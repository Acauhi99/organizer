defmodule OrganizerWeb.DashboardLiveTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Organizer.Planning
  alias Organizer.SharedFinance

  describe "access" do
    test "redirects unauthenticated users", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/finances")
    end

    test "renders for authenticated users", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/finances")
      assert has_element?(view, "#quick-finance-form")
      assert has_element?(view, "#finance-metrics-panel")
      assert has_element?(view, "#finance-operations-panel")
      assert has_element?(view, "#notification-permission-modal")
      assert has_element?(view, "#notification-permission-allow")
      refute has_element?(view, "#task-timer-box")
      refute has_element?(view, "#task-operations-panel")
    end

    test "renders modular authenticated routes", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      assert {:ok, finances, _html} = live(conn, ~p"/finances")
      assert has_element?(finances, "#finances-page-hero")
      assert has_element?(finances, "#quick-finance-form")
      assert has_element?(finances, "#finance-filters")

      assert {:ok, tasks, _html} = live(conn, ~p"/tasks")
      assert has_element?(tasks, "#tasks-page-hero")
      assert has_element?(tasks, "#quick-task-form")
      assert has_element?(tasks, "#task-focus-timer")
      assert has_element?(tasks, "#task-metrics-panel")
      assert has_element?(tasks, "#task-operations-panel")
    end

    test "analytics route was removed", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      conn = get(conn, "/analytics")
      assert html_response(conn, 404)
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

    test "creates expense through quick finance form", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/finances")
      today = Date.to_iso8601(Date.utc_today())

      view
      |> form("#quick-finance-form", %{
        "quick_finance" => %{
          "kind" => "expense",
          "amount_cents" => "123,45",
          "category" => "Alimentação",
          "description" => "mercado",
          "occurred_on" => today,
          "expense_profile" => "variable",
          "payment_method" => "debit"
        }
      })
      |> render_submit()

      {:ok, finances} = Planning.list_finance_entries(scope, %{})

      assert Enum.any?(finances, fn entry ->
               entry.kind == :expense and
                 entry.amount_cents == 12_345 and
                 entry.category == "Alimentação" and
                 entry.payment_method == :debit
             end)
    end

    test "shows quick finance sharing controls disabled when user has no links", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")

      assert has_element?(view, "#quick-finance-share-controls")
      assert has_element?(view, "#quick-finance-share-with-link[disabled]")
      assert has_element?(view, "#quick-finance-share-link-id[disabled]")
    end

    test "creates quick expense from decimal amount and shares with linked account", %{
      conn: conn,
      scope: scope
    } do
      linked_user = user_fixture()
      linked_scope = user_scope_fixture(linked_user)
      {:ok, invite} = SharedFinance.create_invite(scope)
      {:ok, link} = SharedFinance.accept_invite(linked_scope, invite.token)

      {:ok, view, _html} = live(conn, ~p"/finances")
      today = Date.to_iso8601(Date.utc_today())

      view
      |> form("#quick-finance-form", %{
        "quick_finance" => %{
          "kind" => "expense",
          "amount_cents" => "182.54",
          "category" => "Alimentação",
          "description" => "mercado compartilhado",
          "occurred_on" => today,
          "expense_profile" => "variable",
          "payment_method" => "debit",
          "share_with_link" => "true"
        }
      })
      |> render_submit()

      {:ok, finances} = Planning.list_finance_entries(scope, %{})

      assert Enum.any?(finances, fn entry ->
               entry.kind == :expense and
                 entry.amount_cents == 18_254 and
                 entry.category == "Alimentação" and
                 entry.shared_with_link_id == link.id
             end)
    end

    test "creates quick shared expense with manual split mode", %{conn: conn, scope: scope} do
      linked_user = user_fixture()
      linked_scope = user_scope_fixture(linked_user)
      {:ok, invite} = SharedFinance.create_invite(scope)
      {:ok, link} = SharedFinance.accept_invite(linked_scope, invite.token)

      {:ok, view, _html} = live(conn, ~p"/finances")
      today = Date.to_iso8601(Date.utc_today())

      view
      |> form("#quick-finance-form", %{
        "quick_finance" => %{
          "kind" => "expense",
          "amount_cents" => "500",
          "category" => "Moradia",
          "description" => "aluguel compartilhado",
          "occurred_on" => today,
          "expense_profile" => "fixed",
          "payment_method" => "debit",
          "share_with_link" => "true"
        }
      })
      |> render_change()

      view
      |> form("#quick-finance-form", %{
        "quick_finance" => %{
          "kind" => "expense",
          "amount_cents" => "500",
          "category" => "Moradia",
          "description" => "aluguel compartilhado",
          "occurred_on" => today,
          "expense_profile" => "fixed",
          "payment_method" => "debit",
          "share_with_link" => "true",
          "shared_with_link_id" => to_string(link.id),
          "shared_split_mode" => "manual"
        }
      })
      |> render_change()

      view
      |> form("#quick-finance-form", %{
        "quick_finance" => %{
          "kind" => "expense",
          "amount_cents" => "500",
          "category" => "Moradia",
          "description" => "aluguel compartilhado",
          "occurred_on" => today,
          "expense_profile" => "fixed",
          "payment_method" => "debit",
          "share_with_link" => "true",
          "shared_with_link_id" => to_string(link.id),
          "shared_split_mode" => "manual",
          "shared_manual_mine_amount" => "200"
        }
      })
      |> render_submit()

      {:ok, finances} = Planning.list_finance_entries(scope, %{})

      assert Enum.any?(finances, fn entry ->
               entry.kind == :expense and
                 entry.amount_cents == 50_000 and
                 entry.shared_with_link_id == link.id and
                 entry.shared_split_mode == :manual and
                 entry.shared_manual_mine_cents == 20_000
             end)
    end

    test "applies quick preset for income", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")

      view
      |> element("#quick-preset-income-salary")
      |> render_click()

      assert has_element?(
               view,
               "#quick-finance-form select[name='quick_finance[kind]'] option[value='income'][selected]"
             )
    end

    test "highlights only selected expense preset", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")

      view
      |> element("#quick-preset-expense-fixed")
      |> render_click()

      assert has_element?(view, "#quick-preset-expense-fixed.btn-primary")
      refute has_element?(view, "#quick-preset-expense-variable.btn-primary")
    end

    test "creates task through quick task form", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/tasks")
      today = Date.to_iso8601(Date.utc_today())

      view
      |> form("#quick-task-form", %{
        "quick_task" => %{
          "title" => "Fechar conciliação bancária",
          "priority" => "high",
          "status" => "in_progress",
          "due_on" => today,
          "notes" => "Prioridade da manhã"
        }
      })
      |> render_submit()

      {:ok, tasks} = Planning.list_tasks(scope, %{})

      assert Enum.any?(tasks, fn task ->
               task.title == "Fechar conciliação bancária" and
                 task.priority == :high and
                 task.status == :in_progress
             end)
    end

    test "edits and deletes a task inline", %{conn: conn, scope: scope} do
      assert {:ok, task} =
               Planning.create_task(scope, %{"title" => "Task original", "priority" => "low"})

      {:ok, view, _html} = live(conn, ~p"/tasks")

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

    test "opens and closes task details modal from kanban card", %{conn: conn, scope: scope} do
      assert {:ok, task} =
               Planning.create_task(scope, %{
                 "title" => "Tarefa com detalhes",
                 "priority" => "high",
                 "notes" => "Primeira linha\nSegunda linha completa"
               })

      {:ok, view, _html} = live(conn, ~p"/tasks")

      refute has_element?(view, "#task-details-modal")

      view
      |> element("#task-details-btn-#{task.id}")
      |> render_click()

      assert has_element?(view, "#task-details-modal")
      assert has_element?(view, "#task-details-title")
      assert has_element?(view, "#task-details-edit-btn-#{task.id}")
      assert has_element?(view, "#task-details-modal-backdrop")
      assert render(view) =~ "Segunda linha completa"

      refute render(view) =~ ~r/id="task-details-modal-backdrop"[^>]*phx-click=/

      view
      |> element("#task-details-close-btn")
      |> render_click()

      refute has_element?(view, "#task-details-modal")
    end

    test "auto-detects task note links as clickable anchors in card and modal", %{
      conn: conn,
      scope: scope
    } do
      notes = "Links: https://grafana.example.com/dashboard e www.claude.ai/share/abc123"

      assert {:ok, task} =
               Planning.create_task(scope, %{
                 "title" => "Links clicáveis",
                 "priority" => "medium",
                 "notes" => notes
               })

      {:ok, view, _html} = live(conn, ~p"/tasks")

      assert has_element?(
               view,
               "#tasks-todo-#{task.id} a[href=\"https://grafana.example.com/dashboard\"]"
             )

      assert has_element?(
               view,
               "#tasks-todo-#{task.id} a[href=\"https://www.claude.ai/share/abc123\"]"
             )

      view
      |> element("#task-details-btn-#{task.id}")
      |> render_click()

      assert has_element?(
               view,
               "#task-details-notes a[href=\"https://grafana.example.com/dashboard\"]"
             )

      assert has_element?(
               view,
               "#task-details-notes a[href=\"https://www.claude.ai/share/abc123\"]"
             )
    end

    test "moves task status quickly through kanban actions", %{conn: conn, scope: scope} do
      assert {:ok, task} =
               Planning.create_task(scope, %{"title" => "Mover status", "priority" => "medium"})

      {:ok, view, _html} = live(conn, ~p"/tasks")

      view
      |> element("#task-status-quick-btn-#{task.id}")
      |> render_click()

      task_id = task.id
      task_title = task.title

      assert_push_event(view, "task_focus_sync_target", %{
        task_id: ^task_id,
        task_title: ^task_title
      })

      assert {:ok, task_in_progress} = Planning.get_task(scope, task.id)
      assert task_in_progress.status == :in_progress

      view
      |> element("#task-status-quick-btn-#{task.id}")
      |> render_click()

      assert {:ok, task_done} = Planning.get_task(scope, task.id)
      assert task_done.status == :done
      refute is_nil(task_done.completed_at)
    end

    test "shares a task with linked account from kanban card", %{conn: conn, scope: scope} do
      linked_user = user_fixture()
      linked_scope = user_scope_fixture(linked_user)
      {:ok, invite} = SharedFinance.create_invite(scope)
      {:ok, link} = SharedFinance.accept_invite(linked_scope, invite.token)

      assert {:ok, task} =
               Planning.create_task(scope, %{
                 "title" => "Compartilhar no compartilhamento",
                 "priority" => "high",
                 "notes" => "Validar com a outra conta"
               })

      assert {:ok, _check_item} =
               Planning.add_task_checklist_item(scope, task.id, %{"label" => "Primeira etapa"})

      {:ok, view, _html} = live(conn, ~p"/tasks")

      view
      |> form("#task-share-form-#{task.id}", %{
        "task_id" => to_string(task.id),
        "share_task" => %{
          "attach_to_link" => "true",
          "link_id" => to_string(link.id)
        }
      })
      |> render_submit()

      {:ok, linked_tasks} = Planning.list_tasks(linked_scope, %{"days" => "30"})

      assert Enum.any?(linked_tasks, fn linked_task ->
               linked_task.title == "Compartilhar no compartilhamento" and
                 linked_task.status == :todo and
                 linked_task.notes =~ "Compartilhada por"
             end)

      view
      |> element("#task-status-quick-btn-#{task.id}")
      |> render_click()

      {:ok, linked_tasks_after_status_change} =
        Planning.list_tasks(linked_scope, %{"days" => "30"})

      assert Enum.any?(linked_tasks_after_status_change, fn linked_task ->
               linked_task.title == "Compartilhar no compartilhamento" and
                 linked_task.status == :in_progress
             end)
    end

    test "keeps task private when share checkbox is not checked", %{conn: conn, scope: scope} do
      linked_user = user_fixture()
      linked_scope = user_scope_fixture(linked_user)
      {:ok, invite} = SharedFinance.create_invite(scope)
      {:ok, link} = SharedFinance.accept_invite(linked_scope, invite.token)

      assert {:ok, task} =
               Planning.create_task(scope, %{
                 "title" => "Permanecer privada",
                 "priority" => "medium"
               })

      {:ok, view, _html} = live(conn, ~p"/tasks")

      view
      |> form("#task-share-form-#{task.id}", %{
        "task_id" => to_string(task.id),
        "share_task" => %{
          "attach_to_link" => "false",
          "link_id" => to_string(link.id)
        }
      })
      |> render_submit()

      {:ok, linked_tasks} = Planning.list_tasks(linked_scope, %{"days" => "30"})
      refute Enum.any?(linked_tasks, &(&1.title == "Permanecer privada"))
    end

    test "manages checklist items and auto-completes task", %{conn: conn, scope: scope} do
      assert {:ok, task} =
               Planning.create_task(scope, %{"title" => "Compras", "priority" => "medium"})

      {:ok, view, _html} = live(conn, ~p"/tasks")

      view
      |> form("#task-checklist-add-form-#{task.id}", %{
        "task_id" => to_string(task.id),
        "checklist_item" => %{"label" => "Arroz"}
      })
      |> render_submit()

      view
      |> form("#task-checklist-add-form-#{task.id}", %{
        "task_id" => to_string(task.id),
        "checklist_item" => %{"label" => "Feijão"}
      })
      |> render_submit()

      assert {:ok, task_with_items} = Planning.get_task(scope, task.id)
      assert length(task_with_items.checklist_items) == 2

      [first_item | _] = task_with_items.checklist_items

      view
      |> element("#task-checklist-toggle-#{task.id}-#{first_item.id}")
      |> render_click()

      assert {:ok, task_in_progress} = Planning.get_task(scope, task.id)
      assert task_in_progress.status == :in_progress

      item_ids = Enum.map(task_in_progress.checklist_items, & &1.id)

      Enum.each(item_ids, fn item_id ->
        if item_id != first_item.id do
          view
          |> element("#task-checklist-toggle-#{task.id}-#{item_id}")
          |> render_click()
        end
      end)

      assert {:ok, task_done} = Planning.get_task(scope, task.id)
      assert task_done.status == :done
      refute is_nil(task_done.completed_at)
      assert render(view) =~ "Checklist: 2/2 itens concluídos"
    end

    test "edits and deletes a finance entry inline", %{conn: conn, scope: scope} do
      assert {:ok, entry} =
               Planning.create_finance_entry(scope, %{
                 "kind" => "expense",
                 "amount_cents" => 2500,
                 "category" => "mercado",
                 "occurred_on" => Date.to_iso8601(Date.utc_today())
               })

      {:ok, view, _html} = live(conn, ~p"/finances")

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

      {:ok, view, _html} = live(conn, ~p"/tasks")

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

      {:ok, view, _html} = live(conn, ~p"/finances")

      view
      |> form("#finance-filters", %{"filters" => %{"days" => "7"}})
      |> render_change()

      assert has_element?(view, "#finance-edit-btn-#{recent_entry.id}")
      refute has_element?(view, "#finance-edit-btn-#{old_entry.id}")
    end

    test "updates task metrics filters through chips", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tasks")

      assert has_element?(view, "#task-metrics-days-30.btn-primary")
      assert has_element?(view, "#task-metrics-capacity-10.btn-primary")

      view
      |> element("#task-metrics-days-7")
      |> render_click()

      view
      |> element("#task-metrics-capacity-20")
      |> render_click()

      assert has_element?(view, "#task-metrics-days-7.btn-primary")
      assert has_element?(view, "#task-metrics-capacity-20.btn-primary")
    end

    test "updates finance metrics days through chips", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")

      assert has_element?(view, "#finance-metrics-days-30.btn-primary")

      view
      |> element("#finance-metrics-days-7")
      |> render_click()

      assert has_element?(view, "#finance-metrics-days-7.btn-primary")
    end

    test "does not render onboarding card", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")
      refute has_element?(view, "h2", "Configuração inicial em 2 passos")
    end
  end

  describe "panel visibility controls" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "task panels are visible in tasks route", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tasks")
      assert has_element?(view, "#task-metrics-panel")
      assert has_element?(view, "#task-operations-panel")
    end

    test "finance panels are visible in finances route", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")
      assert has_element?(view, "#finance-metrics-panel")
      assert has_element?(view, "#finance-operations-panel")
    end
  end

  describe "onboarding flow" do
    setup %{conn: conn} do
      # user_fixture() creates a new user with no onboarding progress → onboarding is active
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "onboarding overlay is shown for new users", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")
      assert has_element?(view, "#onboarding-overlay")
    end

    test "advances through all 6 onboarding steps", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")

      assert has_element?(view, "#onboarding-overlay")

      # Steps 1-5: click next
      for _step <- 1..5 do
        view |> element("#onboarding-next-btn") |> render_click()
        assert has_element?(view, "#onboarding-overlay")
      end

      # Step 6: clicking next completes onboarding
      view |> element("#onboarding-next-btn") |> render_click()
      refute has_element?(view, "#onboarding-overlay")
    end

    test "skip onboarding dismisses the overlay", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")

      assert has_element?(view, "#onboarding-overlay")

      view |> element("#onboarding-skip-btn") |> render_click()

      refute has_element?(view, "#onboarding-overlay")
    end

    test "dismissed onboarding does not reappear after page reload", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/finances")

      view |> element("#onboarding-skip-btn") |> render_click()
      refute has_element?(view, "#onboarding-overlay")

      # Reload (new session for same user)
      {:ok, view2, _html} = live(log_in_user(conn, user), ~p"/finances")
      refute has_element?(view2, "#onboarding-overlay")
    end

    test "completed onboarding does not reappear after page reload", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/finances")

      # Advance to last step and complete
      for _step <- 1..6 do
        view |> element("#onboarding-next-btn") |> render_click()
      end

      refute has_element?(view, "#onboarding-overlay")

      {:ok, view2, _html} = live(log_in_user(conn, user), ~p"/finances")
      refute has_element?(view2, "#onboarding-overlay")
    end
  end

  describe "empty states" do
    setup %{conn: conn} do
      # New user with no data → empty states should be visible
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "empty state for tasks is shown when user has no tasks", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tasks")
      assert has_element?(view, "#empty-state-tasks")
    end

    test "empty state for finances is shown when user has no finances", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")
      assert has_element?(view, "#empty-state-finances")
    end

    test "quick finance form is available for empty state users", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")

      assert has_element?(view, "#quick-finance-hero")
      assert has_element?(view, "#quick-finance-form")
    end

    test "empty state disappears after creating data", %{conn: conn, user: user} do
      scope = user_scope_fixture(user)

      {:ok, _task} =
        Planning.create_task(scope, %{"title" => "Tarefa teste", "priority" => "low"})

      {:ok, view, _html} = live(conn, ~p"/tasks")

      assert has_element?(view, "#tasks [id^='tasks-']")
    end
  end

  describe "responsive layout" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "dashboard layout grid is rendered", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")
      assert has_element?(view, "#module-keyboard-shortcuts")
    end

    test "finance operation panel is present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")
      assert has_element?(view, "#finance-operations-panel")
    end

    test "task metrics panel is present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tasks")
      assert has_element?(view, "#task-metrics-panel")
    end

    test "toggling task metrics event is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tasks")
      render_click(view, "set_task_metrics_days", %{"days" => "7"})
      assert has_element?(view, "#task-metrics-panel")
    end
  end

  describe "keyboard navigation and accessibility" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user)}
    end

    test "skip links to finance sections are present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")
      assert has_element?(view, "a.skip-link[href='#finance-metrics-panel']")
      assert has_element?(view, "a.skip-link[href='#finance-operations-panel']")
    end

    test "skip links to task sections are present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tasks")
      assert has_element?(view, "a.skip-link[href='#task-metrics-panel']")
      assert has_element?(view, "a.skip-link[href='#task-operations-panel']")
    end

    test "onboarding overlay has role dialog", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")
      assert has_element?(view, "#onboarding-overlay[role='dialog']")
    end

    test "Alt+B shortcut triggers focus scroll event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")

      render_hook(view, "global_shortcut", %{"key" => "b", "altKey" => true})

      assert_push_event(view, "scroll-to-element", %{
        selector: "#quick-finance-hero",
        focus: "#quick-finance-amount"
      })
    end

    test "global shortcut ignores payload without key", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")

      render_hook(view, "global_shortcut", %{"altKey" => true})

      assert has_element?(view, "#quick-finance-form")
    end
  end

  describe "performance" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "finances renders within 2 second budget", %{conn: conn} do
      {time_us, {:ok, _view, _html}} =
        :timer.tc(fn -> live(conn, ~p"/finances") end)

      time_ms = time_us / 1000
      assert time_ms < 2000, "Finances took #{time_ms}ms to render (budget: 2000ms)"
    end

    test "task metrics filter change completes within 200ms budget", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tasks")

      {time_us, _result} =
        :timer.tc(fn ->
          render_click(view, "set_task_metrics_days", %{"days" => "7"})
        end)

      time_ms = time_us / 1000
      assert time_ms < 200, "Task metrics filter took #{time_ms}ms (budget: 200ms)"
    end

    test "tasks renders with large task list within budget", %{conn: conn, user: user} do
      scope = user_scope_fixture(user)

      for i <- 1..55 do
        Planning.create_task(scope, %{
          "title" => "Tarefa de carga #{i}",
          "priority" => "low"
        })
      end

      {time_us, {:ok, _view, _html}} =
        :timer.tc(fn -> live(conn, ~p"/tasks") end)

      time_ms = time_us / 1000
      assert time_ms < 2000, "Dashboard with 55 tasks took #{time_ms}ms (budget: 2000ms)"
    end

    test "task chart containers are shown on initial render", %{conn: conn} do
      # Charts start in loading state and load asynchronously
      # We verify the chart containers are present (they may be loading or loaded)
      {:ok, view, _html} = live(conn, ~p"/tasks")
      assert has_element?(view, "#task-metrics-panel")
      assert has_element?(view, "#chart-task-delivery")
    end

    test "finances renders with large finance list within budget", %{conn: conn, user: user} do
      scope = user_scope_fixture(user)

      for i <- 1..55 do
        Planning.create_finance_entry(scope, %{
          "kind" => "expense",
          "amount_cents" => i * 100,
          "category" => "teste",
          "occurred_on" => Date.to_iso8601(Date.utc_today())
        })
      end

      {time_us, {:ok, _view, _html}} =
        :timer.tc(fn -> live(conn, ~p"/finances") end)

      time_ms = time_us / 1000
      assert time_ms < 2000, "Dashboard with 55 finances took #{time_ms}ms (budget: 2000ms)"
    end
  end
end
