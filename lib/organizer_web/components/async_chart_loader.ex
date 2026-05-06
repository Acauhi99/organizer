defmodule OrganizerWeb.Components.AsyncChartLoader do
  use Phoenix.Component

  attr :chart_id, :string, required: true
  attr :chart_type, :atom, required: true
  attr :loading, :boolean, default: true
  attr :chart_svg, :any, default: nil

  def async_chart_loader(assigns) do
    ~H"""
    <div
      id={@chart_id}
      class="relative min-h-[15rem] rounded-2xl border border-cyan-300/18 bg-slate-900/66 p-3 shadow-[inset_0_0_0_1px_rgba(34,211,238,0.05)]"
    >
      <div :if={@loading} class="grid gap-2.5">
        <div class="relative h-12 overflow-hidden rounded-lg border border-cyan-300/14 bg-slate-900/78 skeleton-bar">
        </div>
        <div class="relative h-12 overflow-hidden rounded-lg border border-cyan-300/14 bg-slate-900/78 skeleton-bar">
        </div>
        <div class="relative h-12 overflow-hidden rounded-lg border border-cyan-300/14 bg-slate-900/78 skeleton-bar">
        </div>
      </div>

      <div :if={!@loading && @chart_svg} class="contex-plot">
        {@chart_svg}
      </div>

      <div
        :if={!@loading && !@chart_svg}
        class="flex min-h-[15rem] items-center justify-center rounded-xl border border-dashed border-cyan-300/30 bg-slate-900/76"
      >
        <p class="text-xs text-base-content/68">
          Dados insuficientes para gerar gráfico.
        </p>
      </div>
    </div>
    """
  end
end
