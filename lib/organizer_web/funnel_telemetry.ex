defmodule OrganizerWeb.FunnelTelemetry do
  @moduledoc """
  Helper for emitting product funnel telemetry events.

  Event:
    `[:organizer, :product, :funnel, :step]`

  Measurements:
    - `:count` (always `1`)

  Required metadata:
    - `:journey`
    - `:action`
    - `:outcome`
  """

  @event [:organizer, :product, :funnel, :step]

  @type step_value :: String.t() | atom()
  @type metadata :: map()

  @spec track_step(step_value(), step_value(), step_value(), metadata()) :: :ok
  def track_step(journey, action, outcome, metadata \\ %{}) when is_map(metadata) do
    normalized_metadata =
      metadata
      |> Map.put(:journey, normalize_step_value(journey))
      |> Map.put(:action, normalize_step_value(action))
      |> Map.put(:outcome, normalize_step_value(outcome))

    :telemetry.execute(@event, %{count: 1}, normalized_metadata)
  end

  defp normalize_step_value(value) when is_atom(value), do: Atom.to_string(value)

  defp normalize_step_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> "unknown"
      normalized -> normalized
    end
  end

  defp normalize_step_value(_value), do: "unknown"
end
