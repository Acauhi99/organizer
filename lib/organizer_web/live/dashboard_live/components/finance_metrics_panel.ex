defmodule OrganizerWeb.DashboardLive.Components.FinanceMetricsPanel do
  use Phoenix.Component

  import OrganizerWeb.DashboardLive.Formatters
  alias OrganizerWeb.Components.AsyncChartLoader

  attr :finance_metrics_filters, :map, required: true
  attr :finance_highlights, :map, required: true
  attr :finance_flow_chart, :map, required: true
  attr :finance_category_chart, :map, required: true
  attr :finance_composition_chart, :map, required: true

  def finance_metrics_panel(assigns) do
    ~H"""
    <section id="finance-metrics-panel" class="surface-card rounded-2xl p-4 scroll-mt-20">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
          Métricas financeiras
        </h2>

        <div
          id="finance-metrics-filters"
          class="grid gap-1.5"
          aria-label="Filtros de métricas financeiras"
        >
          <p class="font-mono text-[0.64rem] uppercase tracking-[0.08em] text-base-content/80">
            Período
          </p>
          <div class="flex flex-wrap gap-1.5">
            <button
              :for={days <- finance_metrics_day_range_options()}
              id={"finance-metrics-days-#{days}"}
              type="button"
              phx-click="set_finance_metrics_days"
              phx-value-days={days}
              class={[
                "btn btn-xs ds-pill-btn",
                @finance_metrics_filters.days == days && "btn-primary",
                @finance_metrics_filters.days != days && "btn-soft"
              ]}
            >
              {finance_metrics_days_label(days)}
            </button>
          </div>
        </div>
      </div>

      <div class="mt-4 grid gap-3 grid-cols-1 md:grid-cols-2 xl:grid-cols-4">
        <article class="micro-surface rounded-xl p-3">
          <p class="text-xs uppercase tracking-wide text-base-content/65">Saldo no período</p>
          <p class={[
            "mt-1 text-lg font-semibold",
            balance_value_class(highlight_value(@finance_highlights, :net_cents))
          ]}>
            {format_money(highlight_value(@finance_highlights, :net_cents))}
          </p>
          <p class="text-xs text-base-content/65">
            Rec: {format_money(highlight_value(@finance_highlights, :income_cents))} • Desp: {format_money(
              highlight_value(@finance_highlights, :expense_cents)
            )}
          </p>
        </article>

        <article class="micro-surface rounded-xl p-3">
          <p class="text-xs uppercase tracking-wide text-base-content/65">Ticket médio despesa</p>
          <p class="mt-1 text-lg font-semibold text-base-content">
            {format_money(highlight_value(@finance_highlights, :avg_expense_ticket_cents))}
          </p>
          <p class="text-xs text-base-content/65">
            {highlight_value(@finance_highlights, :expense_entries_window)} lançamento(s) de despesa
          </p>
        </article>

        <article class="micro-surface rounded-xl p-3">
          <p class="text-xs uppercase tracking-wide text-base-content/65">Categoria dominante</p>
          <p class="mt-1 truncate text-sm font-semibold text-base-content">
            {dominant_category_label(@finance_highlights)}
          </p>
          <p class="text-xs text-base-content/65">
            {highlight_value(@finance_highlights, :dominant_expense_share)}% do total de despesas
          </p>
        </article>

        <article class="micro-surface rounded-xl p-3">
          <p class="text-xs uppercase tracking-wide text-base-content/65">Lançamentos no período</p>
          <p class="mt-1 text-lg font-semibold text-base-content">
            {highlight_value(@finance_highlights, :finance_entries_window)}
          </p>
          <p class="text-xs text-base-content/65">
            Dados usados para tendência e composição financeira.
          </p>
        </article>
      </div>

      <div class="mt-4 grid gap-3 xl:grid-cols-2">
        <article class="micro-surface min-h-[15rem] overflow-x-auto rounded-xl p-3 sm:min-h-[18rem]">
          <div class="flex items-center justify-between gap-2">
            <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
              Receitas x despesas no tempo
            </h3>
            <span class="text-[0.65rem] text-base-content/60">barras empilhadas</span>
          </div>
          <AsyncChartLoader.async_chart_loader
            chart_id="chart-finance-flow"
            chart_type={:finance_flow}
            loading={@finance_flow_chart.loading}
            chart_svg={@finance_flow_chart.chart_svg}
          />
          <p
            :if={
              !@finance_flow_chart.loading &&
                highlight_value(@finance_highlights, :finance_entries_window) == 0
            }
            class="mt-2 text-xs text-base-content/65"
          >
            Sem lançamentos financeiros no período para montar o fluxo.
          </p>
        </article>

        <article class="micro-surface min-h-[14rem] overflow-hidden rounded-xl p-3 sm:min-h-[16rem]">
          <div class="flex items-center justify-between gap-2">
            <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
              Composição por natureza
            </h3>
            <span class="text-[0.65rem] text-base-content/60">distribuição</span>
          </div>
          <div class="mx-auto mt-2 w-full max-w-[56rem]">
            <AsyncChartLoader.async_chart_loader
              chart_id="chart-finance-composition"
              chart_type={:finance_composition}
              loading={@finance_composition_chart.loading}
              chart_svg={@finance_composition_chart.chart_svg}
            />
          </div>
          <p
            :if={
              !@finance_composition_chart.loading &&
                !composition_present?(@finance_highlights)
            }
            class="mt-2 text-xs text-base-content/65"
          >
            Sem despesas no período para montar composição.
          </p>
        </article>
      </div>

      <article class="micro-surface mt-3 min-h-[13rem] overflow-hidden rounded-xl p-3 sm:min-h-[15rem]">
        <div class="flex items-center justify-between gap-2">
          <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
            Top despesas por categoria
          </h3>
          <span class="text-[0.65rem] text-base-content/60">ranking</span>
        </div>
        <div class="mx-auto mt-2 w-full max-w-[74rem]">
          <AsyncChartLoader.async_chart_loader
            chart_id="chart-finance-category"
            chart_type={:finance_category}
            loading={@finance_category_chart.loading}
            chart_svg={@finance_category_chart.chart_svg}
          />
        </div>
        <p
          :if={
            !@finance_category_chart.loading &&
              highlight_value(@finance_highlights, :expense_entries_window) == 0
          }
          class="mt-2 text-xs text-base-content/65"
        >
          Cadastre despesas para identificar categorias com maior impacto.
        </p>
      </article>
    </section>
    """
  end

  defp highlight_value(highlights, key) when is_map(highlights), do: Map.get(highlights, key, 0)
  defp highlight_value(_highlights, _key), do: 0

  defp dominant_category_label(finance_highlights) do
    case Map.get(finance_highlights, :dominant_expense_category) do
      nil -> "Sem predominância"
      value when is_binary(value) and value != "" -> value
      _ -> "Sem predominância"
    end
  end

  defp composition_present?(finance_highlights) when is_map(finance_highlights) do
    Map.get(finance_highlights, :expense_entries_window, 0) > 0 and
      Map.get(finance_highlights, :expense_composition_top, []) != []
  end

  defp composition_present?(_finance_highlights), do: false

  defp finance_metrics_days_label("365"), do: "365d"
  defp finance_metrics_days_label(days), do: days <> "d"

  defp finance_metrics_day_range_options, do: ["7", "30", "90", "365"]
end
