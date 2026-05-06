defmodule OrganizerWeb.DashboardLive.Components.FinanceOperationsPanel do
  use Phoenix.Component

  import OrganizerWeb.CoreComponents,
    only: [app_modal: 1, destructive_confirm_modal: 1, icon: 1]

  import OrganizerWeb.DashboardLive.Formatters

  attr :streams, :map, required: true
  attr :finance_filters, :map, required: true
  attr :finance_meta, :any, default: nil
  attr :category_suggestions, :map, default: %{}
  attr :editing_finance_id, :any, default: nil
  attr :finance_edit_modal_entry, :any, default: nil
  attr :pending_finance_delete, :any, default: nil
  attr :ops_counts, :map, required: true
  attr :finance_visible_count, :integer, default: 0
  attr :finance_has_more?, :boolean, default: false
  attr :finance_loading_more?, :boolean, default: false
  attr :finance_next_page, :integer, default: 2

  def finance_operations_panel(assigns) do
    assigns =
      assigns
      |> assign(:finance_filters, normalize_finance_filters(assigns.finance_filters))
      |> assign(
        :category_suggestions,
        normalize_category_suggestions(assigns.category_suggestions)
      )

    ~H"""
    <section
      id="finance-operations-panel"
      class={neon_surface_class("operations-shell p-4 scroll-mt-20")}
      phx-hook="FinanceFormEnhancements"
    >
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div class="max-w-3xl">
          <h2 class="text-2xl font-black tracking-[-0.02em] text-base-content">
            Operação diária financeira
          </h2>
          <p id="finance-fixed-guidance" class="text-sm leading-6 text-base-content/75">
            Filtre e acompanhe receitas e despesas ativas para entender o comportamento financeiro em tempo real.
          </p>
        </div>
      </div>

      <div class="mt-3 grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
        <article
          id="finance-ops-card-total"
          class={neon_card_class("rounded-lg p-3")}
          aria-label={"Lançamentos no filtro em #{finance_period_context_label(@finance_filters)}"}
        >
          <div class="flex items-center justify-between">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Lançamentos no filtro</p>
            <span class="text-xs text-base-content/65">
              {finance_period_context_badge(@finance_filters)}
            </span>
          </div>
          <p class="mt-1 text-lg font-semibold text-base-content">{@ops_counts.finances_total}</p>
        </article>

        <article
          id="finance-ops-card-kinds"
          class={neon_card_class("rounded-lg p-3")}
          aria-label="Receitas e despesas no filtro"
        >
          <div class="flex items-center justify-between">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Receitas x despesas</p>
            <span class="text-xs text-base-content/65">contagem</span>
          </div>
          <p class="mt-1 text-sm text-base-content/82">
            Receitas: {Map.get(@ops_counts, :finances_income_total, 0)} • Despesas: {Map.get(
              @ops_counts,
              :finances_expense_total,
              0
            )}
          </p>
        </article>

        <article
          id="finance-ops-card-balance"
          class={neon_card_class("rounded-lg p-3")}
          aria-label={"Saldo financeiro em #{finance_period_context_label(@finance_filters)}"}
        >
          <div class="flex items-center justify-between">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Saldo no filtro</p>
            <span class="text-xs text-base-content/65">
              {finance_period_context_badge(@finance_filters)}
            </span>
          </div>
          <p class={[
            "mt-1 text-lg font-semibold",
            balance_value_class(finance_balance_cents(@ops_counts))
          ]}>
            {format_money(finance_balance_cents(@ops_counts))}
          </p>
        </article>
      </div>

      <form
        id="finance-filters"
        phx-change="filter_finances"
        phx-debounce="500"
        class="mt-3 space-y-3"
        aria-label="Filtros de lançamentos"
      >
        <div
          id="finance-filters-basic"
          class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-6"
        >
          <select
            id="finance-filter-period-mode"
            name="filters[period_mode]"
            aria-label="Modo de período"
            class={field_control_class()}
          >
            <option value="rolling" selected={@finance_filters.period_mode == "rolling"}>
              Janela móvel (dias)
            </option>
            <option value="specific_date" selected={@finance_filters.period_mode == "specific_date"}>
              Data específica
            </option>
            <option value="month" selected={@finance_filters.period_mode == "month"}>
              Mês específico
            </option>
            <option value="range" selected={@finance_filters.period_mode == "range"}>
              Intervalo de datas
            </option>
            <option value="weekday" selected={@finance_filters.period_mode == "weekday"}>
              Dia da semana
            </option>
          </select>

          <select
            :if={rolling_period_mode?(@finance_filters)}
            id="finance-filter-days"
            name="filters[days]"
            aria-label="Janela em dias"
            class={field_control_class()}
          >
            <option value="7" selected={@finance_filters.days == "7"}>Últimos 7 dias</option>
            <option value="30" selected={@finance_filters.days == "30"}>Últimos 30 dias</option>
            <option value="90" selected={@finance_filters.days == "90"}>Últimos 90 dias</option>
            <option value="365" selected={@finance_filters.days == "365"}>Últimos 365 dias</option>
          </select>

          <select
            id="finance-filter-kind"
            name="filters[kind]"
            aria-label="Tipo de lançamento"
            class={field_control_class()}
          >
            <option value="all" selected={@finance_filters.kind == "all"}>Todos tipos</option>
            <option value="income" selected={@finance_filters.kind == "income"}>Receita</option>
            <option value="expense" selected={@finance_filters.kind == "expense"}>Despesa</option>
          </select>

          <select
            id="finance-filter-payment-method"
            name="filters[payment_method]"
            aria-label="Método de pagamento"
            class={field_control_class()}
          >
            <option value="all" selected={@finance_filters.payment_method == "all"}>
              Todos métodos
            </option>
            <option value="credit" selected={@finance_filters.payment_method == "credit"}>
              Crédito
            </option>
            <option value="debit" selected={@finance_filters.payment_method == "debit"}>
              Débito
            </option>
          </select>

          <input
            type="text"
            id="finance-filter-category"
            name="filters[category]"
            value={@finance_filters.category}
            aria-label="Filtrar por categoria"
            placeholder="Categoria..."
            class={field_control_class()}
            maxlength="50"
            list="finance-filter-categories"
          />

          <input
            type="text"
            id="finance-filter-q"
            name="filters[q]"
            value={@finance_filters.q}
            aria-label="Buscar por descrição"
            placeholder="Buscar descrição..."
            class={field_control_class()}
            maxlength="100"
          />

          <input
            type="hidden"
            id="finance-filter-min-amount-cents"
            name="filters[min_amount_cents]"
            value={@finance_filters.min_amount_cents}
          />

          <input
            type="text"
            id="finance-filter-min-amount-display"
            value={money_filter_input_value(@finance_filters.min_amount_cents)}
            aria-label="Valor mínimo"
            placeholder="Valor mín..."
            class={field_control_class()}
            inputmode="numeric"
            data-money-mask="true"
            data-money-hidden-target="finance-filter-min-amount-cents"
          />

          <input
            type="hidden"
            id="finance-filter-max-amount-cents"
            name="filters[max_amount_cents]"
            value={@finance_filters.max_amount_cents}
          />

          <input
            type="text"
            id="finance-filter-max-amount-display"
            value={money_filter_input_value(@finance_filters.max_amount_cents)}
            aria-label="Valor máximo"
            placeholder="Valor máx..."
            class={field_control_class()}
            inputmode="numeric"
            data-money-mask="true"
            data-money-hidden-target="finance-filter-max-amount-cents"
          />
        </div>

        <details
          id="finance-filters-advanced"
          class="rounded-xl border border-cyan-300/20 bg-slate-900/65 p-3"
          open={advanced_filters_active?(@finance_filters)}
        >
          <summary
            id="finance-filters-advanced-summary"
            class="flex cursor-pointer list-none items-center justify-between gap-2"
          >
            <span class="text-xs font-semibold uppercase tracking-[0.12em] text-base-content/70">
              Filtros avançados
            </span>
            <span class="text-xs text-base-content/62">
              {advanced_filters_summary_hint(@finance_filters)}
            </span>
          </summary>

          <p
            id="finance-filters-advanced-guidance"
            class="mt-2 text-xs leading-5 text-base-content/68"
          >
            {advanced_filters_guidance(@finance_filters)}
          </p>

          <div class="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-6">
            <input
              :if={period_mode?(@finance_filters, "specific_date")}
              type="text"
              id="finance-filter-occurred-on"
              name="filters[occurred_on]"
              value={@finance_filters.occurred_on}
              aria-label="Data específica"
              placeholder="Data exata: dd/mm/aaaa"
              class={field_control_class()}
              inputmode="numeric"
              maxlength="10"
              pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
              data-date-picker="date"
            />

            <input
              :if={period_mode?(@finance_filters, "month")}
              type="text"
              id="finance-filter-month"
              name="filters[month]"
              value={@finance_filters.month}
              aria-label="Mês de referência"
              placeholder="Mês: mm/aaaa"
              class={field_control_class()}
              inputmode="numeric"
              maxlength="7"
              pattern="^[0-9]{2}/[0-9]{4}$"
              data-date-picker="month"
            />

            <input
              :if={period_mode?(@finance_filters, "range")}
              type="text"
              id="finance-filter-occurred-from"
              name="filters[occurred_from]"
              value={@finance_filters.occurred_from}
              aria-label="Data inicial do intervalo"
              placeholder="De: dd/mm/aaaa"
              class={field_control_class()}
              inputmode="numeric"
              maxlength="10"
              pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
              data-date-picker="date"
            />

            <input
              :if={period_mode?(@finance_filters, "range")}
              type="text"
              id="finance-filter-occurred-to"
              name="filters[occurred_to]"
              value={@finance_filters.occurred_to}
              aria-label="Data final do intervalo"
              placeholder="Até: dd/mm/aaaa"
              class={field_control_class()}
              inputmode="numeric"
              maxlength="10"
              pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
              data-date-picker="date"
            />

            <select
              :if={period_mode?(@finance_filters, "weekday")}
              id="finance-filter-weekday"
              name="filters[weekday]"
              aria-label="Dia da semana"
              class={field_control_class()}
            >
              <option value="all" selected={@finance_filters.weekday == "all"}>Todos os dias</option>
              <option value="1" selected={@finance_filters.weekday == "1"}>Segunda</option>
              <option value="2" selected={@finance_filters.weekday == "2"}>Terça</option>
              <option value="3" selected={@finance_filters.weekday == "3"}>Quarta</option>
              <option value="4" selected={@finance_filters.weekday == "4"}>Quinta</option>
              <option value="5" selected={@finance_filters.weekday == "5"}>Sexta</option>
              <option value="6" selected={@finance_filters.weekday == "6"}>Sábado</option>
              <option value="0" selected={@finance_filters.weekday == "0"}>Domingo</option>
            </select>

            <select
              id="finance-filter-sort-by"
              name="filters[sort_by]"
              aria-label="Ordenar lançamentos"
              class={field_control_class()}
            >
              <option value="date_desc" selected={@finance_filters.sort_by == "date_desc"}>
                Data mais recente
              </option>
              <option value="date_asc" selected={@finance_filters.sort_by == "date_asc"}>
                Data mais antiga
              </option>
              <option value="amount_desc" selected={@finance_filters.sort_by == "amount_desc"}>
                Maior valor
              </option>
              <option value="amount_asc" selected={@finance_filters.sort_by == "amount_asc"}>
                Menor valor
              </option>
              <option value="category_asc" selected={@finance_filters.sort_by == "category_asc"}>
                Categoria A-Z
              </option>
            </select>

            <select
              id="finance-filter-expense-profile"
              name="filters[expense_profile]"
              aria-label="Perfil de despesa"
              class={field_control_class()}
            >
              <option value="all" selected={@finance_filters.expense_profile == "all"}>
                Todos perfis
              </option>
              <option value="fixed" selected={@finance_filters.expense_profile == "fixed"}>
                Fixa
              </option>
              <option value="variable" selected={@finance_filters.expense_profile == "variable"}>
                Variável
              </option>
              <option
                value="recurring_fixed"
                selected={@finance_filters.expense_profile == "recurring_fixed"}
              >
                Recorrente fixa
              </option>
              <option
                value="recurring_variable"
                selected={@finance_filters.expense_profile == "recurring_variable"}
              >
                Recorrente variável
              </option>
            </select>
          </div>
        </details>
      </form>

      <datalist id="finance-filter-categories">
        <option :for={category <- Map.get(@category_suggestions, :all, [])} value={category}>
          {category}
        </option>
      </datalist>

      <div class="mt-3 flex items-center justify-between gap-2">
        <p id="finance-visible-counter" class="text-[11px] font-medium text-base-content/68">
          Exibindo {@finance_visible_count} de {Map.get(@ops_counts, :finances_total, 0)} lançamentos
        </p>
      </div>

      <div
        id="finances-scroll-area"
        phx-hook="InfiniteScroll"
        data-event="load_more_finances"
        data-has-more={to_string(@finance_has_more?)}
        data-loading={to_string(@finance_loading_more?)}
        data-next-page={@finance_next_page}
        class="operations-scroll-area operations-scroll-area--list mt-3 rounded-2xl border border-cyan-300/20 bg-slate-900/65 p-3 shadow-[inset_0_0_0_1px_rgba(34,211,238,0.04)]"
      >
        <div id="finances" phx-update="stream" class="space-y-2">
          <div id="finances-empty-wrapper" class="hidden only:block">
            <div
              id="empty-state-finances"
              class="rounded-xl border border-dashed border-cyan-300/30 px-4 py-6 text-center"
            >
              <p class="text-sm font-semibold text-base-content/85">Nenhum lançamento financeiro</p>
              <p class="mt-1 text-xs leading-5 text-base-content/65">
                Registre rendas e gastos no card de lançamento rápido para começar seu histórico.
              </p>
            </div>
          </div>

          <article
            :for={{id, entry} <- @streams.finances}
            id={id}
            class={finance_row_card_class(entry.kind)}
          >
            <div class="flex flex-col gap-2">
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <div class="flex flex-wrap items-center gap-x-2 gap-y-0.5">
                    <p class="truncate text-sm font-semibold text-base-content">{entry.category}</p>
                    <p class="text-[11px] text-base-content/62">
                      {date_input_value(entry.occurred_on)}
                    </p>
                  </div>
                  <p
                    :if={entry.description && String.trim(entry.description) != ""}
                    class="mt-0.5 text-xs text-base-content/72"
                  >
                    {entry.description}
                  </p>
                </div>
                <p class={[finance_amount_class(entry.kind), "shrink-0 whitespace-nowrap"]}>
                  {format_money(entry.amount_cents)}
                </p>
              </div>

              <div class="flex flex-wrap items-center justify-between gap-2">
                <div class="flex flex-wrap gap-1.5">
                  <span class={finance_kind_badge_class(entry.kind)}>
                    {finance_kind_label(entry.kind)}
                  </span>
                  <span
                    :if={entry.expense_profile}
                    class={finance_profile_badge_class(entry.expense_profile)}
                  >
                    {finance_profile_label(entry.expense_profile)}
                  </span>
                  <span
                    :if={entry.payment_method}
                    class={finance_payment_badge_class(entry.payment_method)}
                  >
                    {finance_payment_label(entry.payment_method)}
                  </span>
                  <span
                    :if={show_installments_badge?(entry)}
                    class={finance_installments_badge_class()}
                  >
                    {installments_badge_label(entry)}
                  </span>
                  <span
                    :if={fixed_until_cancelled?(entry)}
                    class="inline-flex items-center rounded-full border border-cyan-300/45 bg-cyan-400/14 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-cyan-100"
                  >
                    Ativa até cancelar
                  </span>
                </div>

                <div class="flex items-center gap-1.5">
                  <button
                    id={"finance-edit-btn-#{entry.id}"}
                    type="button"
                    phx-click="start_edit_finance"
                    phx-value-id={entry.id}
                    class={edit_action_btn_class()}
                  >
                    Editar
                  </button>
                  <button
                    id={"finance-delete-btn-#{entry.id}"}
                    type="button"
                    phx-click="prompt_delete_finance"
                    phx-value-id={entry.id}
                    class={delete_action_btn_class()}
                  >
                    Excluir
                  </button>
                </div>
              </div>
            </div>
          </article>
        </div>

        <div :if={@finance_loading_more?} id="finance-load-more-state" class="px-1 py-2">
          <p class="text-center text-[11px] text-base-content/62">Carregando mais lançamentos...</p>
        </div>
      </div>

      <.finance_edit_modal
        entry={@finance_edit_modal_entry}
        category_suggestions={@category_suggestions}
      />

      <.destructive_confirm_modal
        id="finance-delete-confirmation-modal"
        show={is_map(@pending_finance_delete)}
        title="Excluir lançamento financeiro?"
        message="Você está prestes a remover este lançamento do histórico financeiro."
        severity="danger"
        impact_label="Impacto: o lançamento some da lista e dos indicadores"
        confirm_event="confirm_delete_finance"
        cancel_event="cancel_delete_finance"
        confirm_button_id="finance-delete-confirm-btn"
        cancel_button_id="finance-delete-cancel-btn"
        confirm_label="Sim, excluir lançamento"
      >
        <p :if={is_map(@pending_finance_delete)} class="font-medium text-base-content">
          {Map.get(@pending_finance_delete, :category, "Lançamento sem categoria")}
        </p>
      </.destructive_confirm_modal>
    </section>
    """
  end

  attr :entry, :any, default: nil
  attr :category_suggestions, :map, default: %{income: [], expense: [], all: []}

  defp finance_edit_modal(assigns) do
    ~H"""
    <.app_modal
      id="finance-edit-modal"
      show={is_map(@entry)}
      cancel_event="cancel_edit_finance"
      aria_labelledby={if is_map(@entry), do: "finance-edit-title-#{@entry.id}", else: nil}
      z_index_class="z-[120]"
      dialog_class="max-w-3xl rounded-2xl p-5 shadow-[0_24px_70px_rgba(23,33,47,0.34)] sm:p-6"
    >
      <section id="finance-edit-dialog">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/65">
              Editar lançamento
            </p>
            <h2
              id={"finance-edit-title-#{@entry.id}"}
              class="mt-1 break-words text-xl font-semibold text-base-content"
            >
              {@entry.category}
            </h2>
          </div>

          <button
            id="finance-edit-close-btn"
            type="button"
            phx-click="cancel_edit_finance"
            class={modal_cancel_btn_class()}
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <div class="mt-3 flex flex-wrap gap-1.5">
          <span class={finance_kind_badge_class(@entry.kind)}>{finance_kind_label(@entry.kind)}</span>
          <span
            :if={@entry.expense_profile}
            class={finance_profile_badge_class(@entry.expense_profile)}
          >
            {finance_profile_label(@entry.expense_profile)}
          </span>
          <span :if={@entry.payment_method} class={finance_payment_badge_class(@entry.payment_method)}>
            {finance_payment_label(@entry.payment_method)}
          </span>
          <span :if={show_installments_badge?(@entry)} class={finance_installments_badge_class()}>
            {installments_badge_label(@entry)}
          </span>
        </div>

        <form
          id={"finance-edit-form-#{@entry.id}"}
          phx-submit="save_finance"
          class="mt-4 space-y-3 bg-slate-900/75 p-3.5 sm:p-4"
        >
          <input type="hidden" name="_id" value={@entry.id} />
          <div class="grid gap-2 sm:grid-cols-2">
            <div>
              <label
                class="text-xs font-medium text-base-content/70"
                for={"finance-kind-#{@entry.id}"}
              >
                Tipo
              </label>
              <select
                id={"finance-kind-#{@entry.id}"}
                name="finance[kind]"
                class={field_control_class()}
              >
                <option value="income" selected={@entry.kind == :income}>Receita</option>
                <option value="expense" selected={@entry.kind == :expense}>Despesa</option>
              </select>
            </div>
            <div>
              <label
                class="text-xs font-medium text-base-content/70"
                for={"finance-expense-profile-#{@entry.id}"}
              >
                {finance_profile_field_label(@entry.kind)}
              </label>
              <select
                id={"finance-expense-profile-#{@entry.id}"}
                name="finance[expense_profile]"
                class={field_control_class()}
              >
                <option
                  :for={{label, value} <- finance_edit_profile_options(@entry.kind)}
                  value={value}
                  selected={to_string(@entry.expense_profile || "variable") == value}
                >
                  {label}
                </option>
              </select>
            </div>
            <div>
              <label
                class="text-xs font-medium text-base-content/70"
                for={"finance-payment-method-#{@entry.id}"}
              >
                Pagamento
              </label>
              <select
                id={"finance-payment-method-#{@entry.id}"}
                name="finance[payment_method]"
                class={field_control_class()}
              >
                <option value="" selected={is_nil(@entry.payment_method)}>Não se aplica</option>
                <option value="debit" selected={@entry.payment_method == :debit}>Débito</option>
                <option value="credit" selected={@entry.payment_method == :credit}>Crédito</option>
              </select>
            </div>
            <div>
              <label
                class="text-xs font-medium text-base-content/70"
                for={"finance-amount-#{@entry.id}"}
              >
                Valor
              </label>
              <input
                id={"finance-amount-#{@entry.id}"}
                name="finance[amount_cents]"
                type="text"
                inputmode="decimal"
                required
                value={money_input_value(@entry.amount_cents)}
                class={field_control_class()}
                placeholder="Ex: 330,00"
                data-money-mask="true"
              />
            </div>
          </div>
          <label
            class="text-xs font-medium text-base-content/70"
            for={"finance-category-#{@entry.id}"}
          >
            Categoria
          </label>
          <input
            id={"finance-category-#{@entry.id}"}
            name="finance[category]"
            type="text"
            required
            value={@entry.category}
            class={field_control_class()}
            list={finance_entry_category_datalist_id(@entry.id, @entry.kind)}
          />
          <label class="text-xs font-medium text-base-content/70" for={"finance-date-#{@entry.id}"}>
            Data
          </label>
          <input
            id={"finance-date-#{@entry.id}"}
            name="finance[occurred_on]"
            type="text"
            value={date_input_value(@entry.occurred_on)}
            class={field_control_class()}
            placeholder="dd/mm/aaaa"
            inputmode="numeric"
            maxlength="10"
            pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
            data-date-picker="date"
          />
          <label
            class="text-xs font-medium text-base-content/70"
            for={"finance-description-#{@entry.id}"}
          >
            Descrição
          </label>
          <input
            id={"finance-description-#{@entry.id}"}
            name="finance[description]"
            type="text"
            value={@entry.description || ""}
            class={field_control_class()}
          />
          <div :if={@entry.kind == :expense}>
            <div class="grid gap-2 sm:grid-cols-2">
              <div>
                <label
                  class="text-xs font-medium text-base-content/70"
                  for={"finance-installment-number-#{@entry.id}"}
                >
                  Parcela atual
                </label>
                <input
                  id={"finance-installment-number-#{@entry.id}"}
                  name="finance[installment_number]"
                  type="number"
                  min="1"
                  max="120"
                  step="1"
                  value={@entry.installment_number || 1}
                  class={field_control_class()}
                />
              </div>
              <div>
                <label
                  class="text-xs font-medium text-base-content/70"
                  for={"finance-installments-#{@entry.id}"}
                >
                  Total de parcelas
                </label>
                <input
                  id={"finance-installments-#{@entry.id}"}
                  name="finance[installments_count]"
                  type="number"
                  min="1"
                  max="120"
                  step="1"
                  value={@entry.installments_count || 1}
                  class={field_control_class()}
                />
              </div>
            </div>
            <p class="mt-1 text-[11px] text-base-content/62">
              Use o formato atual/total para facilitar a leitura, por exemplo: 6/10.
            </p>
          </div>
          <datalist id={finance_entry_category_datalist_id(@entry.id, @entry.kind)}>
            <option
              :for={category <- finance_category_options(@entry.kind, @category_suggestions)}
              value={category}
            >
              {category}
            </option>
          </datalist>
          <div class="mt-1 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
            <button type="button" class={modal_cancel_btn_class()} phx-click="cancel_edit_finance">
              Cancelar
            </button>
            <button type="submit" class={modal_submit_btn_class()}>Salvar lançamento</button>
          </div>
        </form>
      </section>
    </.app_modal>
    """
  end

  defp finance_balance_cents(ops_counts) do
    Map.get(ops_counts, :finances_income_cents, 0) -
      Map.get(ops_counts, :finances_expense_cents, 0)
  end

  defp finance_row_border_class(:income), do: "border-success/25"
  defp finance_row_border_class(:expense), do: "border-error/25"
  defp finance_row_border_class(_), do: "border-cyan-300/20"

  defp finance_row_card_class(kind) do
    join_classes([
      neon_card_class("rounded-xl border p-2.5"),
      finance_row_border_class(kind)
    ])
  end

  defp finance_amount_class(:income), do: "text-sm font-semibold font-mono text-success"
  defp finance_amount_class(:expense), do: "text-sm font-semibold font-mono text-error"
  defp finance_amount_class(_), do: "text-sm font-semibold font-mono text-base-content"

  defp finance_kind_badge_class(:income),
    do:
      "inline-flex items-center rounded-full border border-emerald-300/50 bg-emerald-400/15 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-emerald-100"

  defp finance_kind_badge_class(:expense),
    do:
      "inline-flex items-center rounded-full border border-rose-300/55 bg-rose-500/15 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-rose-100"

  defp finance_kind_badge_class(_),
    do:
      "inline-flex items-center rounded-full border border-slate-300/35 bg-slate-800/80 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-slate-100"

  defp finance_kind_label(:income), do: "Receita"
  defp finance_kind_label(:expense), do: "Despesa"
  defp finance_kind_label(_), do: "Tipo"

  defp finance_profile_field_label(:income), do: "Natureza da receita"
  defp finance_profile_field_label(_), do: "Natureza da despesa"

  defp finance_edit_profile_options(:income) do
    [
      {"Variável", "variable"},
      {"Fixa (repete mensalmente)", "fixed"}
    ]
  end

  defp finance_edit_profile_options(_kind) do
    [
      {"Fixa", "fixed"},
      {"Variável", "variable"},
      {"Recorrente fixa", "recurring_fixed"},
      {"Recorrente variável", "recurring_variable"}
    ]
  end

  defp finance_profile_label(:fixed), do: "Fixa"
  defp finance_profile_label(:variable), do: "Variável"
  defp finance_profile_label(:recurring_fixed), do: "Recorrente fixa"
  defp finance_profile_label(:recurring_variable), do: "Recorrente variável"

  defp finance_profile_label(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.capitalize()

  defp finance_profile_label(_), do: "Perfil"

  defp finance_profile_badge_class(:fixed),
    do:
      "inline-flex items-center rounded-full border border-cyan-300/45 bg-cyan-400/12 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-cyan-100"

  defp finance_profile_badge_class(:variable),
    do:
      "inline-flex items-center rounded-full border border-amber-300/50 bg-amber-300/14 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-amber-100"

  defp finance_profile_badge_class(:recurring_fixed),
    do:
      "inline-flex items-center rounded-full border border-violet-300/55 bg-violet-400/14 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-violet-100"

  defp finance_profile_badge_class(:recurring_variable),
    do:
      "inline-flex items-center rounded-full border border-lime-300/55 bg-lime-300/15 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-lime-100"

  defp finance_profile_badge_class(_),
    do:
      "inline-flex items-center rounded-full border border-slate-300/35 bg-slate-800/80 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-slate-100"

  defp finance_payment_label(:debit), do: "Débito"
  defp finance_payment_label(:credit), do: "Crédito"

  defp finance_payment_label(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.capitalize()

  defp finance_payment_label(_), do: "Pagamento"

  defp finance_payment_badge_class(:debit),
    do:
      "inline-flex items-center rounded-full border border-emerald-300/50 bg-emerald-400/15 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-emerald-100"

  defp finance_payment_badge_class(:credit),
    do:
      "inline-flex items-center rounded-full border border-rose-300/55 bg-rose-500/15 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-rose-100"

  defp finance_payment_badge_class(_),
    do:
      "inline-flex items-center rounded-full border border-slate-300/35 bg-slate-800/80 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-slate-100"

  defp finance_installments_badge_class,
    do:
      "inline-flex items-center rounded-full border border-fuchsia-300/50 bg-fuchsia-500/14 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-fuchsia-100"

  defp show_installments_badge?(entry) do
    entry.kind == :expense and entry.payment_method == :credit and
      is_integer(entry.installments_count) and entry.installments_count > 1
  end

  defp installments_badge_label(entry) do
    "Parcela #{current_installment_number(entry)}/#{entry.installments_count}"
  end

  defp current_installment_number(entry) do
    case entry.installment_number do
      number when is_integer(number) and number > 0 -> number
      _ -> 1
    end
  end

  defp fixed_until_cancelled?(entry) do
    entry.kind == :expense and entry.expense_profile in [:fixed, :recurring_fixed]
  end

  defp neon_surface_class(extra) do
    join_classes([
      "neon-surface rounded-3xl border border-cyan-400/20 bg-slate-950/72 shadow-[0_24px_70px_-38px_rgba(34,211,238,0.7)] backdrop-blur-sm",
      extra
    ])
  end

  defp neon_card_class(extra) do
    join_classes([
      "neon-card rounded-2xl border border-cyan-300/15 bg-slate-900/72 shadow-[0_18px_45px_-34px_rgba(16,185,129,0.65)]",
      extra
    ])
  end

  defp field_control_class do
    "w-full rounded-xl border border-cyan-300/20 bg-slate-900/85 px-2.5 py-2 text-sm text-base-content placeholder:text-base-content/45 transition focus:border-cyan-200/60 focus:outline-none focus:ring-2 focus:ring-cyan-300/25"
  end

  defp edit_action_btn_class do
    "rounded-lg border border-cyan-300/30 bg-slate-900/90 px-2.5 py-1.5 text-xs font-medium text-cyan-100 transition hover:border-cyan-200/70 hover:bg-cyan-400/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/35"
  end

  defp delete_action_btn_class do
    "rounded-lg border border-rose-300/40 bg-rose-500/10 px-2.5 py-1.5 text-xs font-medium text-rose-100 transition hover:border-rose-200/70 hover:bg-rose-500/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-300/35"
  end

  defp modal_cancel_btn_class do
    "inline-flex items-center justify-center rounded-xl border border-slate-400/30 bg-slate-900/70 px-3 py-1.5 text-xs font-semibold text-slate-200 transition hover:border-cyan-300/45 hover:text-cyan-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/35"
  end

  defp modal_submit_btn_class do
    "inline-flex items-center justify-center rounded-xl border border-cyan-300/70 bg-cyan-400/90 px-3 py-1.5 text-xs font-semibold text-slate-950 shadow-[0_14px_30px_-16px_rgba(34,211,238,0.75)] transition hover:bg-cyan-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-200/60"
  end

  defp money_input_value(cents) when is_integer(cents) and cents >= 0 do
    integer_part = cents |> div(100) |> Integer.to_string()
    decimal_part = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    integer_part <> "," <> decimal_part
  end

  defp money_input_value(cents) when is_integer(cents), do: Integer.to_string(cents)
  defp money_input_value(_cents), do: ""

  defp money_filter_input_value(value) when is_integer(value), do: money_input_value(value)

  defp money_filter_input_value(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {cents, ""} when cents >= 0 -> money_input_value(cents)
      _ -> ""
    end
  end

  defp money_filter_input_value(_value), do: ""

  defp finance_entry_category_datalist_id(entry_id, :income),
    do: "finance-entry-income-categories-#{entry_id}"

  defp finance_entry_category_datalist_id(entry_id, _kind),
    do: "finance-entry-expense-categories-#{entry_id}"

  defp finance_category_options(:income, suggestions) do
    default_income_categories()
    |> merge_with_category_suggestions(Map.get(suggestions, :income, []))
  end

  defp finance_category_options(_kind, suggestions) do
    default_expense_categories()
    |> merge_with_category_suggestions(Map.get(suggestions, :expense, []))
  end

  defp default_income_categories do
    ["Salário", "Renda extra", "Freelance", "Reembolso", "Dividendos"]
  end

  defp default_expense_categories do
    ["Alimentação", "Moradia", "Transporte", "Saúde", "Lazer", "Educação", "Assinaturas"]
  end

  defp merge_with_category_suggestions(defaults, suggestions) when is_list(suggestions) do
    (defaults ++ suggestions)
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&String.downcase/1)
  end

  defp normalize_finance_filters(filters) when is_map(filters) do
    defaults = %{
      period_mode: "rolling",
      days: "30",
      month: "",
      occurred_on: "",
      occurred_from: "",
      occurred_to: "",
      weekday: "all",
      sort_by: "date_desc",
      kind: "all",
      expense_profile: "all",
      payment_method: "all",
      category: "",
      q: "",
      min_amount_cents: "",
      max_amount_cents: ""
    }

    Map.merge(defaults, filters)
  end

  defp normalize_finance_filters(_filters) do
    %{
      period_mode: "rolling",
      days: "30",
      month: "",
      occurred_on: "",
      occurred_from: "",
      occurred_to: "",
      weekday: "all",
      sort_by: "date_desc",
      kind: "all",
      expense_profile: "all",
      payment_method: "all",
      category: "",
      q: "",
      min_amount_cents: "",
      max_amount_cents: ""
    }
  end

  defp advanced_filters_active?(filters) when is_map(filters) do
    Map.get(filters, :period_mode, "rolling") in ["specific_date", "month", "range", "weekday"] or
      non_empty_filter_value?(Map.get(filters, :occurred_on, "")) or
      non_empty_filter_value?(Map.get(filters, :month, "")) or
      non_empty_filter_value?(Map.get(filters, :occurred_from, "")) or
      non_empty_filter_value?(Map.get(filters, :occurred_to, "")) or
      Map.get(filters, :weekday, "all") != "all" or
      Map.get(filters, :sort_by, "date_desc") != "date_desc" or
      Map.get(filters, :expense_profile, "all") != "all"
  end

  defp advanced_filters_active?(_filters), do: false

  defp period_mode?(filters, mode) when is_binary(mode), do: finance_period_mode(filters) == mode

  defp rolling_period_mode?(filters), do: period_mode?(filters, "rolling")

  defp finance_period_context_badge(filters) do
    case finance_period_mode(filters) do
      "specific_date" ->
        period_specific_date(filters)

      "month" ->
        period_month(filters)

      "range" ->
        period_range_badge(filters)

      "weekday" ->
        period_weekday_badge(filters)

      _ ->
        "#{period_days(filters)}d"
    end
  end

  defp finance_period_context_label(filters) do
    case finance_period_mode(filters) do
      "specific_date" ->
        "data #{period_specific_date(filters)}"

      "month" ->
        "mês #{period_month(filters)}"

      "range" ->
        period_range_label(filters)

      "weekday" ->
        "dia da semana #{period_weekday_label(filters)}"

      _ ->
        "janela móvel dos últimos #{period_days(filters)} dias"
    end
  end

  defp advanced_filters_summary_hint(filters) do
    case finance_period_mode(filters) do
      "specific_date" -> "Data específica, ordenação e perfil"
      "month" -> "Mês específico, ordenação e perfil"
      "range" -> "Intervalo de datas, ordenação e perfil"
      "weekday" -> "Dia da semana, ordenação e perfil"
      _ -> "Data específica, intervalo, dia da semana, ordenação e perfil"
    end
  end

  defp advanced_filters_guidance(filters) do
    case finance_period_mode(filters) do
      "specific_date" ->
        "Selecione uma data exata para investigar eventos pontuais e validar ajustes do dia."

      "month" ->
        "Selecione um mês para revisar fechamento mensal e comparar tendências."

      "range" ->
        "Defina início e fim para analisar o comportamento entre dois marcos."

      "weekday" ->
        "Filtre por dia da semana para identificar padrões recorrentes de receita e despesa."

      _ ->
        "Use estes filtros quando precisar investigar um período ou comportamento específico."
    end
  end

  defp finance_period_mode(filters) when is_map(filters) do
    case Map.get(filters, :period_mode, "rolling") do
      mode when mode in ["rolling", "specific_date", "month", "range", "weekday"] -> mode
      _ -> "rolling"
    end
  end

  defp finance_period_mode(_filters), do: "rolling"

  defp period_days(filters) do
    case Integer.parse(to_string(Map.get(filters, :days, "30"))) do
      {days, ""} when days > 0 -> days
      _ -> 30
    end
  end

  defp period_specific_date(filters) do
    Map.get(filters, :occurred_on, "")
    |> to_string()
    |> String.trim()
    |> case do
      "" -> "data específica"
      value -> value
    end
  end

  defp period_month(filters) do
    Map.get(filters, :month, "")
    |> to_string()
    |> String.trim()
    |> case do
      "" -> "mês específico"
      value -> value
    end
  end

  defp period_range_badge(filters) do
    from_date = period_from_date(filters)
    to_date = period_to_date(filters)

    cond do
      from_date != "" and to_date != "" -> "#{from_date} → #{to_date}"
      from_date != "" -> "Desde #{from_date}"
      to_date != "" -> "Até #{to_date}"
      true -> "Intervalo"
    end
  end

  defp period_range_label(filters) do
    from_date = period_from_date(filters)
    to_date = period_to_date(filters)

    cond do
      from_date != "" and to_date != "" -> "intervalo de #{from_date} até #{to_date}"
      from_date != "" -> "intervalo a partir de #{from_date}"
      to_date != "" -> "intervalo até #{to_date}"
      true -> "intervalo de datas personalizado"
    end
  end

  defp period_from_date(filters) do
    Map.get(filters, :occurred_from, "") |> to_string() |> String.trim()
  end

  defp period_to_date(filters) do
    Map.get(filters, :occurred_to, "") |> to_string() |> String.trim()
  end

  defp period_weekday_badge(filters) do
    case Map.get(filters, :weekday, "all") |> to_string() |> String.trim() do
      "0" -> "Dom"
      "1" -> "Seg"
      "2" -> "Ter"
      "3" -> "Qua"
      "4" -> "Qui"
      "5" -> "Sex"
      "6" -> "Sáb"
      _ -> "Dia da semana"
    end
  end

  defp period_weekday_label(filters) do
    case Map.get(filters, :weekday, "all") |> to_string() |> String.trim() do
      "0" -> "domingo"
      "1" -> "segunda"
      "2" -> "terça"
      "3" -> "quarta"
      "4" -> "quinta"
      "5" -> "sexta"
      "6" -> "sábado"
      _ -> "selecionado"
    end
  end

  defp non_empty_filter_value?(value) when is_binary(value), do: String.trim(value) != ""
  defp non_empty_filter_value?(nil), do: false
  defp non_empty_filter_value?(_value), do: true

  defp normalize_category_suggestions(suggestions) when is_map(suggestions) do
    Map.merge(%{income: [], expense: [], all: []}, suggestions)
  end

  defp normalize_category_suggestions(_suggestions), do: %{income: [], expense: [], all: []}

  defp join_classes(classes) do
    classes
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end
end
