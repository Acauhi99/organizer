defmodule OrganizerWeb.Components.AsyncChartLoader do
  use Phoenix.Component

  attr :chart_id, :string, required: true
  attr :chart_type, :atom, required: true
  attr :loading, :boolean, default: true
  attr :chart_svg, :any, default: nil

  def async_chart_loader(assigns) do
    ~H"""
    <div id={@chart_id} class="relative min-h-[15rem]">
      <div :if={@loading} class="grid gap-3 p-4">
        <div class="relative overflow-hidden h-12 rounded-lg bg-base-content/12 skeleton-bar"></div>
        <div class="relative overflow-hidden h-12 rounded-lg bg-base-content/12 skeleton-bar"></div>
        <div class="relative overflow-hidden h-12 rounded-lg bg-base-content/12 skeleton-bar"></div>
      </div>

      <div :if={!@loading && @chart_svg} class="contex-plot">
        {@chart_svg}
      </div>

      <div
        :if={!@loading && !@chart_svg}
        class="flex items-center justify-center min-h-[15rem] border border-dashed border-base-content/25 rounded-xl bg-base-100/70"
      >
        <p class="text-xs text-base-content/65">
          Dados insuficientes para gerar gráfico.
        </p>
      </div>
    </div>
    """
  end
end
