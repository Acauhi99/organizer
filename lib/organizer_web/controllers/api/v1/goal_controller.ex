defmodule OrganizerWeb.API.V1.GoalController do
  use OrganizerWeb, :controller

  alias Organizer.Planning

  action_fallback OrganizerWeb.ApiFallbackController

  def index(conn, _params) do
    with {:ok, goals} <- Planning.list_goals(conn.assigns.current_scope) do
      json(conn, %{data: Enum.map(goals, &goal_json/1)})
    end
  end

  def create(conn, %{"goal" => attrs}) do
    with {:ok, goal} <- Planning.create_goal(conn.assigns.current_scope, attrs) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/goals/#{goal.id}")
      |> json(%{data: goal_json(goal)})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, goal} <- Planning.get_goal(conn.assigns.current_scope, id) do
      json(conn, %{data: goal_json(goal)})
    end
  end

  def update(conn, %{"id" => id, "goal" => attrs}) do
    with {:ok, goal} <- Planning.update_goal(conn.assigns.current_scope, id, attrs) do
      json(conn, %{data: goal_json(goal)})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, _goal} <- Planning.delete_goal(conn.assigns.current_scope, id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp goal_json(goal) do
    %{
      id: goal.id,
      title: goal.title,
      horizon: to_string(goal.horizon),
      status: to_string(goal.status),
      target_value: goal.target_value,
      current_value: goal.current_value,
      due_on: to_iso(goal.due_on),
      notes: goal.notes,
      inserted_at: DateTime.to_iso8601(goal.inserted_at),
      updated_at: DateTime.to_iso8601(goal.updated_at)
    }
  end

  defp to_iso(nil), do: nil
  defp to_iso(%Date{} = date), do: Date.to_iso8601(date)
end
