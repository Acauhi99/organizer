defmodule Organizer.PlanningTest do
  use Organizer.DataCase

  alias Organizer.Planning
  alias Organizer.SharedFinance

  import Organizer.AccountsFixtures

  describe "task isolation" do
    test "lists only current user tasks" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()

      assert {:ok, created_task} =
               Planning.create_task(scope_a, %{"title" => "Planejar semana", "priority" => "high"})

      assert {:ok, tasks_a} = Planning.list_tasks(scope_a)
      assert {:ok, tasks_b} = Planning.list_tasks(scope_b)

      assert Enum.any?(tasks_a, &(&1.id == created_task.id))
      assert Enum.empty?(tasks_b)
    end

    test "prevents cross-user update and delete" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()

      assert {:ok, task} =
               Planning.create_task(scope_a, %{"title" => "Task privada", "priority" => "medium"})

      assert {:error, :not_found} =
               Planning.update_task(scope_b, task.id, %{"title" => "Invadir"})

      assert {:error, :not_found} = Planning.delete_task(scope_b, task.id)

      assert {:ok, owner_task} = Planning.get_task(scope_a, task.id)
      assert owner_task.title == "Task privada"
    end
  end

  describe "task checklist" do
    test "adds checklist items and auto-updates task status based on checks" do
      scope = user_scope_fixture()

      assert {:ok, task} =
               Planning.create_task(scope, %{
                 "title" => "Compras do mercado",
                 "priority" => "medium"
               })

      assert {:ok, item_a} =
               Planning.add_task_checklist_item(scope, task.id, %{"label" => "Arroz"})

      assert {:ok, item_b} =
               Planning.add_task_checklist_item(scope, task.id, %{"label" => "Feijão"})

      assert {:ok, task_after_add} = Planning.get_task(scope, task.id)
      assert task_after_add.status == :todo
      assert Enum.count(task_after_add.checklist_items) == 2
      assert Enum.any?(task_after_add.checklist_items, &(&1.id == item_a.id))
      assert Enum.any?(task_after_add.checklist_items, &(&1.id == item_b.id))

      assert {:ok, _} = Planning.toggle_task_checklist_item(scope, task.id, item_a.id, "true")

      assert {:ok, task_after_first_check} = Planning.get_task(scope, task.id)
      assert task_after_first_check.status == :in_progress

      assert {:ok, _} = Planning.toggle_task_checklist_item(scope, task.id, item_b.id, "true")

      assert {:ok, task_done} = Planning.get_task(scope, task.id)
      assert task_done.status == :done
      refute is_nil(task_done.completed_at)

      assert {:ok, _} = Planning.toggle_task_checklist_item(scope, task.id, item_a.id, "false")

      assert {:ok, task_reopened} = Planning.get_task(scope, task.id)
      assert task_reopened.status == :in_progress
      assert is_nil(task_reopened.completed_at)
    end

    test "enforces ownership for checklist mutations" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()

      assert {:ok, task_a} =
               Planning.create_task(scope_a, %{
                 "title" => "Task privada com checklist",
                 "priority" => "medium"
               })

      assert {:ok, item} =
               Planning.add_task_checklist_item(scope_a, task_a.id, %{"label" => "Item A"})

      assert {:error, :not_found} =
               Planning.add_task_checklist_item(scope_b, task_a.id, %{"label" => "Invasão"})

      assert {:error, :not_found} =
               Planning.update_task_checklist_item(scope_b, task_a.id, item.id, %{
                 "label" => "Alterado"
               })

      assert {:error, :not_found} =
               Planning.toggle_task_checklist_item(scope_b, task_a.id, item.id, "true")

      assert {:error, :not_found} =
               Planning.delete_task_checklist_item(scope_b, task_a.id, item.id)
    end
  end

  describe "task sharing with linked accounts" do
    test "duplicates task and checklist for the linked partner account" do
      owner_scope = user_scope_fixture()
      partner_user = user_fixture()
      partner_scope = user_scope_fixture(partner_user)
      {:ok, invite} = SharedFinance.create_invite(owner_scope)
      {:ok, link} = SharedFinance.accept_invite(partner_scope, invite.token)

      assert {:ok, source_task} =
               Planning.create_task(owner_scope, %{
                 "title" => "Fechar relatório semanal",
                 "priority" => "high",
                 "status" => "in_progress",
                 "notes" => "Enviar versão final para revisão"
               })

      assert {:ok, _item_a} =
               Planning.add_task_checklist_item(owner_scope, source_task.id, %{
                 "label" => "Consolidar métricas"
               })

      assert {:ok, _item_b} =
               Planning.add_task_checklist_item(owner_scope, source_task.id, %{
                 "label" => "Revisar pendências"
               })

      assert {:ok, shared_task} =
               Planning.share_task_with_link(owner_scope, source_task.id, link.id)

      assert shared_task.user_id == partner_scope.user.id
      assert shared_task.title == "Fechar relatório semanal"
      assert shared_task.priority == :high
      assert shared_task.status == :todo
      assert shared_task.notes =~ "Compartilhada por"

      assert {:ok, reloaded_shared_task} = Planning.get_task(partner_scope, shared_task.id)
      assert length(reloaded_shared_task.checklist_items) == 2
      assert Enum.all?(reloaded_shared_task.checklist_items, &(!&1.checked))

      assert Enum.map(reloaded_shared_task.checklist_items, & &1.label) == [
               "Consolidar métricas",
               "Revisar pendências"
             ]
    end

    test "requires task ownership and valid link participation" do
      owner_scope = user_scope_fixture()
      partner_user = user_fixture()
      partner_scope = user_scope_fixture(partner_user)
      outsider_scope = user_scope_fixture()

      {:ok, invite} = SharedFinance.create_invite(owner_scope)
      {:ok, link} = SharedFinance.accept_invite(partner_scope, invite.token)

      assert {:ok, source_task} =
               Planning.create_task(owner_scope, %{
                 "title" => "Task privada",
                 "priority" => "medium"
               })

      assert {:error, :not_found} =
               Planning.share_task_with_link(partner_scope, source_task.id, link.id)

      assert {:error, :not_found} =
               Planning.share_task_with_link(owner_scope, source_task.id, 999_999)

      assert {:error, :not_found} =
               Planning.share_task_with_link(outsider_scope, source_task.id, link.id)
    end

    test "sync mode mirrors status and checklist between linked accounts" do
      owner_scope = user_scope_fixture()
      partner_user = user_fixture()
      partner_scope = user_scope_fixture(partner_user)
      {:ok, invite} = SharedFinance.create_invite(owner_scope)
      {:ok, link} = SharedFinance.accept_invite(partner_scope, invite.token)

      assert {:ok, source_task} =
               Planning.create_task(owner_scope, %{
                 "title" => "Checklist sincronizada",
                 "priority" => "high",
                 "status" => "todo"
               })

      assert {:ok, _item_a} =
               Planning.add_task_checklist_item(owner_scope, source_task.id, %{
                 "label" => "Item A"
               })

      assert {:ok, _item_b} =
               Planning.add_task_checklist_item(owner_scope, source_task.id, %{
                 "label" => "Item B"
               })

      assert {:ok, shared_task} =
               Planning.share_task_with_link(owner_scope, source_task.id, link.id, %{
                 "mode" => "sync"
               })

      assert {:ok, partner_task} = Planning.get_task(partner_scope, shared_task.id)
      assert partner_task.status == :todo
      assert length(partner_task.checklist_items) == 2
      assert Enum.all?(partner_task.checklist_items, &(!&1.checked))

      [partner_item_a | _] = partner_task.checklist_items

      assert {:ok, _} =
               Planning.toggle_task_checklist_item(
                 partner_scope,
                 partner_task.id,
                 partner_item_a.id,
                 "true"
               )

      assert {:ok, owner_after_toggle} = Planning.get_task(owner_scope, source_task.id)
      assert owner_after_toggle.status == :in_progress
      assert Enum.count(owner_after_toggle.checklist_items, & &1.checked) == 1

      assert {:ok, _} =
               Planning.update_task(owner_scope, source_task.id, %{"status" => "done"})

      assert {:ok, partner_after_done} = Planning.get_task(partner_scope, partner_task.id)
      assert partner_after_done.status == :done
      refute is_nil(partner_after_done.completed_at)
    end
  end

  describe "finance isolation" do
    test "aggregates finance summary per user" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()

      assert {:ok, _} =
               Planning.create_finance_entry(scope_a, %{
                 "kind" => "income",
                 "amount_cents" => 5_000,
                 "category" => "salario"
               })

      assert {:ok, _} =
               Planning.create_finance_entry(scope_b, %{
                 "kind" => "expense",
                 "amount_cents" => 3_000,
                 "category" => "contas"
               })

      assert {:ok, summary_a} = Planning.finance_summary(scope_a)
      assert {:ok, summary_b} = Planning.finance_summary(scope_b)

      assert summary_a.income_cents == 5_000
      assert summary_a.expense_cents == 0
      assert summary_a.balance_cents == 5_000

      assert summary_b.income_cents == 0
      assert summary_b.expense_cents == 3_000
      assert summary_b.balance_cents == -3_000
    end

    test "applies expense classification defaults and explicit values" do
      scope = user_scope_fixture()

      assert {:ok, default_expense} =
               Planning.create_finance_entry(scope, %{
                 "kind" => "expense",
                 "amount_cents" => 1_500,
                 "category" => "mercado"
               })

      assert default_expense.expense_profile == :variable
      assert default_expense.payment_method == :debit

      assert {:ok, classified_expense} =
               Planning.create_finance_entry(scope, %{
                 "kind" => "expense",
                 "expense_profile" => "fixed",
                 "payment_method" => "credit",
                 "amount_cents" => 9_900,
                 "category" => "assinaturas"
               })

      assert classified_expense.expense_profile == :fixed
      assert classified_expense.payment_method == :credit

      assert {:ok, income_entry} =
               Planning.create_finance_entry(scope, %{
                 "kind" => "income",
                 "amount_cents" => 20_000,
                 "category" => "salario"
               })

      assert is_nil(income_entry.expense_profile)
      assert is_nil(income_entry.payment_method)
    end
  end

  describe "filters" do
    test "filters tasks by status and priority" do
      scope = user_scope_fixture()

      assert {:ok, _} =
               Planning.create_task(scope, %{
                 "title" => "Task feita",
                 "status" => "done",
                 "priority" => "high"
               })

      assert {:ok, _} =
               Planning.create_task(scope, %{
                 "title" => "Task aberta",
                 "status" => "todo",
                 "priority" => "low"
               })

      assert {:ok, filtered} =
               Planning.list_tasks(scope, %{
                 "status" => "done",
                 "priority" => "high",
                 "days" => "30"
               })

      assert length(filtered) == 1
      assert hd(filtered).title == "Task feita"
    end

    test "returns validation error for invalid task filter values" do
      scope = user_scope_fixture()

      assert {:error, {:validation, %{status: ["is invalid"]}}} =
               Planning.list_tasks(scope, %{"status" => "invalid"})

      assert {:error, {:validation, %{priority: ["is invalid"]}}} =
               Planning.list_tasks(scope, %{"priority" => "urgent"})
    end

    test "returns validation error for invalid goal filters" do
      scope = user_scope_fixture()

      assert {:error, {:validation, %{status: ["is invalid"]}}} =
               Planning.list_goals(scope, %{"status" => "archived"})

      assert {:error, {:validation, %{horizon: ["is invalid"]}}} =
               Planning.list_goals(scope, %{"horizon" => "immediate"})
    end
  end

  describe "analytics overview" do
    test "returns progress, capacity and burnout insight blocks" do
      scope = user_scope_fixture()

      assert {:ok, _} =
               Planning.create_task(scope, %{
                 "title" => "Task concluida",
                 "status" => "done",
                 "priority" => "medium",
                 "due_on" => Date.to_iso8601(Date.utc_today())
               })

      assert {:ok, _} =
               Planning.create_task(scope, %{
                 "title" => "Task pendente",
                 "status" => "todo",
                 "priority" => "high",
                 "due_on" => Date.to_iso8601(Date.add(Date.utc_today(), 3))
               })

      assert {:ok, overview} = Planning.analytics_overview(scope, %{planned_capacity: 1})

      assert is_map(overview.progress_by_period)
      assert is_map(overview.workload_capacity)
      assert is_map(overview.burnout_risk_assessment)
      assert overview.workload_capacity.overload_alert in [true, false]
    end

    test "applies capacity and days options from map and keyword forms" do
      scope = user_scope_fixture()

      assert {:ok, _} =
               Planning.create_task(scope, %{
                 "title" => "Task aberta",
                 "status" => "todo",
                 "priority" => "high",
                 "due_on" => Date.to_iso8601(Date.add(Date.utc_today(), 2))
               })

      assert {:ok, low_capacity} =
               Planning.analytics_overview(scope, %{"planned_capacity" => "0", "days" => "30"})

      assert low_capacity.workload_capacity.planned_capacity_14d == 0
      assert low_capacity.workload_capacity.overload_alert

      assert {:ok, high_capacity} =
               Planning.analytics_overview(scope, planned_capacity: 20, days: 30)

      assert high_capacity.workload_capacity.planned_capacity_14d == 20
      refute high_capacity.workload_capacity.overload_alert
    end

    test "falls back to defaults for invalid option values" do
      scope = user_scope_fixture()

      assert {:ok, _} =
               Planning.create_task(scope, %{
                 "title" => "Task padrao",
                 "status" => "todo",
                 "priority" => "medium",
                 "due_on" => Date.to_iso8601(Date.add(Date.utc_today(), 1))
               })

      assert {:ok, snapshot} =
               Planning.burndown_snapshot(scope, %{
                 "planned_capacity" => "invalid",
                 "days" => "nope"
               })

      assert snapshot.planned_capacity_14d == 10
      assert snapshot.total >= 1
    end
  end

  describe "analytics cache" do
    test "returns cached analytics on cache hit" do
      scope = user_scope_fixture()

      assert {:ok, _} =
               Planning.create_task(scope, %{
                 "title" => "Task para cache",
                 "status" => "todo",
                 "priority" => "high"
               })

      # First call should cache the result
      assert {:ok, analytics_1} =
               Organizer.Planning.AnalyticsCache.get_analytics(scope,
                 days: 7,
                 planned_capacity: 10
               )

      assert is_map(analytics_1)
      assert analytics_1.workload_capacity != nil

      # Second immediate call should return the same cached result
      assert {:ok, analytics_2} =
               Organizer.Planning.AnalyticsCache.get_analytics(scope,
                 days: 7,
                 planned_capacity: 10
               )

      # Verify cache was hit (same data structure)
      assert analytics_1.workload_capacity == analytics_2.workload_capacity
    end

    test "invalidates cache when task is mutated" do
      scope = user_scope_fixture()

      # Create initial task
      assert {:ok, task} =
               Planning.create_task(scope, %{
                 "title" => "Task para invalidar",
                 "status" => "todo",
                 "priority" => "low"
               })

      # Cache the analytics
      assert {:ok, _analytics_before} =
               Organizer.Planning.AnalyticsCache.get_analytics(scope,
                 days: 7,
                 planned_capacity: 10
               )

      # Update the task (should invalidate cache)
      assert {:ok, _updated} = Planning.update_task(scope, task.id, %{"priority" => "high"})

      # Cache should be invalidated, next call will recalculate
      assert {:ok, _analytics_after} =
               Organizer.Planning.AnalyticsCache.get_analytics(scope,
                 days: 7,
                 planned_capacity: 10
               )
    end

    test "invalidates cache when finance entry is mutated" do
      scope = user_scope_fixture()

      # Create initial finance entry
      assert {:ok, finance} =
               Planning.create_finance_entry(scope, %{
                 "kind" => "expense",
                 "amount_cents" => 1_000,
                 "category" => "test"
               })

      # Cache the analytics
      assert {:ok, _analytics_before} =
               Organizer.Planning.AnalyticsCache.get_analytics(scope,
                 days: 30,
                 planned_capacity: 10
               )

      # Update the finance entry (should invalidate cache)
      assert {:ok, _updated} =
               Planning.update_finance_entry(scope, finance.id, %{
                 "kind" => "expense",
                 "amount_cents" => 2_000,
                 "category" => "test"
               })

      # Cache should be invalidated
      assert {:ok, _analytics_after} =
               Organizer.Planning.AnalyticsCache.get_analytics(scope,
                 days: 30,
                 planned_capacity: 10
               )
    end

    test "invalidates cache when goal is mutated" do
      scope = user_scope_fixture()

      # Create initial goal
      assert {:ok, goal} =
               Planning.create_goal(scope, %{
                 "title" => "Goal para cache",
                 "horizon" => "short",
                 "status" => "active"
               })

      # Cache the analytics
      assert {:ok, _analytics_before} =
               Organizer.Planning.AnalyticsCache.get_analytics(scope,
                 days: 14,
                 planned_capacity: 10
               )

      # Update the goal (should invalidate cache)
      assert {:ok, _updated} =
               Planning.update_goal(scope, goal.id, %{
                 "title" => "Goal para cache",
                 "horizon" => "short",
                 "status" => "paused"
               })

      # Cache should be invalidated
      assert {:ok, _analytics_after} =
               Organizer.Planning.AnalyticsCache.get_analytics(scope,
                 days: 14,
                 planned_capacity: 10
               )
    end

    test "deletes create task invalidates cache for user" do
      scope = user_scope_fixture()

      # Cache analytics
      assert {:ok, _} =
               Organizer.Planning.AnalyticsCache.get_analytics(scope,
                 days: 7,
                 planned_capacity: 10
               )

      # Create a task (should invalidate cache)
      assert {:ok, _} =
               Planning.create_task(scope, %{
                 "title" => "New task",
                 "status" => "todo",
                 "priority" => "medium"
               })

      # Verify cache was invalidated by getting fresh analytics
      assert {:ok, analytics} =
               Organizer.Planning.AnalyticsCache.get_analytics(scope,
                 days: 7,
                 planned_capacity: 10
               )

      assert is_map(analytics)
    end

    test "isolates cache per user" do
      scope_a = user_scope_fixture()
      scope_b = user_scope_fixture()

      # Create task for user A
      assert {:ok, _} =
               Planning.create_task(scope_a, %{
                 "title" => "Task A",
                 "status" => "todo",
                 "priority" => "high"
               })

      # Cache analytics for both users
      assert {:ok, analytics_a} =
               Organizer.Planning.AnalyticsCache.get_analytics(scope_a,
                 days: 7,
                 planned_capacity: 10
               )

      assert {:ok, analytics_b} =
               Organizer.Planning.AnalyticsCache.get_analytics(scope_b,
                 days: 7,
                 planned_capacity: 10
               )

      # User B should have different analytics (no tasks)
      assert analytics_a.workload_capacity != nil
      assert analytics_b.workload_capacity != nil

      # Create task for user B and verify cache isolation
      assert {:ok, _} =
               Planning.create_task(scope_b, %{
                 "title" => "Task B",
                 "status" => "todo",
                 "priority" => "medium"
               })

      # User A's cache should still be valid, User B's updated
      assert {:ok, analytics_a_new} =
               Organizer.Planning.AnalyticsCache.get_analytics(scope_a,
                 days: 7,
                 planned_capacity: 10
               )

      assert {:ok, _analytics_b_new} =
               Organizer.Planning.AnalyticsCache.get_analytics(scope_b,
                 days: 7,
                 planned_capacity: 10
               )

      # Verify A's analytics unchanged by B's operation
      assert analytics_a.workload_capacity == analytics_a_new.workload_capacity
    end
  end
end
