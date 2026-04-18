defmodule OrganizerWeb.DashboardLive.Components.DashboardHeader do
  @moduledoc """
  Dashboard header component displaying KPI cards for workload and finance summaries.
  """

  use Phoenix.Component

  import OrganizerWeb.CoreComponents
  import OrganizerWeb.DashboardLive.Formatters

  attr :workload_capacity_snapshot, :map, required: true
  attr :finance_summary, :map, required: true
  attr :onboarding_completed, :boolean, default: false
  attr :help_menu_open, :boolean, default: false

  def dashboard_header(assigns) do
    ~H"""
    <header class="brand-hero-card order-1 rounded-3xl p-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold tracking-tight text-base-content">Painel Diário</h1>
        </div>
        <.help_menu onboarding_completed={@onboarding_completed} open={@help_menu_open} />
      </div>
      <div class="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <article class="micro-surface rounded-xl p-3">
          <div class="flex items-center justify-between gap-2">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Burndown (14d)</p>
            <.icon name="hero-chart-bar" class="size-4 text-cyan-300/90" />
          </div>
          <p class="mt-1 text-xl font-semibold text-base-content">
            {@workload_capacity_snapshot.completed}/{@workload_capacity_snapshot.total}
          </p>
          <p class="text-xs text-base-content/65">
            {completion_rate(
              @workload_capacity_snapshot.completed,
              @workload_capacity_snapshot.total
            )}% concluído
          </p>
          <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-base-content/15">
            <div
              class="h-full rounded-full bg-cyan-300"
              style={"width: #{metric_bar_width(completion_rate(@workload_capacity_snapshot.completed, @workload_capacity_snapshot.total))}%;"}
            >
            </div>
          </div>
        </article>

        <article class="micro-surface rounded-xl p-3">
          <div class="flex items-center justify-between gap-2">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Receitas (30d)</p>
            <.icon name="hero-arrow-trending-up" class="size-4 text-emerald-300/90" />
          </div>
          <p class="mt-1 text-xl font-semibold text-emerald-300">
            {format_money(@finance_summary.income_cents)}
          </p>
          <p class="text-xs text-base-content/65">Entradas no período</p>
        </article>

        <article class="micro-surface rounded-xl p-3">
          <div class="flex items-center justify-between gap-2">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Despesas (30d)</p>
            <.icon name="hero-arrow-trending-down" class="size-4 text-rose-300/90" />
          </div>
          <p class="mt-1 text-xl font-semibold text-rose-300">
            {format_money(@finance_summary.expense_cents)}
          </p>
          <p class="text-xs text-base-content/65">Saídas no período</p>
        </article>

        <article class="micro-surface rounded-xl p-3">
          <div class="flex items-center justify-between gap-2">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Saldo (30d)</p>
            <span class={[
              "rounded-md border px-2 py-0.5 text-[0.65rem] font-semibold uppercase tracking-wide",
              balance_badge_class(@finance_summary.balance_cents)
            ]}>
              {balance_label(@finance_summary.balance_cents)}
            </span>
          </div>
          <p class={[
            "mt-1 text-xl font-semibold",
            balance_value_class(@finance_summary.balance_cents)
          ]}>
            {format_money(@finance_summary.balance_cents)}
          </p>
          <p class="text-xs text-base-content/65">Resultado do período</p>
        </article>
      </div>
    </header>
    """
  end

  attr :onboarding_completed, :boolean, required: true
  attr :open, :boolean, default: false

  defp help_menu(assigns) do
    ~H"""
    <div class="relative" id="help-menu-container" phx-click-away="close_help_menu">
      <button
        id="help-menu-btn"
        type="button"
        phx-click="toggle_help_menu"
        class="btn btn-xs btn-soft"
        aria-label="Ajuda"
        aria-expanded={@open}
        aria-haspopup="true"
      >
        <.icon name="hero-question-mark-circle" class="size-4" />
        <span class="hidden sm:inline">Ajuda</span>
      </button>

      <div
        id="help-menu-dropdown"
        class={[
          "absolute top-[calc(100%+0.5rem)] right-0 z-50 w-56 border border-base-content/20 rounded-xl p-2 bg-base-100/95 shadow-[0_10px_40px_rgba(3,12,26,0.4)] backdrop-blur-[12px]",
          !@open && "hidden"
        ]}
        role="menu"
        aria-labelledby="help-menu-btn"
      >
        <button
          id="restart-tutorial-btn"
          type="button"
          phx-click="show_onboarding_tutorial"
          class="flex items-center gap-2 w-full border-0 rounded-lg px-3 py-2 bg-transparent text-base-content/85 text-left cursor-pointer transition-colors hover:bg-info/12 hover:text-base-content/95"
          role="menuitem"
        >
          <.icon name="hero-arrow-path" class="size-4 shrink-0" />
          <span class="text-sm font-medium">
            {if @onboarding_completed, do: "Refazer tutorial", else: "Iniciar tutorial"}
          </span>
        </button>

        <button
          id="keyboard-shortcuts-btn"
          type="button"
          phx-click="show_keyboard_shortcuts"
          class="flex items-center gap-2 w-full border-0 rounded-lg px-3 py-2 bg-transparent text-base-content/85 text-left cursor-pointer transition-colors hover:bg-info/12 hover:text-base-content/95"
          role="menuitem"
        >
          <.icon name="hero-command-line" class="size-4 shrink-0" />
          <span class="text-sm font-medium">Atalhos de teclado</span>
        </button>
      </div>
    </div>
    """
  end
end
