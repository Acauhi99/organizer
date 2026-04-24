defmodule OrganizerWeb.DashboardLive.Components.TaskMetricsPanel do
  use Phoenix.Component

  import OrganizerWeb.DashboardLive.Formatters
  alias OrganizerWeb.Components.AsyncChartLoader

  attr :task_metrics_filters, :map, required: true
  attr :insights_overview, :map, required: true
  attr :workload_capacity_snapshot, :map, required: true
  attr :task_delivery_chart, :map, required: true
  attr :task_priority_chart, :map, required: true
  attr :task_highlights, :map, required: true

  def task_metrics_panel(assigns) do
    ~H"""
    <section id="task-metrics-panel" class="surface-card rounded-2xl p-4 scroll-mt-20">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
          Métricas de tarefas
        </h2>

        <div
          id="task-metrics-filters"
          class="grid w-full gap-3 sm:grid-cols-2"
          aria-label="Filtros de métricas de tarefas"
        >
          <div class="grid gap-1.5">
            <p class="font-mono text-[0.64rem] uppercase tracking-[0.08em] text-base-content/80">
              Período
            </p>
            <div class="flex flex-wrap gap-1.5">
              <button
                :for={days <- task_metrics_day_range_options()}
                id={"task-metrics-days-#{days}"}
                type="button"
                phx-click="set_task_metrics_days"
                phx-value-days={days}
                class={[
                  "btn btn-xs ds-pill-btn",
                  @task_metrics_filters.days == days && "btn-primary",
                  @task_metrics_filters.days != days && "btn-soft"
                ]}
              >
                {task_metrics_days_label(days)}
              </button>
            </div>
          </div>

          <div class="grid gap-1.5">
            <p class="font-mono text-[0.64rem] uppercase tracking-[0.08em] text-base-content/80">
              Capacidade (14d)
            </p>
            <div class="flex flex-wrap gap-1.5">
              <button
                :for={capacity <- task_metrics_capacity_options()}
                id={"task-metrics-capacity-#{capacity}"}
                type="button"
                phx-click="set_task_metrics_capacity"
                phx-value-planned_capacity={capacity}
                class={[
                  "btn btn-xs ds-pill-btn",
                  @task_metrics_filters.planned_capacity == capacity && "btn-primary",
                  @task_metrics_filters.planned_capacity != capacity && "btn-soft"
                ]}
              >
                {capacity}
              </button>
            </div>
          </div>
        </div>
      </div>

      <div class="mt-4 grid gap-3 grid-cols-1 md:grid-cols-2 xl:grid-cols-4">
        <article class="micro-surface rounded-xl p-3">
          <p class="text-xs uppercase tracking-wide text-base-content/65">Entrega no período</p>
          <p class="mt-1 text-lg font-semibold text-base-content">
            {highlight_value(@task_highlights, :tasks_completed_window)}/{highlight_value(
              @task_highlights,
              :tasks_created_window
            )}
          </p>
          <p class="text-xs text-base-content/65">
            {highlight_value(@task_highlights, :tasks_completion_rate)}% de ritmo de conclusão
          </p>
        </article>

        <article class="micro-surface rounded-xl p-3">
          <p class="text-xs uppercase tracking-wide text-base-content/65">Backlog crítico</p>
          <p class="mt-1 text-lg font-semibold text-warning-content">
            {highlight_value(@task_highlights, :open_high_priority)} alta prioridade
          </p>
          <p class="text-xs text-base-content/65">
            {highlight_value(@task_highlights, :overdue_open)} tarefa(s) atrasada(s)
          </p>
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

      <div class="mt-4 grid gap-3 xl:grid-cols-2">
        <article class="micro-surface min-h-[15rem] overflow-x-auto rounded-xl p-3 sm:min-h-[18rem]">
          <div class="flex items-center justify-between gap-2">
            <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
              Tarefas: criadas x concluídas
            </h3>
            <span class="text-[0.65rem] text-base-content/60">tendência</span>
          </div>
          <AsyncChartLoader.async_chart_loader
            chart_id="chart-task-delivery"
            chart_type={:task_delivery}
            loading={@task_delivery_chart.loading}
            chart_svg={@task_delivery_chart.chart_svg}
          />
          <p
            :if={
              !@task_delivery_chart.loading &&
                highlight_value(@task_highlights, :tasks_created_window) == 0 &&
                highlight_value(@task_highlights, :tasks_completed_window) == 0
            }
            class="mt-2 text-xs text-base-content/65"
          >
            Sem atividade de tarefas no período selecionado.
          </p>
        </article>

        <article class="micro-surface min-h-[15rem] overflow-x-auto rounded-xl p-3 sm:min-h-[18rem]">
          <div class="flex items-center justify-between gap-2">
            <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
              Backlog por prioridade
            </h3>
            <span class="text-[0.65rem] text-base-content/60">comparação</span>
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
                highlight_value(@task_highlights, :tasks_total_window) == 0
            }
            class="mt-2 text-xs text-base-content/65"
          >
            Sem tarefas relevantes no período para comparar prioridades.
          </p>
        </article>
      </div>
    </section>
    """
  end

  defp highlight_value(highlights, key) when is_map(highlights), do: Map.get(highlights, key, 0)
  defp highlight_value(_highlights, _key), do: 0

  defp task_metrics_days_label("365"), do: "365d"
  defp task_metrics_days_label(days), do: days <> "d"

  defp task_metrics_day_range_options, do: ["7", "15", "30", "90", "365"]
  defp task_metrics_capacity_options, do: ["5", "10", "15", "20", "30"]
end
