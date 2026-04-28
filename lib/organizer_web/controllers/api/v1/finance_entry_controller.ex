defmodule OrganizerWeb.API.V1.FinanceEntryController do
  use OrganizerWeb, :controller

  alias Organizer.Planning

  action_fallback OrganizerWeb.ApiFallbackController

  def index(conn, params) do
    with {:ok, {entries, meta}} <-
           Planning.list_finance_entries_with_meta(conn.assigns.current_scope, params) do
      json(conn, %{
        data: Enum.map(entries, &finance_entry_json/1),
        meta: pagination_meta_json(meta)
      })
    end
  end

  def create(conn, %{"finance_entry" => attrs}) do
    with {:ok, entry} <- Planning.create_finance_entry(conn.assigns.current_scope, attrs) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/finance-entries/#{entry.id}")
      |> json(%{data: finance_entry_json(entry)})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, entry} <- Planning.get_finance_entry(conn.assigns.current_scope, id) do
      json(conn, %{data: finance_entry_json(entry)})
    end
  end

  def update(conn, %{"id" => id, "finance_entry" => attrs}) do
    with {:ok, entry} <- Planning.update_finance_entry(conn.assigns.current_scope, id, attrs) do
      json(conn, %{data: finance_entry_json(entry)})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, _entry} <- Planning.delete_finance_entry(conn.assigns.current_scope, id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp finance_entry_json(entry) do
    %{
      id: entry.id,
      kind: to_string(entry.kind),
      expense_profile: enum_to_string(entry.expense_profile),
      payment_method: enum_to_string(entry.payment_method),
      installment_number: entry.installment_number,
      installments_count: entry.installments_count,
      amount_cents: entry.amount_cents,
      category: entry.category,
      description: entry.description,
      occurred_on: Date.to_iso8601(entry.occurred_on),
      inserted_at: DateTime.to_iso8601(entry.inserted_at),
      updated_at: DateTime.to_iso8601(entry.updated_at)
    }
  end

  defp enum_to_string(nil), do: nil
  defp enum_to_string(value), do: to_string(value)

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
