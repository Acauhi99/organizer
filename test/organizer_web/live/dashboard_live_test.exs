defmodule OrganizerWeb.DashboardLiveTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Organizer.DateSupport
  alias Organizer.Planning

  @funnel_event [:organizer, :product, :funnel, :step]

  defp create_expense_entry(scope, attrs) do
    {:ok, entry} = Planning.create_finance_entry(scope, attrs)
    entry
  end

  defp attach_funnel_listener do
    handler_id = "dashboard-live-test-funnel-#{System.unique_integer([:positive, :monotonic])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @funnel_event,
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:funnel_event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  defp drain_funnel_events do
    receive do
      {:funnel_event, _, _} -> drain_funnel_events()
    after
      0 -> :ok
    end
  end

  describe "flash feedback pattern" do
    test "quick finance creation shows happened + next step feedback", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/finances")

      today = DateSupport.format_pt_br(Date.utc_today())

      view
      |> form("#quick-finance-form", %{
        "quick_finance" => %{
          "kind" => "expense",
          "amount_cents" => "125,90",
          "category" => "Alimentação",
          "description" => "Mercado semanal",
          "occurred_on" => today,
          "expense_profile" => "variable",
          "payment_method" => "debit"
        }
      })
      |> render_submit()

      assert render(view) =~ "Lançamento registrado."

      assert render(view) =~
               "Próximo passo: Revise os detalhes na lista abaixo e ajuste se necessário."
    end

    test "delete confirmation event shows happened + next step feedback", %{conn: conn} do
      user = user_fixture()
      scope = user_scope_fixture(user)
      conn = log_in_user(conn, user)

      entry =
        create_expense_entry(scope, %{
          "description" => "Despesa protegida",
          "amount_cents" => 15_000,
          "kind" => "expense",
          "category" => "Categoria",
          "occurred_on" => Date.to_iso8601(Date.utc_today())
        })

      {:ok, view, _html} = live(conn, ~p"/finances")

      render_hook(view, "delete_finance", %{"id" => to_string(entry.id)})

      assert render(view) =~ "Confirmação necessária para excluir o lançamento."
      assert render(view) =~ "Próximo passo: Revise os dados no modal e confirme para continuar."
    end
  end

  describe "finances list pagination" do
    test "delete event opens confirmation before removing entry", %{conn: conn} do
      user = user_fixture()
      scope = user_scope_fixture(user)
      conn = log_in_user(conn, user)

      entry =
        create_expense_entry(scope, %{
          "description" => "Despesa protegida",
          "amount_cents" => 15_000,
          "kind" => "expense",
          "category" => "Categoria",
          "occurred_on" => Date.to_iso8601(Date.utc_today())
        })

      {:ok, view, _html} = live(conn, ~p"/finances")

      assert has_element?(view, "#finance-delete-btn-#{entry.id}")

      render_hook(view, "delete_finance", %{"id" => to_string(entry.id)})

      assert has_element?(view, "#finance-delete-confirmation-modal")
      assert has_element?(view, "#finance-delete-btn-#{entry.id}")

      view
      |> element("#finance-delete-confirm-btn")
      |> render_click()

      refute has_element?(view, "#finance-delete-btn-#{entry.id}")
    end

    test "resets to first page after deleting an entry", %{conn: conn} do
      user = user_fixture()
      scope = user_scope_fixture(user)
      conn = log_in_user(conn, user)

      entries =
        Enum.map(0..20, fn offset ->
          create_expense_entry(scope, %{
            "description" => "Despesa #{offset}",
            "amount_cents" => 10_000 + offset,
            "kind" => "expense",
            "category" => "Categoria",
            "occurred_on" => Date.to_iso8601(Date.add(Date.utc_today(), -offset))
          })
        end)

      latest_entry = hd(entries)
      oldest_entry = List.last(entries)

      {:ok, view, _html} = live(conn, ~p"/finances")

      render_hook(view, "load_more_finances", %{"page" => 2})
      render_hook(view, "load_more_finances", %{"page" => 3})

      assert has_element?(view, "#finance-delete-btn-#{oldest_entry.id}")

      view
      |> element("#finance-delete-btn-#{oldest_entry.id}")
      |> render_click()

      view
      |> element("#finance-delete-confirm-btn")
      |> render_click()

      assert has_element?(view, "#finance-delete-btn-#{latest_entry.id}")
      refute has_element?(view, "#finance-delete-btn-#{oldest_entry.id}")
    end
  end

  describe "funnel telemetry" do
    test "emits start and success for quick finance create", %{conn: conn} do
      attach_funnel_listener()
      drain_funnel_events()

      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/finances")

      today = DateSupport.format_pt_br(Date.utc_today())

      view
      |> form("#quick-finance-form", %{
        "quick_finance" => %{
          "kind" => "expense",
          "amount_cents" => "125,90",
          "category" => "Alimentação",
          "description" => "Mercado semanal",
          "occurred_on" => today,
          "expense_profile" => "variable",
          "payment_method" => "debit"
        }
      })
      |> render_submit()

      assert_receive {:funnel_event, %{count: 1},
                      %{journey: "finances", action: "quick_finance_create", outcome: "start"}}

      assert_receive {:funnel_event, %{count: 1},
                      %{journey: "finances", action: "quick_finance_create", outcome: "success"}}
    end

    test "emits start and cancel for finance delete confirmation flow", %{conn: conn} do
      attach_funnel_listener()
      drain_funnel_events()

      user = user_fixture()
      scope = user_scope_fixture(user)
      conn = log_in_user(conn, user)

      entry =
        create_expense_entry(scope, %{
          "description" => "Despesa protegida",
          "amount_cents" => 15_000,
          "kind" => "expense",
          "category" => "Categoria",
          "occurred_on" => Date.to_iso8601(Date.utc_today())
        })

      {:ok, view, _html} = live(conn, ~p"/finances")

      render_hook(view, "prompt_delete_finance", %{"id" => to_string(entry.id)})
      render_hook(view, "cancel_delete_finance", %{})

      assert_receive {:funnel_event, %{count: 1},
                      %{journey: "finances", action: "finance_delete", outcome: "start"}}

      assert_receive {:funnel_event, %{count: 1},
                      %{journey: "finances", action: "finance_delete", outcome: "cancel"}}
    end
  end
end
