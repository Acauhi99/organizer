defmodule OrganizerWeb.DashboardLive.Components.OperationsPanelTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Phoenix.LiveViewTest
  alias OrganizerWeb.DashboardLive.Components.OperationsPanel

  defp base_assigns do
    %{
      streams: %{
        tasks: [],
        finances: [],
        goals: []
      },
      ops_tab: "tasks",
      task_filters: %{status: "all", priority: "all", days: "7", q: ""},
      finance_filters: %{
        days: "30",
        kind: "all",
        expense_profile: "all",
        payment_method: "all",
        category: "",
        q: "",
        min_amount_cents: "",
        max_amount_cents: ""
      },
      goal_filters: %{
        status: "all",
        horizon: "all",
        days: "90",
        progress_min: "",
        progress_max: "",
        q: ""
      },
      editing_task_id: nil,
      editing_finance_id: nil,
      editing_goal_id: nil,
      ops_counts: %{
        tasks_open: 0,
        tasks_total: 0,
        finances_total: 0,
        goals_active: 0,
        goals_total: 0
      }
    }
  end

  # Feature: dashboard-components, Property 5: OperationsPanel é uma função pura
  # Validates: Requirements 5.1, 5.4
  property "OperationsPanel is a pure function — same assigns produce identical HTML" do
    tabs = ["tasks", "finances", "goals"]

    check all(
            ops_tab <- StreamData.member_of(tabs),
            tasks_open <- StreamData.integer(0..100),
            tasks_total <- StreamData.integer(0..100),
            finances_total <- StreamData.integer(0..100),
            goals_active <- StreamData.integer(0..50),
            goals_total <- StreamData.integer(0..100),
            days <- StreamData.member_of(["7", "14", "30"])
          ) do
      assigns =
        base_assigns()
        |> Map.put(:ops_tab, ops_tab)
        |> Map.put(:task_filters, %{status: "all", priority: "all", days: days, q: ""})
        |> Map.put(
          :ops_counts,
          %{
            tasks_open: tasks_open,
            tasks_total: tasks_total,
            finances_total: finances_total,
            goals_active: goals_active,
            goals_total: goals_total
          }
        )

      html1 = render_component(&OperationsPanel.operations_panel/1, assigns)
      html2 = render_component(&OperationsPanel.operations_panel/1, assigns)

      assert html1 == html2
    end
  end

  describe "unit tests" do
    test "renders the operations panel section with correct id" do
      html = render_component(&OperationsPanel.operations_panel/1, base_assigns())
      assert html =~ ~s(id="operations-panel")
    end

    test "renders all three tab buttons" do
      html = render_component(&OperationsPanel.operations_panel/1, base_assigns())
      assert html =~ ~s(id="ops-tab-tasks")
      assert html =~ ~s(id="ops-tab-finances")
      assert html =~ ~s(id="ops-tab-goals")
    end

    test "tab buttons emit phx-click=set_ops_tab with correct phx-value-tab" do
      html = render_component(&OperationsPanel.operations_panel/1, base_assigns())
      assert html =~ ~s(phx-click="set_ops_tab")
      assert html =~ ~s(phx-value-tab="tasks")
      assert html =~ ~s(phx-value-tab="finances")
      assert html =~ ~s(phx-value-tab="goals")
    end

    test "renders KPI cards" do
      html = render_component(&OperationsPanel.operations_panel/1, base_assigns())
      assert html =~ ~s(id="ops-card-tasks-open")
      assert html =~ ~s(id="ops-card-tasks-total")
      assert html =~ ~s(id="ops-card-finances-total")
      assert html =~ ~s(id="ops-card-goals-active")
    end

    test "tasks tab is visible when ops_tab is tasks" do
      assigns = Map.put(base_assigns(), :ops_tab, "tasks")
      html = render_component(&OperationsPanel.operations_panel/1, assigns)
      assert html =~ ~s(id="task-filters")
      assert html =~ ~s(phx-change="filter_tasks")
    end

    test "finances tab is visible when ops_tab is finances" do
      assigns = Map.put(base_assigns(), :ops_tab, "finances")
      html = render_component(&OperationsPanel.operations_panel/1, assigns)
      assert html =~ ~s(id="finance-filters")
    end

    test "goals tab is visible when ops_tab is goals" do
      assigns = Map.put(base_assigns(), :ops_tab, "goals")
      html = render_component(&OperationsPanel.operations_panel/1, assigns)
      assert html =~ ~s(id="goal-filters")
    end

    test "tasks stream container has phx-update=stream" do
      html = render_component(&OperationsPanel.operations_panel/1, base_assigns())
      assert html =~ ~s(id="tasks" phx-update="stream")
    end

    test "finances stream container has phx-update=stream" do
      html = render_component(&OperationsPanel.operations_panel/1, base_assigns())
      assert html =~ ~s(id="finances" phx-update="stream")
    end

    test "goals stream container has phx-update=stream" do
      html = render_component(&OperationsPanel.operations_panel/1, base_assigns())
      assert html =~ ~s(id="goals" phx-update="stream")
    end

    test "ops_counts values are rendered" do
      assigns =
        Map.put(base_assigns(), :ops_counts, %{
          tasks_open: 5,
          tasks_total: 12,
          finances_total: 8,
          goals_active: 3,
          goals_total: 7
        })

      html = render_component(&OperationsPanel.operations_panel/1, assigns)
      assert html =~ "5"
      assert html =~ "12"
      assert html =~ "8"
      assert html =~ "3/7"
    end

    test "editing_task_id nil does not render edit form" do
      assigns = Map.put(base_assigns(), :editing_task_id, nil)
      html = render_component(&OperationsPanel.operations_panel/1, assigns)
      refute html =~ ~s(phx-submit="save_task")
    end

    test "editing_finance_id nil does not render finance edit form" do
      assigns = Map.put(base_assigns(), :editing_finance_id, nil)
      html = render_component(&OperationsPanel.operations_panel/1, assigns)
      refute html =~ ~s(phx-submit="save_finance")
    end

    test "editing_goal_id nil does not render goal edit form" do
      assigns = Map.put(base_assigns(), :editing_goal_id, nil)
      html = render_component(&OperationsPanel.operations_panel/1, assigns)
      refute html =~ ~s(phx-submit="save_goal")
    end
  end
end
