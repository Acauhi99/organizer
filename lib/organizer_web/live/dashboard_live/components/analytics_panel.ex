defmodule OrganizerWeb.DashboardLive.Components.AnalyticsPanel do
  @moduledoc """
  Analytics panel component for the DashboardLive.

  Renders the analytics section with filters, actionable highlights and charts.
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
  attr :task_priority_chart, :map, required: true
  attr :finance_mix_chart, :map, required: true
  attr :analytics_highlights, :map, required: true
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

      <div class="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
        <article class="micro-surface rounded-xl p-3">
          <p class="text-xs uppercase tracking-wide text-base-content/65">Entrega no período</p>
          <p class="mt-1 text-lg font-semibold text-base-content">
            {highlight_value(@analytics_highlights, :tasks_completed_window)}/{highlight_value(
              @analytics_highlights,
              :tasks_created_window
            )}
          </p>
          <p class="text-xs text-base-content/65">
            {highlight_value(@analytics_highlights, :tasks_completion_rate)}% de ritmo de conclusão
          </p>
        </article>

        <article class="micro-surface rounded-xl p-3">
          <p class="text-xs uppercase tracking-wide text-base-content/65">Backlog crítico</p>
          <p class="mt-1 text-lg font-semibold text-warning-content">
            {highlight_value(@analytics_highlights, :open_high_priority)} alta prioridade
          </p>
          <p class="text-xs text-base-content/65">
            {highlight_value(@analytics_highlights, :overdue_open)} tarefa(s) atrasada(s)
          </p>
        </article>

        <article class="micro-surface rounded-xl p-3">
          <p class="text-xs uppercase tracking-wide text-base-content/65">Saldo no período</p>
          <p class={[
            "mt-1 text-lg font-semibold",
            balance_value_class(highlight_value(@analytics_highlights, :net_cents))
          ]}>
            {format_money(highlight_value(@analytics_highlights, :net_cents))}
          </p>
          <p class="text-xs text-base-content/65">
            Rec: {format_money(highlight_value(@analytics_highlights, :income_cents))} • Desp: {format_money(
              highlight_value(@analytics_highlights, :expense_cents)
            )}
          </p>
        </article>

        <article class="micro-surface rounded-xl p-3">
          <p class="text-xs uppercase tracking-wide text-base-content/65">Ticket médio despesa</p>
          <p class="mt-1 text-lg font-semibold text-base-content">
            {format_money(highlight_value(@analytics_highlights, :avg_expense_ticket_cents))}
          </p>
          <p class="text-xs text-base-content/65">
            {highlight_value(@analytics_highlights, :expense_entries_window)} lançamento(s) de despesa
          </p>
        </article>

        <article class="micro-surface rounded-xl p-3">
          <p class="text-xs uppercase tracking-wide text-base-content/65">Categoria dominante</p>
          <p class="mt-1 truncate text-sm font-semibold text-base-content">
            {dominant_category_label(@analytics_highlights)}
          </p>
          <p class="text-xs text-base-content/65">
            {highlight_value(@analytics_highlights, :dominant_expense_share)}% do total de despesas
          </p>
        </article>
      </div>

      <div id="analytics-panel-content">
        <div class="mt-4 grid gap-3 xl:grid-cols-2">
          <article class="micro-surface min-h-[15rem] overflow-x-auto rounded-xl p-3 sm:min-h-[18rem]">
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                Tarefas: criadas x concluídas
              </h3>
              <span class="text-[0.65rem] text-base-content/60">
                tendência
              </span>
            </div>
            <AsyncChartLoader.async_chart_loader
              chart_id="chart-progress"
              chart_type={:task_delivery}
              loading={@progress_chart.loading}
              chart_svg={@progress_chart.chart_svg}
            />
            <p
              :if={
                !@progress_chart.loading &&
                  highlight_value(@analytics_highlights, :tasks_created_window) == 0 &&
                  highlight_value(@analytics_highlights, :tasks_completed_window) == 0
              }
              class="mt-2 text-xs text-base-content/65"
            >
              Sem atividade de tarefas no período selecionado.
            </p>
          </article>

          <article class="micro-surface min-h-[15rem] overflow-x-auto rounded-xl p-3 sm:min-h-[18rem]">
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                Receitas x despesas no tempo
              </h3>
              <span class="text-[0.65rem] text-base-content/60">
                barras empilhadas
              </span>
            </div>
            <AsyncChartLoader.async_chart_loader
              chart_id="chart-finance-trend"
              chart_type={:finance_flow}
              loading={@finance_trend_chart.loading}
              chart_svg={@finance_trend_chart.chart_svg}
            />
            <p
              :if={
                !@finance_trend_chart.loading &&
                  highlight_value(@analytics_highlights, :finance_entries_window) == 0
              }
              class="mt-2 text-xs text-base-content/65"
            >
              Sem lançamentos financeiros no período para montar o fluxo.
            </p>
          </article>
        </div>

        <div class="mt-3 grid gap-3 2xl:grid-cols-3">
          <article class="micro-surface min-h-[15rem] overflow-x-auto rounded-xl p-3 sm:min-h-[18rem]">
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                Top despesas por categoria
              </h3>
              <span class="text-[0.65rem] text-base-content/60">
                ranking
              </span>
            </div>
            <AsyncChartLoader.async_chart_loader
              chart_id="chart-finance-category"
              chart_type={:finance_category}
              loading={@finance_category_chart.loading}
              chart_svg={@finance_category_chart.chart_svg}
            />
            <p
              :if={
                !@finance_category_chart.loading &&
                  highlight_value(@analytics_highlights, :expense_entries_window) == 0
              }
              class="mt-2 text-xs text-base-content/65"
            >
              Cadastre despesas para identificar categorias com maior impacto.
            </p>
          </article>

          <article class="micro-surface min-h-[15rem] overflow-x-auto rounded-xl p-3 sm:min-h-[18rem]">
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                Backlog por prioridade
              </h3>
              <span class="text-[0.65rem] text-base-content/60">
                comparação
              </span>
            </div>
            <AsyncChartLoader.async_chart_loader
              chart_id="chart-task-priority"
              chart_type={:task_priority}
              loading={@task_priority_chart.loading}
              chart_svg={@task_priority_chart.chart_svg}
            />
            <p
              :if={
                !@task_priority_chart.loading &&
                  highlight_value(@analytics_highlights, :tasks_total_window) == 0
              }
              class="mt-2 text-xs text-base-content/65"
            >
              Sem tarefas relevantes no período para comparar prioridades.
            </p>
          </article>

          <article class="micro-surface min-h-[15rem] overflow-x-auto rounded-xl p-3 sm:min-h-[18rem]">
            <div class="flex items-center justify-between gap-2">
              <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                Mix de despesas por natureza
              </h3>
              <span class="text-[0.65rem] text-base-content/60">
                parte do todo
              </span>
            </div>
            <AsyncChartLoader.async_chart_loader
              chart_id="chart-finance-mix"
              chart_type={:finance_mix}
              loading={@finance_mix_chart.loading}
              chart_svg={@finance_mix_chart.chart_svg}
            />
            <div :if={expense_mix_present?(@analytics_highlights)} class="mt-2 space-y-1">
              <p class="text-[0.7rem] font-semibold uppercase tracking-[0.08em] text-base-content/62">
                Maiores componentes
              </p>
              <p
                :for={item <- Map.get(@analytics_highlights, :expense_mix_top, [])}
                class="text-xs text-base-content/72"
              >
                {item.label}: {item.share}% ({format_money(item.amount_cents)})
              </p>
            </div>
            <p
              :if={!@finance_mix_chart.loading && !expense_mix_present?(@analytics_highlights)}
              class="mt-2 text-xs text-base-content/65"
            >
              Sem despesas no período para montar composição.
            </p>
          </article>
        </div>

        <div class="mt-3 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
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

          <article class="micro-surface rounded-xl p-3">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Contexto operacional</p>
            <p class="mt-1 text-sm font-semibold text-base-content">
              {Map.get(@ops_counts, :tasks_open, 0)} tarefas abertas • {Map.get(
                @ops_counts,
                :finances_total,
                0
              )} lançamentos
            </p>
            <p class="mt-2 text-xs text-base-content/65">
              Combine filtros de período e capacidade para comparar execução com fluxo financeiro.
            </p>
          </article>
        </div>
      </div>
    </section>
    """
  end

  defp dominant_category_label(analytics_highlights) do
    case Map.get(analytics_highlights, :dominant_expense_category) do
      nil -> "Sem predominância"
      value when is_binary(value) and value != "" -> value
      _ -> "Sem predominância"
    end
  end

  defp highlight_value(highlights, key) when is_map(highlights) do
    Map.get(highlights, key, 0)
  end

  defp highlight_value(_highlights, _key), do: 0

  defp expense_mix_present?(analytics_highlights) when is_map(analytics_highlights) do
    Map.get(analytics_highlights, :expense_entries_window, 0) > 0 and
      Map.get(analytics_highlights, :expense_mix_top, []) != []
  end

  defp expense_mix_present?(_analytics_highlights), do: false

  defp analytics_days_label("365"), do: "365d"
  defp analytics_days_label(days), do: days <> "d"

  defp analytics_day_range_options, do: ["7", "15", "30", "90", "365"]
  defp analytics_capacity_options, do: ["5", "10", "15", "20", "30"]
end
