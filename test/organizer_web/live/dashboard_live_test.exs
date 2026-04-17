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

      assert {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#action-strip")
      assert has_element?(view, "#quick-bulk")
      assert has_element?(view, "#bulk-capture-form")
      assert has_element?(view, "#analytics-panel")
      assert has_element?(view, "#chart-progress")
      assert has_element?(view, "#chart-finance")
    end
  end

  describe "quick capture" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        scope: user_scope_fixture(user)
      }
    end

    test "renders copy/paste capture by default", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#bulk-capture-form")
    end

    test "imports mixed items through copy/paste mode", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      today = Date.to_iso8601(Date.utc_today())

      payload = """
      tarefa: Comprar ração | data=#{today} | prioridade=alta
      financeiro: tipo=despesa | natureza=fixa | pagamento=credito | valor=125,90 | categoria=pet | data=#{today}
      meta: Reserva viagem | horizonte=medio | alvo=200000
      """

      view
      |> form("#bulk-capture-form", %{"bulk" => %{"payload" => payload}})
      |> render_submit()

      assert_push_event(view, "form:reset", %{id: "bulk-capture-form"})
      assert has_element?(view, "#bulk-capture-result")

      {:ok, tasks} = Planning.list_tasks(scope, %{})
      {:ok, finances} = Planning.list_finance_entries(scope, %{})
      {:ok, goals} = Planning.list_goals(scope, %{})

      assert Enum.any?(tasks, &(&1.title == "Comprar ração"))

      assert Enum.any?(finances, fn entry ->
               entry.category == "pet" and
                 entry.amount_cents == 12_590 and
                 entry.expense_profile == :fixed and
                 entry.payment_method == :credit
             end)

      assert Enum.any?(goals, &(&1.title == "Reserva viagem"))
    end

    test "applies a quick template in copy/paste mode", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("#bulk-template-mixed")
      |> render_click()

      view
      |> element("#bulk-capture-form")
      |> render_submit()

      {:ok, tasks} = Planning.list_tasks(scope, %{})
      {:ok, finances} = Planning.list_finance_entries(scope, %{})
      {:ok, goals} = Planning.list_goals(scope, %{})

      assert Enum.any?(tasks, &String.contains?(&1.title, "reunião com equipe"))
      assert Enum.any?(finances, &(&1.kind == :expense and &1.category == "almoço"))
      assert Enum.any?(goals, &(&1.title == "aprender Elixir"))
    end

    test "previews lines without creating records", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      today = Date.to_iso8601(Date.utc_today())

      {:ok, tasks_before} = Planning.list_tasks(scope, %{})

      payload = """
      tarefa: Task só preview | data=#{today} | prioridade=alta
      inválido sem dois pontos
      """

      view
      |> element("#bulk-capture-form")
      |> render_submit(%{"bulk" => %{"payload" => payload}, "action" => "preview"})

      assert has_element?(view, "#bulk-capture-preview")
      refute has_element?(view, "#bulk-capture-result")

      {:ok, tasks_after} = Planning.list_tasks(scope, %{})
      assert length(tasks_after) == length(tasks_before)
    end

    test "applies guided fix to invalid preview line", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      {:ok, tasks_before} = Planning.list_tasks(scope, %{})

      payload = """
      tarefa Comprar leite
      """

      view
      |> element("#bulk-capture-form")
      |> render_submit(%{"bulk" => %{"payload" => payload}, "action" => "preview"})

      assert has_element?(view, "#bulk-fix-line-1")

      view
      |> element("#bulk-fix-line-1")
      |> render_click()

      refute has_element?(view, "#bulk-fix-line-1")

      view
      |> form("#bulk-capture-form", %{"bulk" => %{"payload" => "tarefa: Comprar leite"}})
      |> render_submit()

      assert has_element?(view, "#bulk-capture-result")

      {:ok, tasks_after} = Planning.list_tasks(scope, %{})
      assert length(tasks_after) == length(tasks_before) + 1
    end

    test "applies all guided fixes in one action", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      {:ok, tasks_before} = Planning.list_tasks(scope, %{})

      payload = """
      tarefa Comprar leite
      tarefa Pagar conta
      """

      view
      |> element("#bulk-capture-form")
      |> render_submit(%{"bulk" => %{"payload" => payload}, "action" => "preview"})

      assert has_element?(view, "#bulk-fix-all-btn")

      view
      |> element("#bulk-fix-all-btn")
      |> render_click()

      refute has_element?(view, "#bulk-fix-all-btn")

      view
      |> form("#bulk-capture-form", %{
        "bulk" => %{"payload" => "tarefa: Comprar leite\ntarefa: Pagar conta"}
      })
      |> render_submit()

      assert has_element?(view, "#bulk-capture-result")

      {:ok, tasks_after} = Planning.list_tasks(scope, %{})
      assert length(tasks_after) == length(tasks_before) + 2
    end

    test "undoes the last bulk import", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      today = Date.to_iso8601(Date.utc_today())

      payload = """
      tarefa: Item para desfazer | data=#{today} | prioridade=media
      financeiro: tipo=despesa | valor=8900 | categoria=teste | data=#{today}
      """

      view
      |> form("#bulk-capture-form", %{
        "bulk" => %{"payload" => payload}
      })
      |> render_submit()

      assert has_element?(view, "#bulk-undo-btn")

      view
      |> element("#bulk-undo-btn")
      |> render_click()

      refute has_element?(view, "#bulk-capture-result")
      refute has_element?(view, "#bulk-capture-preview")

      {:ok, tasks_after} = Planning.list_tasks(scope, %{})
      assert Enum.all?(tasks_after, &(&1.title != "Item para desfazer"))
    end

    test "strict mode blocks import when there are invalid lines", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      today = Date.to_iso8601(Date.utc_today())

      {:ok, tasks_before} = Planning.list_tasks(scope, %{})

      view
      |> element("#bulk-strict-toggle")
      |> render_click()

      payload = """
      tarefa: Item válido em estrito | data=#{today} | prioridade=alta
      inválido sem dois pontos
      """

      view
      |> form("#bulk-capture-form", %{"bulk" => %{"payload" => payload}})
      |> render_submit()

      assert has_element?(view, "#bulk-capture-preview")
      refute has_element?(view, "#bulk-capture-result")

      {:ok, tasks_after} = Planning.list_tasks(scope, %{})
      assert length(tasks_after) == length(tasks_before)
    end

    test "normalizes tolerant date, amount and priority inputs", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      payload = """
      tarefa: Ajustar parser | data=15-04-2026 | prioridade=urgente
      financeiro: tipo=despesa | natureza=variavel | pagamento=debito | valor=R$ 1.234,56 | categoria=moradia | data=15/04/2026
      meta: Meta com alvo | horizonte=médio | alvo=10.000 | data=2026/12/01
      """

      view
      |> form("#bulk-capture-form", %{"bulk" => %{"payload" => payload}})
      |> render_submit()

      {:ok, tasks} = Planning.list_tasks(scope, %{})
      {:ok, finances} = Planning.list_finance_entries(scope, %{})
      {:ok, goals} = Planning.list_goals(scope, %{})

      task = Enum.find(tasks, &(&1.title == "Ajustar parser"))
      assert task
      assert task.priority == :high
      assert Date.to_iso8601(task.due_on) == "2026-04-15"

      finance = Enum.find(finances, &(&1.category == "moradia" and &1.amount_cents == 123_456))
      assert finance
      assert Date.to_iso8601(finance.occurred_on) == "2026-04-15"
      assert finance.expense_profile == :variable
      assert finance.payment_method == :debit

      goal = Enum.find(goals, &(&1.title == "Meta com alvo"))
      assert goal
      assert goal.target_value == 10_000
      assert Date.to_iso8601(goal.due_on) == "2026-12-01"
    end

    test "manages template favorites and payload history", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("#bulk-template-fav-mixed")
      |> render_click()

      assert has_element?(view, "#bulk-template-fav-mixed span.hero-star-solid")

      payload = "tarefa: Payload para histórico"

      view
      |> element("#bulk-capture-form")
      |> render_submit(%{"bulk" => %{"payload" => payload}, "action" => "preview"})

      assert has_element?(view, "#bulk-history")
      assert has_element?(view, "[id^='bulk-history-load-']")

      view
      |> element("[id^='bulk-history-load-']")
      |> render_click()

      assert render(view) =~ payload
    end

    test "imports incrementally by block with diff preview", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      payload = """
      tarefa: Bloco tarefa 1 | prioridade=alta
      tarefa: Bloco tarefa 2 | prioridade=media
      tarefa: Bloco tarefa 3 | prioridade=baixa
      """

      view
      |> element("#bulk-capture-form")
      |> render_submit(%{"bulk" => %{"payload" => payload}, "action" => "preview"})

      assert has_element?(view, "#bulk-block-diff")

      view
      |> element("#bulk-block-size-2")
      |> render_click()

      view
      |> element("#bulk-import-block-btn")
      |> render_click()

      {:ok, tasks_after_first} = Planning.list_tasks(scope, %{})
      assert length(tasks_after_first) == 2
      refute Enum.any?(tasks_after_first, &(&1.title == "Bloco tarefa 3"))

      view
      |> element("#bulk-import-block-btn")
      |> render_click()

      {:ok, tasks_after_second} = Planning.list_tasks(scope, %{})
      assert length(tasks_after_second) == 3
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

      assert {:ok, updated_task} = Planning.get_task(scope, task.id)
      assert updated_task.title == "Task atualizada"
      assert updated_task.priority == :high
      assert updated_task.status == :in_progress

      view
      |> element("#task-delete-btn-#{task.id}")
      |> render_click()

      assert {:error, :not_found} = Planning.get_task(scope, task.id)
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
          "expense_profile" => "",
          "payment_method" => "",
          "amount_cents" => 9000,
          "category" => "freela",
          "occurred_on" => Date.to_iso8601(Date.utc_today()),
          "description" => "projeto extra"
        }
      })
      |> render_submit()

      assert {:ok, updated_entry} = Planning.get_finance_entry(scope, entry.id)
      assert updated_entry.kind == :income
      assert updated_entry.category == "freela"
      assert updated_entry.amount_cents == 9000

      view
      |> element("#finance-edit-btn-#{entry.id}")
      |> render_click()

      view
      |> form("#finance-edit-form-#{entry.id}", %{
        "_id" => to_string(entry.id),
        "finance" => %{
          "kind" => "expense",
          "expense_profile" => "fixed",
          "payment_method" => "credit",
          "amount_cents" => 9500,
          "category" => "assinatura",
          "occurred_on" => Date.to_iso8601(Date.utc_today()),
          "description" => "plano anual"
        }
      })
      |> render_submit()

      assert {:ok, expense_entry} = Planning.get_finance_entry(scope, entry.id)
      assert expense_entry.kind == :expense
      assert expense_entry.expense_profile == :fixed
      assert expense_entry.payment_method == :credit

      view
      |> element("#finance-delete-btn-#{entry.id}")
      |> render_click()

      assert {:error, :not_found} = Planning.get_finance_entry(scope, entry.id)
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

      assert {:ok, updated_goal} = Planning.get_goal(scope, goal.id)
      assert updated_goal.title == "Meta atualizada"
      assert updated_goal.status == :paused
      assert updated_goal.horizon == :medium
      assert updated_goal.target_value == 200

      view
      |> element("#goal-delete-btn-#{goal.id}")
      |> render_click()

      assert {:error, :not_found} = Planning.get_goal(scope, goal.id)
    end

    test "filters tasks by status and priority", %{conn: conn, scope: scope} do
      assert {:ok, done_task} =
               Planning.create_task(scope, %{
                 "title" => "Task feita",
                 "priority" => "high",
                 "status" => "done"
               })

      assert {:ok, open_task} =
               Planning.create_task(scope, %{
                 "title" => "Task aberta",
                 "priority" => "low",
                 "status" => "todo"
               })

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#task-filters", %{"filters" => %{"status" => "done", "priority" => "high"}})
      |> render_change()

      assert has_element?(view, "#task-edit-btn-#{done_task.id}")
      refute has_element?(view, "#task-edit-btn-#{open_task.id}")
    end

    test "filters finance entries by period", %{conn: conn, scope: scope} do
      assert {:ok, recent_entry} =
               Planning.create_finance_entry(scope, %{
                 "kind" => "expense",
                 "amount_cents" => 1100,
                 "category" => "recente",
                 "occurred_on" => Date.to_iso8601(Date.utc_today())
               })

      old_date = Date.utc_today() |> Date.add(-45) |> Date.to_iso8601()

      assert {:ok, old_entry} =
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

      assert has_element?(view, "#finance-edit-btn-#{recent_entry.id}")
      refute has_element?(view, "#finance-edit-btn-#{old_entry.id}")
    end

    test "filters goals by status", %{conn: conn, scope: scope} do
      assert {:ok, active_goal} =
               Planning.create_goal(scope, %{
                 "title" => "Meta ativa",
                 "horizon" => "short",
                 "status" => "active"
               })

      assert {:ok, paused_goal} =
               Planning.create_goal(scope, %{
                 "title" => "Meta pausada",
                 "horizon" => "long",
                 "status" => "paused"
               })

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#goal-filters", %{"filters" => %{"status" => "paused"}})
      |> render_change()

      assert has_element?(view, "#goal-edit-btn-#{paused_goal.id}")
      refute has_element?(view, "#goal-edit-btn-#{active_goal.id}")
    end

    test "applies finance template for quick copy/paste capture", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      {:ok, finance_entries_before} = Planning.list_finance_entries(scope, %{})

      view
      |> element("#bulk-template-finance")
      |> render_click()

      view
      |> element("#bulk-capture-form")
      |> render_submit()

      {:ok, finance_entries} = Planning.list_finance_entries(scope, %{})
      assert length(finance_entries) > length(finance_entries_before)
      assert Enum.any?(finance_entries, &(&1.kind == :expense))
      assert Enum.any?(finance_entries, &(&1.kind == :income))
    end

    test "updates analytics filters through chips", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#analytics-days-30.btn-primary")
      assert has_element?(view, "#analytics-capacity-10.btn-primary")

      view
      |> element("#analytics-days-7")
      |> render_click()

      view
      |> element("#analytics-capacity-20")
      |> render_click()

      assert has_element?(view, "#analytics-days-7.btn-primary")
      assert has_element?(view, "#analytics-capacity-20.btn-primary")
    end

    test "does not render onboarding card", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      refute has_element?(view, "h2", "Configuração inicial em 2 passos")
    end
  end
end
