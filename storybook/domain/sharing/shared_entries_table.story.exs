defmodule Storybook.Domain.Sharing.SharedEntriesTable do
  use PhoenixStorybook.Story, :component

  def function, do: &OrganizerWeb.CoreComponents.table/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :default,
        description: "Historico de compartilhamento com dados paginados",
        attributes: %{
          id: "storybook-shared-entries-table",
          rows: rows()
        },
        slots: table_slots()
      },
      %Variation{
        id: :empty,
        description: "Estado vazio da tabela compartilhada",
        attributes: %{
          id: "storybook-shared-entries-table-empty",
          rows: []
        },
        slots: table_slots()
      }
    ]
  end

  defp rows do
    [
      %{id: 1, occurred_on: "28/04/2026", category: "Moradia", amount: "R$ 250,00", status: "Pendente"},
      %{id: 2, occurred_on: "27/04/2026", category: "Mercado", amount: "R$ 120,00", status: "Parcial"}
    ]
  end

  defp table_slots do
    [
      """
      <:col :let={entry} label="Data">
        <%= entry.occurred_on %>
      </:col>
      """,
      """
      <:col :let={entry} label="Categoria">
        <%= entry.category %>
      </:col>
      """,
      """
      <:col :let={entry} label="Valor">
        <%= entry.amount %>
      </:col>
      """,
      """
      <:col :let={entry} label="Status">
        <span class="badge badge-sm border-base-content/20 bg-base-100/70 text-base-content/85"><%= entry.status %></span>
      </:col>
      """,
      """
      <:action :let={entry}>
        <button type="button" class="btn btn-xs btn-outline">Detalhar #<%= entry.id %></button>
      </:action>
      """
    ]
  end
end
