defmodule Storybook.Domain.Settlement.MonthlySummary do
  use PhoenixStorybook.Story, :component

  def function, do: &OrganizerWeb.CoreComponents.list/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :pending_cycle,
        description: "Resumo de acerto em aberto",
        slots: [
          """
          <:item title="Competencia">Abril/2026</:item>
          """,
          """
          <:item title="Saldo pendente">R$ 412,30</:item>
          """,
          """
          <:item title="Status">
            <span class="badge badge-warning badge-sm">Pendente</span>
          </:item>
          """
        ]
      },
      %Variation{
        id: :closed_cycle,
        description: "Resumo de acerto fechado",
        slots: [
          """
          <:item title="Competencia">Março/2026</:item>
          """,
          """
          <:item title="Saldo final">R$ 0,00</:item>
          """,
          """
          <:item title="Status">
            <span class="badge badge-success badge-sm">Fechado</span>
          </:item>
          """
        ]
      }
    ]
  end
end
