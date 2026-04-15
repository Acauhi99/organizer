defmodule Organizer.PlanningTest do
  use Organizer.DataCase

  alias Organizer.Planning

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
  end

  describe "filters" do
    test "filters tasks by status and priority" do
      scope = user_scope_fixture()

      assert {:ok, _} =
               Planning.create_task(scope, %{"title" => "Task feita", "status" => "done", "priority" => "high"})

      assert {:ok, _} =
               Planning.create_task(scope, %{"title" => "Task aberta", "status" => "todo", "priority" => "low"})

      assert {:ok, filtered} =
               Planning.list_tasks(scope, %{"status" => "done", "priority" => "high", "days" => "30"})

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

      assert {:ok, low_capacity} = Planning.analytics_overview(scope, %{"planned_capacity" => "0", "days" => "30"})
      assert low_capacity.workload_capacity.planned_capacity_14d == 0
      assert low_capacity.workload_capacity.overload_alert

      assert {:ok, high_capacity} = Planning.analytics_overview(scope, planned_capacity: 20, days: 30)
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
               Planning.burndown_snapshot(scope, %{"planned_capacity" => "invalid", "days" => "nope"})

      assert snapshot.planned_capacity_14d == 10
      assert snapshot.total >= 1
    end
  end
end
