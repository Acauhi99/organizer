defmodule OrganizerWeb.DashboardLive.Components.AnalyticsPanel do
  @moduledoc """
  Analytics panel component for the DashboardLive.

  Renders the analytics section with filters, charts, and capacity/burnout metrics.
  """

  use Phoenix.Component
  import OrganizerWeb.DashboardLive.Formatters
  alias OrganizerWeb.Components.AsyncChartLoader

  attr :analytics_filters, :map, required: true
  attr :insights_overview, :map, required: true
  attr :workload_capacity_snapshot, :map, required: true
  attr :progress_chart, :map, required: true
  attr :finance_trend_chart, :map, required: true
  attr :finance_category_chart, :map, required: true
  attr :ops_counts, :map, required: true

  def analytics_panel(assigns) do
    ~H"""
    <section
      id="analytics-panel"
      class="surface-card order-7 rounded-2xl p-4 scroll-mt-20"
    >
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
          Visão analítica
        </h2>
        <div
          id="analytics-filters"
          class="grid gap-3 w-full sm:grid-cols-2"
          aria-label="Filtros analíticos"
        >
          <div class="grid gap-1.5">
            <p class="font-mono text-[0.64rem] uppercase tracking-[0.08em] text-base-content/80">
              Período
            </p>
            <div class="flex flex-wrap gap-1.5">
              <button
                :for={days <- analytics_day_range_options()}
                id={"analytics-days-#{days}"}
                type="button"
                phx-click="set_analytics_days"
                phx-value-days={days}
                class={[
                  "btn btn-xs ds-pill-btn",
                  @analytics_filters.days == days && "btn-primary",
                  @analytics_filters.days != days && "btn-soft"
                ]}
              >
                {analytics_days_label(days)}
              </button>
            </div>
          </div>

          <div class="grid gap-1.5">
            <p class="font-mono text-[0.64rem] uppercase tracking-[0.08em] text-base-content/80">
              Capacidade (14d)
            </p>
            <div class="flex flex-wrap gap-1.5">
              <button
                :for={capacity <- analytics_capacity_options()}
                id={"analytics-capacity-#{capacity}"}
                type="button"
                phx-click="set_analytics_capacity"
                phx-value-planned_capacity={capacity}
                class={[
                  "btn btn-xs ds-pill-btn",
                  @analytics_filters.planned_capacity == capacity && "btn-primary",
                  @analytics_filters.planned_capacity != capacity && "btn-soft"
                ]}
              >
                {capacity}
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Panel content --%>
      <div id="analytics-panel-content">
        <div class="grid gap-3 mt-4">
          <article class="micro-surface min-h-[20rem] rounded-xl p-3">
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                Execução por período
              </h3>
              <span class="text-[0.65rem] text-base-content/60">
                executado vs planejado
              </span>
            </div>
            <AsyncChartLoader.async_chart_loader
              chart_id="chart-progress"
              chart_type={:progress}
              loading={@progress_chart.loading}
              chart_svg={@progress_chart.chart_svg}
            />
            <p
              :if={!@progress_chart.loading && !progress_chart_has_data?(@insights_overview)}
              class="mt-2 text-xs text-base-content/65"
            >
              Sem dados suficientes neste intervalo. Ajuste a janela para visualizar tendências.
            </p>
          </article>

          <div class="grid gap-3 xl:grid-cols-2">
            <article class="micro-surface min-h-[20rem] rounded-xl p-3">
              <div class="flex items-center justify-between gap-2">
                <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                  Saldo semanal
                </h3>
                <span class="text-[0.65rem] text-base-content/60">
                  tendência financeira
                </span>
              </div>
              <AsyncChartLoader.async_chart_loader
                chart_id="chart-finance-trend"
                chart_type={:finance_trend}
                loading={@finance_trend_chart.loading}
                chart_svg={@finance_trend_chart.chart_svg}
              />
              <p
                :if={!@finance_trend_chart.loading && @ops_counts.finances_total == 0}
                class="mt-2 text-xs text-base-content/65"
              >
                Sem lançamentos financeiros no período para montar tendência.
              </p>
            </article>

            <article class="micro-surface min-h-[20rem] rounded-xl p-3">
              <div class="flex items-center justify-between gap-2">
                <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                  Despesas por categoria
                </h3>
                <span class="text-[0.65rem] text-base-content/60">
                  top 5
                </span>
              </div>
              <AsyncChartLoader.async_chart_loader
                chart_id="chart-finance-category"
                chart_type={:finance_category}
                loading={@finance_category_chart.loading}
                chart_svg={@finance_category_chart.chart_svg}
              />
              <p
                :if={!@finance_category_chart.loading && @ops_counts.finances_total == 0}
                class="mt-2 text-xs text-base-content/65"
              >
                Cadastre despesas para identificar categorias com maior impacto.
              </p>
            </article>
          </div>
        </div>

        <div class="mt-3 grid gap-3 md:grid-cols-2 xl:grid-cols-5">
          <article class="micro-surface rounded-xl p-3">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Semanal</p>
            <p class="mt-1 text-lg font-semibold text-base-content">
              {@insights_overview.progress_by_period.weekly.executed}/{@insights_overview.progress_by_period.weekly.planned}
            </p>
            <p class="text-xs text-base-content/65">
              {format_percent(@insights_overview.progress_by_period.weekly.completion_rate)}% de conclusão
            </p>
            <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-base-content/15">
              <div
                class="h-full rounded-full bg-cyan-300"
                style={"width: #{metric_bar_width(@insights_overview.progress_by_period.weekly.completion_rate)}%;"}
              >
              </div>
            </div>
          </article>

          <article class="micro-surface rounded-xl p-3">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Mensal</p>
            <p class="mt-1 text-lg font-semibold text-base-content">
              {@insights_overview.progress_by_period.monthly.executed}/{@insights_overview.progress_by_period.monthly.planned}
            </p>
            <p class="text-xs text-base-content/65">
              {format_percent(@insights_overview.progress_by_period.monthly.completion_rate)}% de conclusão
            </p>
            <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-base-content/15">
              <div
                class="h-full rounded-full bg-emerald-300"
                style={"width: #{metric_bar_width(@insights_overview.progress_by_period.monthly.completion_rate)}%;"}
              >
              </div>
            </div>
          </article>

          <article class="micro-surface rounded-xl p-3">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Anual</p>
            <p class="mt-1 text-lg font-semibold text-base-content">
              {@insights_overview.progress_by_period.annual.executed}/{@insights_overview.progress_by_period.annual.planned}
            </p>
            <p class="text-xs text-base-content/65">
              {format_percent(@insights_overview.progress_by_period.annual.completion_rate)}% de conclusão
            </p>
            <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-base-content/15">
              <div
                class="h-full rounded-full bg-violet-300"
                style={"width: #{metric_bar_width(@insights_overview.progress_by_period.annual.completion_rate)}%;"}
              >
              </div>
            </div>
          </article>

          <article class="micro-surface rounded-xl p-3">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Capacidade 14d</p>
            <p class={[
              "mt-1 text-lg font-semibold",
              capacity_gap_class(@workload_capacity_snapshot.capacity_gap)
            ]}>
              {@workload_capacity_snapshot.open_14d}/{@workload_capacity_snapshot.planned_capacity_14d}
            </p>
            <p class="text-xs text-base-content/65">
              {capacity_gap_label(@workload_capacity_snapshot.capacity_gap)} • Alerta: {if @workload_capacity_snapshot.overload_alert,
                do: "ligado",
                else: "desligado"}
            </p>
          </article>

          <article class="micro-surface rounded-xl p-3">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Risco burnout</p>
            <p class={"mt-1 inline-flex rounded px-2 py-0.5 text-xs font-semibold " <> risk_badge_class(@insights_overview.burnout_risk_assessment.level)}>
              {burnout_level_label(@insights_overview.burnout_risk_assessment.level)} ({@insights_overview.burnout_risk_assessment.score})
            </p>
            <p class="mt-2 text-xs text-base-content/65">
              {if Enum.empty?(@insights_overview.burnout_risk_assessment.signals),
                do: "Sem sinais críticos no momento.",
                else: Enum.join(@insights_overview.burnout_risk_assessment.signals, " | ")}
            </p>
          </article>
        </div>
        <%!-- End of metrics grid --%>
      </div>
      <%!-- End of panel content --%>
    </section>
    """
  end

  defp progress_chart_has_data?(insights_overview) do
    progress = insights_overview.progress_by_period

    progress.weekly.executed + progress.weekly.planned +
      progress.monthly.executed + progress.monthly.planned +
      progress.annual.executed + progress.annual.planned > 0
  end

  defp analytics_days_label("365"), do: "365d"
  defp analytics_days_label(days), do: days <> "d"

  defp analytics_day_range_options, do: ["7", "15", "30", "90", "365"]
  defp analytics_capacity_options, do: ["5", "10", "15", "20", "30"]
end
