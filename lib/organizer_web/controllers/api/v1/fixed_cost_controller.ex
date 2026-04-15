defmodule OrganizerWeb.API.V1.FixedCostController do
  use OrganizerWeb, :controller

  alias Organizer.Planning

  action_fallback OrganizerWeb.ApiFallbackController

  def index(conn, _params) do
    with {:ok, costs} <- Planning.list_fixed_costs(conn.assigns.current_scope) do
      json(conn, %{data: Enum.map(costs, &fixed_cost_json/1)})
    end
  end

  def create(conn, %{"fixed_cost" => attrs}) do
    with {:ok, cost} <- Planning.create_fixed_cost(conn.assigns.current_scope, attrs) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/fixed-costs/#{cost.id}")
      |> json(%{data: fixed_cost_json(cost)})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, cost} <- Planning.get_fixed_cost(conn.assigns.current_scope, id) do
      json(conn, %{data: fixed_cost_json(cost)})
    end
  end

  def update(conn, %{"id" => id, "fixed_cost" => attrs}) do
    with {:ok, cost} <- Planning.update_fixed_cost(conn.assigns.current_scope, id, attrs) do
      json(conn, %{data: fixed_cost_json(cost)})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, _cost} <- Planning.delete_fixed_cost(conn.assigns.current_scope, id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp fixed_cost_json(cost) do
    %{
      id: cost.id,
      name: cost.name,
      amount_cents: cost.amount_cents,
      billing_day: cost.billing_day,
      starts_on: to_iso(cost.starts_on),
      active: cost.active,
      inserted_at: DateTime.to_iso8601(cost.inserted_at),
      updated_at: DateTime.to_iso8601(cost.updated_at)
    }
  end

  defp to_iso(nil), do: nil
  defp to_iso(%Date{} = date), do: Date.to_iso8601(date)
end
