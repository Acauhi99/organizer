defmodule OrganizerWeb.API.V1.ImportantDateController do
  use OrganizerWeb, :controller

  alias Organizer.Planning

  action_fallback OrganizerWeb.ApiFallbackController

  def index(conn, params) do
    list_params = Map.put(params, "days", parse_days(params))

    with {:ok, {dates, meta}} <-
           Planning.list_important_dates_with_meta(conn.assigns.current_scope, list_params) do
      json(conn, %{
        data: Enum.map(dates, &important_date_json/1),
        meta: pagination_meta_json(meta)
      })
    end
  end

  def create(conn, %{"important_date" => attrs}) do
    with {:ok, date} <- Planning.create_important_date(conn.assigns.current_scope, attrs) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/important-dates/#{date.id}")
      |> json(%{data: important_date_json(date)})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, date} <- Planning.get_important_date(conn.assigns.current_scope, id) do
      json(conn, %{data: important_date_json(date)})
    end
  end

  def update(conn, %{"id" => id, "important_date" => attrs}) do
    with {:ok, date} <- Planning.update_important_date(conn.assigns.current_scope, id, attrs) do
      json(conn, %{data: important_date_json(date)})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, _date} <- Planning.delete_important_date(conn.assigns.current_scope, id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp important_date_json(date) do
    %{
      id: date.id,
      title: date.title,
      category: to_string(date.category),
      date: Date.to_iso8601(date.date),
      notes: date.notes,
      inserted_at: DateTime.to_iso8601(date.inserted_at),
      updated_at: DateTime.to_iso8601(date.updated_at)
    }
  end

  defp parse_days(%{"days" => value}) when is_binary(value) do
    case Integer.parse(value) do
      {days, ""} -> days
      _ -> 30
    end
  end

  defp parse_days(%{"days" => value}) when is_integer(value), do: value
  defp parse_days(_params), do: 30

  defp pagination_meta_json(meta) do
    meta
    |> Map.from_struct()
    |> Map.take([
      :current_page,
      :page_size,
      :total_pages,
      :total_count,
      :has_next_page?,
      :has_previous_page?,
      :next_offset,
      :previous_offset,
      :next_cursor,
      :previous_cursor
    ])
  end
end
