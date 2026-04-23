defmodule OrganizerWeb.DashboardLive.Components.OperationsPanelTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Phoenix.LiveViewTest
  alias OrganizerWeb.DashboardLive.Components.OperationsPanel

  defp base_assigns do
    %{
      streams: %{
        tasks: [],
        finances: []
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
      editing_task_id: nil,
      editing_finance_id: nil,
      ops_counts: %{
        tasks_open: 0,
        tasks_total: 0,
        finances_total: 0,
        finances_income_total: 0,
        finances_expense_total: 0,
        finances_income_cents: 0,
        finances_expense_cents: 0
      }
    }
  end

  property "OperationsPanel is a pure function — same assigns produce identical HTML" do
    tabs = ["tasks", "finances"]

    check all(
            ops_tab <- StreamData.member_of(tabs),
            tasks_open <- StreamData.integer(0..100),
            tasks_total <- StreamData.integer(0..100),
            finances_total <- StreamData.integer(0..100),
            finance_income_total <- StreamData.integer(0..100),
            finance_expense_total <- StreamData.integer(0..100),
            finance_income_cents <- StreamData.integer(0..500_000),
            finance_expense_cents <- StreamData.integer(0..500_000),
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
            finances_income_total: finance_income_total,
            finances_expense_total: finance_expense_total,
            finances_income_cents: finance_income_cents,
            finances_expense_cents: finance_expense_cents
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

    test "renders only tasks and finances tab buttons" do
      html = render_component(&OperationsPanel.operations_panel/1, base_assigns())
      assert html =~ ~s(id="ops-tab-tasks")
      assert html =~ ~s(id="ops-tab-finances")
      refute html =~ ~s(id="ops-tab-goals")
    end

    test "renders KPI cards" do
      html = render_component(&OperationsPanel.operations_panel/1, base_assigns())
      assert html =~ ~s(id="ops-card-tasks-open")
      assert html =~ ~s(id="ops-card-tasks-total")
      assert html =~ ~s(id="ops-card-finances-total")
      assert html =~ ~s(id="ops-card-finances-balance")
    end

    test "renders timer controls for task notifications" do
      html = render_component(&OperationsPanel.operations_panel/1, base_assigns())

      assert html =~ ~s(id="task-timer-box")
      assert html =~ ~s(id="task-timer-task-select")
      assert html =~ ~s(id="task-timer-preset")
      assert html =~ ~s(id="task-timer-minutes")
      assert html =~ ~s(id="task-timer-start")
      assert html =~ ~s(id="task-timer-pause")
      assert html =~ ~s(id="task-timer-reset")
      assert html =~ ~s(id="task-timer-status")
      assert html =~ ~s(id="task-timer-feedback")
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

    test "tasks stream container has phx-update=stream" do
      html = render_component(&OperationsPanel.operations_panel/1, base_assigns())
      assert html =~ ~s(id="tasks" phx-update="stream")
    end

    test "finances stream container has phx-update=stream" do
      html = render_component(&OperationsPanel.operations_panel/1, base_assigns())
      assert html =~ ~s(id="finances" phx-update="stream")
    end

    test "ops_counts values are rendered" do
      assigns =
        Map.put(base_assigns(), :ops_counts, %{
          tasks_open: 5,
          tasks_total: 12,
          finances_total: 8,
          finances_income_total: 3,
          finances_expense_total: 5,
          finances_income_cents: 120_000,
          finances_expense_cents: 80_000
        })

      html = render_component(&OperationsPanel.operations_panel/1, assigns)
      assert html =~ "5"
      assert html =~ "12"
      assert html =~ "8"
      assert html =~ "Receitas: 3 • Despesas: 5"
      assert html =~ "R$ 400,00"
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

    test "renders task checklist controls and progress" do
      task = %{
        id: 1,
        title: "Compras",
        due_on: nil,
        notes: nil,
        priority: :medium,
        status: :in_progress,
        checklist_items: [
          %{id: 10, label: "Arroz", checked: true},
          %{id: 11, label: "Feijão", checked: false}
        ]
      }

      assigns =
        base_assigns()
        |> Map.put(:streams, %{tasks: [{"tasks-1", task}], finances: []})

      html = render_component(&OperationsPanel.operations_panel/1, assigns)

      assert html =~ "Checklist: 1/2 itens concluídos"
      assert html =~ ~s(id="task-checklist-add-form-1")
      assert html =~ ~s(id="task-checklist-toggle-1-10")
      assert html =~ ~s(id="task-checklist-toggle-1-11")
      assert html =~ "line-through"
    end
  end
end
