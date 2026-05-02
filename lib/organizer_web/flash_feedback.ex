defmodule OrganizerWeb.FlashFeedback do
  @moduledoc """
  Utility for building flash copy in the format:
  "what happened" + "next step".
  """

  @spec compose(String.t(), String.t() | nil) :: String.t()
  def compose(happened, next_step)
      when is_binary(happened) and (is_binary(next_step) or is_nil(next_step)) do
    happened_sentence = normalize_sentence(happened)
    next_step_sentence = normalize_sentence(next_step)

    if next_step_sentence == "" do
      happened_sentence
    else
      "#{happened_sentence} Próximo passo: #{next_step_sentence}"
    end
  end

  defp normalize_sentence(nil), do: ""

  defp normalize_sentence(value) when is_binary(value) do
    cleaned = String.trim(value)

    cond do
      cleaned == "" ->
        ""

      String.ends_with?(cleaned, [".", "!", "?"]) ->
        cleaned

      true ->
        cleaned <> "."
    end
  end
end
