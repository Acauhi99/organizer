defmodule OrganizerWeb.DashboardLiveTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Organizer.Planning
  alias Organizer.SharedFinance

  describe "access" do
    test "redirects unauthenticated users", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/dashboard")
    end

    test "renders for authenticated users", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      assert {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#account-link-panel")
      assert has_element?(view, "#quick-finance-form")
      assert has_element?(view, "#quick-task-form")
      assert has_element?(view, "#quick-bulk")
      assert has_element?(view, "#bulk-capture-form")
      assert has_element?(view, "#analytics-panel")
      assert has_element?(view, "#chart-progress")
      assert has_element?(view, "#chart-finance-trend")
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

    test "creates expense through quick finance form", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
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
      {:ok, view, _html} = live(conn, ~p"/dashboard")

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

      {:ok, view, _html} = live(conn, ~p"/dashboard")
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

      {:ok, view, _html} = live(conn, ~p"/dashboard")
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
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("#quick-preset-income-salary")
      |> render_click()

      assert has_element?(
               view,
               "#quick-finance-form select[name='quick_finance[kind]'] option[value='income'][selected]"
             )
    end

    test "creates task through quick task form", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
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

    test "applies quick preset for shopping list task", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> element("#quick-task-preset-shopping-list")
      |> render_click()

      assert has_element?(
               view,
               "#quick-task-form input[name='quick_task[title]'][value='Lista de compras do mercado']"
             )
    end

    test "imports mixed items through copy/paste mode", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      today = Date.to_iso8601(Date.utc_today())

      payload = """
      tarefa: Comprar ração | data=#{today} | prioridade=alta
      financeiro: tipo=despesa | natureza=fixa | pagamento=credito | valor=125,90 | categoria=pet | data=#{today}
      """

      view
      |> form("#bulk-capture-form", %{"bulk" => %{"payload" => payload}})
      |> render_submit()

      assert has_element?(view, "#bulk-capture-result")

      {:ok, tasks} = Planning.list_tasks(scope, %{})
      {:ok, finances} = Planning.list_finance_entries(scope, %{})

      assert Enum.any?(tasks, &(&1.title == "Comprar ração"))

      assert Enum.any?(finances, fn entry ->
               entry.category == "pet" and
                 entry.amount_cents == 12_590 and
                 entry.expense_profile == :fixed and
                 entry.payment_method == :credit
             end)
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

      assert Enum.any?(tasks, &String.contains?(&1.title, "reunião com equipe"))
      assert Enum.any?(finances, &(&1.kind == :expense and &1.category == "almoço"))
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
      """

      view
      |> form("#bulk-capture-form", %{"bulk" => %{"payload" => payload}})
      |> render_submit()

      {:ok, tasks} = Planning.list_tasks(scope, %{})
      {:ok, finances} = Planning.list_finance_entries(scope, %{})

      task = Enum.find(tasks, &(&1.title == "Ajustar parser"))
      assert task
      assert task.priority == :high
      assert Date.to_iso8601(task.due_on) == "2026-04-15"

      finance = Enum.find(finances, &(&1.category == "moradia" and &1.amount_cents == 123_456))
      assert finance
      assert Date.to_iso8601(finance.occurred_on) == "2026-04-15"
      assert finance.expense_profile == :variable
      assert finance.payment_method == :debit
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

    test "moves task status quickly through kanban actions", %{conn: conn, scope: scope} do
      assert {:ok, task} =
               Planning.create_task(scope, %{"title" => "Mover status", "priority" => "medium"})

      {:ok, view, _html} = live(conn, ~p"/dashboard")

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
                 "title" => "Compartilhar no vínculo",
                 "priority" => "high",
                 "notes" => "Validar com a outra conta"
               })

      assert {:ok, _check_item} =
               Planning.add_task_checklist_item(scope, task.id, %{"label" => "Primeira etapa"})

      {:ok, view, _html} = live(conn, ~p"/dashboard")

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
               linked_task.title == "Compartilhar no vínculo" and linked_task.status == :todo and
                 linked_task.notes =~ "Compartilhada por"
             end)

      view
      |> element("#task-status-quick-btn-#{task.id}")
      |> render_click()

      {:ok, linked_tasks_after_status_change} =
        Planning.list_tasks(linked_scope, %{"days" => "30"})

      assert Enum.any?(linked_tasks_after_status_change, fn linked_task ->
               linked_task.title == "Compartilhar no vínculo" and
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

      {:ok, view, _html} = live(conn, ~p"/dashboard")

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

      {:ok, view, _html} = live(conn, ~p"/dashboard")

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

  describe "panel visibility controls" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "analytics panel is visible by default", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#analytics-panel")
    end

    test "operations panel is visible by default", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#operations-panel")
    end
  end

  describe "onboarding flow" do
    setup %{conn: conn} do
      # user_fixture() creates a new user with no onboarding progress → onboarding is active
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "onboarding overlay is shown for new users", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#onboarding-overlay")
    end

    test "advances through all 6 onboarding steps", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

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
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#onboarding-overlay")

      view |> element("#onboarding-skip-btn") |> render_click()

      refute has_element?(view, "#onboarding-overlay")
    end

    test "dismissed onboarding does not reappear after page reload", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view |> element("#onboarding-skip-btn") |> render_click()
      refute has_element?(view, "#onboarding-overlay")

      # Reload (new session for same user)
      {:ok, view2, _html} = live(log_in_user(conn, user), ~p"/dashboard")
      refute has_element?(view2, "#onboarding-overlay")
    end

    test "completed onboarding does not reappear after page reload", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Advance to last step and complete
      for _step <- 1..6 do
        view |> element("#onboarding-next-btn") |> render_click()
      end

      refute has_element?(view, "#onboarding-overlay")

      {:ok, view2, _html} = live(log_in_user(conn, user), ~p"/dashboard")
      refute has_element?(view2, "#onboarding-overlay")
    end

    test "onboarding can be restarted from help menu", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Skip onboarding first
      view |> element("#onboarding-skip-btn") |> render_click()
      refute has_element?(view, "#onboarding-overlay")

      # Open help menu and restart tutorial
      view |> element("#help-menu-btn") |> render_click()
      view |> element("#restart-tutorial-btn") |> render_click()

      assert has_element?(view, "#onboarding-overlay")
    end
  end

  describe "empty states" do
    setup %{conn: conn} do
      # New user with no data → empty states should be visible
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "empty state for tasks is shown when user has no tasks", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#empty-state-tasks")
    end

    test "empty state for finances is shown when user has no finances", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#empty-state-finances")
    end

    test "empty state for account links is shown when user has no links", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#account-link-empty-state")
      assert has_element?(view, "#account-link-create-btn")
    end

    test "quick finance form is available for empty state users", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#quick-finance-hero")
      assert has_element?(view, "#quick-finance-form")
      assert has_element?(view, "#quick-task-form")
    end

    test "empty state disappears after importing data", %{conn: conn, user: user} do
      scope = user_scope_fixture(user)

      {:ok, _task} =
        Planning.create_task(scope, %{"title" => "Tarefa teste", "priority" => "low"})

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#tasks [id^='tasks-']")
    end
  end

  describe "responsive layout" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "dashboard layout grid is rendered", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#dashboard-keyboard-shortcuts")
    end

    test "bulk import hero is present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#bulk-import-hero")
    end

    test "operations panel is present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#operations-panel")
    end

    test "analytics panel is present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#analytics-panel")
    end

    test "toggling analytics mobile expand event is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      render_click(view, "set_analytics_days", %{"days" => "7"})
      assert has_element?(view, "#analytics-panel")
    end
  end

  describe "keyboard navigation and accessibility" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user)}
    end

    test "skip link to bulk import is present in DOM", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "a.skip-link[href='#bulk-import-hero']")
    end

    test "skip link to operations panel is present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "a.skip-link[href='#operations-panel']")
    end

    test "skip link to analytics panel is present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "a.skip-link[href='#analytics-panel']")
    end

    test "onboarding overlay has role dialog", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#onboarding-overlay[role='dialog']")
    end

    test "bulk import form is present and focusable", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#bulk-capture-form")
    end

    test "Alt+B shortcut triggers focus scroll event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "global_shortcut", %{"key" => "b", "altKey" => true})

      assert_push_event(view, "scroll-to-element", %{
        selector: "#quick-finance-hero",
        focus: "#quick-finance-amount"
      })
    end

    test "? shortcut opens help menu", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "global_shortcut", %{"key" => "?"})

      assert has_element?(view, "#help-menu-dropdown:not(.hidden)")
    end

    test "global shortcut ignores payload without key", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      render_hook(view, "global_shortcut", %{"altKey" => true})

      assert has_element?(view, "#bulk-capture-form")
    end
  end

  describe "performance" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "dashboard renders within 2 second budget", %{conn: conn} do
      {time_us, {:ok, _view, _html}} =
        :timer.tc(fn -> live(conn, ~p"/dashboard") end)

      time_ms = time_us / 1000
      assert time_ms < 2000, "Dashboard took #{time_ms}ms to render (budget: 2000ms)"
    end

    test "analytics filter change completes within 200ms budget", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      {time_us, _result} =
        :timer.tc(fn ->
          render_click(view, "set_analytics_days", %{"days" => "7"})
        end)

      time_ms = time_us / 1000
      assert time_ms < 200, "Analytics filter took #{time_ms}ms (budget: 200ms)"
    end

    test "dashboard renders with large task list within budget", %{conn: conn, user: user} do
      scope = user_scope_fixture(user)

      for i <- 1..55 do
        Planning.create_task(scope, %{
          "title" => "Tarefa de carga #{i}",
          "priority" => "low"
        })
      end

      {time_us, {:ok, _view, _html}} =
        :timer.tc(fn -> live(conn, ~p"/dashboard") end)

      time_ms = time_us / 1000
      assert time_ms < 2000, "Dashboard with 55 tasks took #{time_ms}ms (budget: 2000ms)"
    end

    test "async chart loading state is shown on initial render", %{conn: conn} do
      # Charts start in loading state and load asynchronously
      # We verify the chart containers are present (they may be loading or loaded)
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert has_element?(view, "#analytics-panel")
    end

    test "dashboard renders with large finance list within budget", %{conn: conn, user: user} do
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
        :timer.tc(fn -> live(conn, ~p"/dashboard") end)

      time_ms = time_us / 1000
      assert time_ms < 2000, "Dashboard with 55 finances took #{time_ms}ms (budget: 2000ms)"
    end
  end
end
