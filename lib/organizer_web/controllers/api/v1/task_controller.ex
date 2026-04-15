defmodule OrganizerWeb.API.V1.TaskController do
  use OrganizerWeb, :controller

  alias Organizer.Planning

  action_fallback OrganizerWeb.ApiFallbackController

  def index(conn, params) do
    with {:ok, tasks} <- Planning.list_tasks(conn.assigns.current_scope, params) do
      json(conn, %{data: Enum.map(tasks, &task_json/1)})
    end
  end

  def create(conn, %{"task" => attrs}) do
    with {:ok, task} <- Planning.create_task(conn.assigns.current_scope, attrs) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/tasks/#{task.id}")
      |> json(%{data: task_json(task)})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, task} <- Planning.get_task(conn.assigns.current_scope, id) do
      json(conn, %{data: task_json(task)})
    end
  end

  def update(conn, %{"id" => id, "task" => attrs}) do
    with {:ok, task} <- Planning.update_task(conn.assigns.current_scope, id, attrs) do
      json(conn, %{data: task_json(task)})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, _task} <- Planning.delete_task(conn.assigns.current_scope, id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp task_json(task) do
    %{
      id: task.id,
      title: task.title,
      notes: task.notes,
      status: to_string(task.status),
      priority: to_string(task.priority),
      due_on: to_iso(task.due_on),
      inserted_at: DateTime.to_iso8601(task.inserted_at),
      updated_at: DateTime.to_iso8601(task.updated_at)
    }
  end

  defp to_iso(nil), do: nil
  defp to_iso(%Date{} = date), do: Date.to_iso8601(date)
end
