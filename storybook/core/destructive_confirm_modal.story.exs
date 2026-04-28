defmodule Storybook.Core.DestructiveConfirmModal do
  use PhoenixStorybook.Story, :component

  def function, do: &OrganizerWeb.CoreComponents.destructive_confirm_modal/1
  def render_source, do: :function
  def container, do: :iframe

  def template do
    """
    <div class="min-h-[26rem] p-4">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :open_state,
        description: "Estado aberto para validacao de contraste e foco",
        attributes: %{
          id: "storybook-delete-modal-open",
          show: true,
          title: "Excluir lancamento?",
          message: "Essa acao nao pode ser desfeita.",
          confirm_event: "confirm",
          cancel_event: "cancel"
        },
        slots: [
          """
          Categoria: Moradia
          """
        ]
      }
    ]
  end
end
