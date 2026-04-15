defmodule OrganizerWeb.DashboardLiveTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Organizer.Planning

  describe "access" do
    test "redirects unauthenticated users", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/dashboard")
    end

    test "renders for authenticated users", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      assert {:ok, _view, html} = live(conn, ~p"/dashboard")
      assert html =~ "Painel Diário"
      assert html =~ "Captura rápida de tarefa"
    end
  end

  describe "quick add" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        scope: user_scope_fixture(user)
      }
    end

    test "adds a task inline", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      today = Date.to_iso8601(Date.utc_today())

      view
      |> form("#task-form", %{
        "task" => %{"title" => "Revisar metas da semana", "priority" => "high", "due_on" => today}
      })
      |> render_submit()

      assert render(view) =~ "Revisar metas da semana"
    end

    test "edits and deletes a task inline", %{conn: conn, scope: scope} do
      assert {:ok, task} =
               Planning.create_task(scope, %{"title" => "Task original", "priority" => "low"})

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("#task-edit-btn-#{task.id}")
      |> render_click()

      view
      |> form("#task-edit-form-#{task.id}", %{
        "_id" => to_string(task.id),
        "task" => %{
          "title" => "Task atualizada",
          "priority" => "high",
          "status" => "in_progress",
          "due_on" => Date.to_iso8601(Date.utc_today())
        }
      })
      |> render_submit()

      assert render(view) =~ "Task atualizada"

      view
      |> element("#task-delete-btn-#{task.id}")
      |> render_click()

      refute render(view) =~ "Task atualizada"
    end

    test "edits and deletes a finance entry inline", %{conn: conn, scope: scope} do
      assert {:ok, entry} =
               Planning.create_finance_entry(scope, %{
                 "kind" => "expense",
                 "amount_cents" => 2500,
                 "category" => "mercado",
                 "occurred_on" => Date.to_iso8601(Date.utc_today())
               })

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("#finance-edit-btn-#{entry.id}")
      |> render_click()

      view
      |> form("#finance-edit-form-#{entry.id}", %{
        "_id" => to_string(entry.id),
        "finance" => %{
          "kind" => "income",
          "amount_cents" => 9000,
          "category" => "freela",
          "occurred_on" => Date.to_iso8601(Date.utc_today()),
          "description" => "projeto extra"
        }
      })
      |> render_submit()

      assert render(view) =~ "freela"

      view
      |> element("#finance-delete-btn-#{entry.id}")
      |> render_click()

      refute render(view) =~ "freela"
    end

    test "edits and deletes a goal inline", %{conn: conn, scope: scope} do
      assert {:ok, goal} =
               Planning.create_goal(scope, %{
                 "title" => "Meta original",
                 "horizon" => "short",
                 "status" => "active",
                 "target_value" => 100
               })

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("#goal-edit-btn-#{goal.id}")
      |> render_click()

      view
      |> form("#goal-edit-form-#{goal.id}", %{
        "_id" => to_string(goal.id),
        "goal" => %{
          "title" => "Meta atualizada",
          "horizon" => "medium",
          "status" => "paused",
          "target_value" => 200,
          "current_value" => 50,
          "due_on" => Date.to_iso8601(Date.utc_today()),
          "notes" => "ajustada"
        }
      })
      |> render_submit()

      assert render(view) =~ "Meta atualizada"

      view
      |> element("#goal-delete-btn-#{goal.id}")
      |> render_click()

      refute render(view) =~ "Meta atualizada"
    end

    test "filters tasks by status and priority", %{conn: conn, scope: scope} do
      assert {:ok, _} =
               Planning.create_task(scope, %{
                 "title" => "Task feita",
                 "priority" => "high",
                 "status" => "done"
               })

      assert {:ok, _} =
               Planning.create_task(scope, %{
                 "title" => "Task aberta",
                 "priority" => "low",
                 "status" => "todo"
               })

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#task-filters", %{"filters" => %{"status" => "done", "priority" => "high"}})
      |> render_change()

      filtered_html = render(view)
      assert filtered_html =~ "Task feita"
      refute filtered_html =~ "Task aberta"
    end

    test "filters finance entries by period", %{conn: conn, scope: scope} do
      assert {:ok, _} =
               Planning.create_finance_entry(scope, %{
                 "kind" => "expense",
                 "amount_cents" => 1100,
                 "category" => "recente",
                 "occurred_on" => Date.to_iso8601(Date.utc_today())
               })

      old_date = Date.utc_today() |> Date.add(-45) |> Date.to_iso8601()

      assert {:ok, _} =
               Planning.create_finance_entry(scope, %{
                 "kind" => "expense",
                 "amount_cents" => 2200,
                 "category" => "antiga",
                 "occurred_on" => old_date
               })

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#finance-filters", %{"filters" => %{"days" => "7"}})
      |> render_change()

      filtered_html = render(view)
      assert filtered_html =~ "recente"
      refute filtered_html =~ "antiga"
    end

    test "filters goals by status", %{conn: conn, scope: scope} do
      assert {:ok, _} =
               Planning.create_goal(scope, %{
                 "title" => "Meta ativa",
                 "horizon" => "short",
                 "status" => "active"
               })

      assert {:ok, _} =
               Planning.create_goal(scope, %{
                 "title" => "Meta pausada",
                 "horizon" => "long",
                 "status" => "paused"
               })

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#goal-filters", %{"filters" => %{"status" => "paused"}})
      |> render_change()

      filtered_html = render(view)
      assert filtered_html =~ "Meta pausada"
      refute filtered_html =~ "Meta ativa"
    end

    test "applies finance category preset for quick capture", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("#finance-category-preset-moradia")
      |> render_click()

      assert has_element?(view, "#finance_category[value=\"moradia\"]")
    end

    test "hides onboarding after first finance category and first goal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert render(view) =~ "Configuração inicial em 2 passos"
      assert render(view) =~ "Configurar categorias financeiras"

      view
      |> form("#finance-form", %{
        "finance" => %{
          "kind" => "expense",
          "amount_cents" => 1400,
          "category" => "mercado",
          "occurred_on" => Date.to_iso8601(Date.utc_today())
        }
      })
      |> render_submit()

      assert render(view) =~ "Configuração inicial em 2 passos"

      view
      |> form("#goal-form", %{
        "goal" => %{
          "title" => "Primeira meta",
          "horizon" => "short",
          "target_value" => 5000
        }
      })
      |> render_submit()

      refute render(view) =~ "Configuração inicial em 2 passos"
    end
  end
end
