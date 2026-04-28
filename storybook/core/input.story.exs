defmodule Storybook.Core.Input do
  use PhoenixStorybook.Story, :component

  def function, do: &OrganizerWeb.CoreComponents.input/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :default_text,
        attributes: %{
          type: "text",
          id: "storybook-input-default",
          name: "storybook_input_default",
          label: "Descricao",
          value: "Conta de energia",
          placeholder: "Digite uma descricao"
        }
      },
      %Variation{
        id: :with_validation_error,
        attributes: %{
          type: "text",
          id: "storybook-input-error",
          name: "storybook_input_error",
          label: "Valor",
          value: "",
          placeholder: "Ex.: 120,00",
          errors: ["nao pode ficar em branco"]
        }
      },
      %Variation{
        id: :loading_state,
        attributes: %{
          type: "text",
          id: "storybook-input-loading",
          name: "storybook_input_loading",
          label: "Categoria",
          value: "Mercado",
          class: "w-full input loading"
        }
      },
      %Variation{
        id: :disabled_select,
        attributes: %{
          type: "select",
          id: "storybook-select-disabled",
          name: "storybook_select_disabled",
          label: "Metodo de pagamento",
          value: "pix",
          disabled: true,
          options: [
            {"PIX", "pix"},
            {"Cartao", "credit"}
          ]
        }
      }
    ]
  end
end
