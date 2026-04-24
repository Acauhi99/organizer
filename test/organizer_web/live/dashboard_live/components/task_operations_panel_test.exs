defmodule OrganizerWeb.DashboardLive.Components.TaskOperationsPanelTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  alias OrganizerWeb.DashboardLive.Components.TaskOperationsPanel

  defp base_assigns do
    %{
      streams: %{tasks_todo: [], tasks_in_progress: [], tasks_done: []},
      task_filters: %{status: "all", priority: "all", days: "14", q: ""},
      account_links: [],
      current_user_id: 1,
      editing_task_id: nil,
      task_details_modal_task: nil,
      ops_counts: %{
        tasks_open: 0,
        tasks_total: 0,
        tasks_todo: 0,
        tasks_in_progress: 0,
        tasks_done: 0
      }
    }
  end

  test "is deterministic for same assigns" do
    html1 = render_component(&TaskOperationsPanel.task_operations_panel/1, base_assigns())
    html2 = render_component(&TaskOperationsPanel.task_operations_panel/1, base_assigns())
    assert html1 == html2
  end

  test "renders panel, timer controls and filters" do
    assigns =
      base_assigns()
      |> Map.put(:ops_counts, %{
        tasks_open: 1,
        tasks_total: 1,
        tasks_todo: 1,
        tasks_in_progress: 0,
        tasks_done: 0
      })

    html = render_component(&TaskOperationsPanel.task_operations_panel/1, assigns)
    assert html =~ ~s(id="task-operations-panel")
    assert html =~ ~s(id="task-filters")
    assert html =~ ~s(id="task-focus-timer")
    assert html =~ ~s(id="task-focus-task")
    assert html =~ ~s(id="task-focus-duration")
    assert html =~ ~s(id="task-focus-start")
    assert html =~ ~s(id="tasks-column-todo-scroll-area")
    assert html =~ ~s(phx-hook="InfiniteScroll")
    assert html =~ "Exibindo 0 de 0"
  end

  test "renders tasks empty state" do
    html = render_component(&TaskOperationsPanel.task_operations_panel/1, base_assigns())
    assert html =~ ~s(id="empty-state-tasks")
  end
end
