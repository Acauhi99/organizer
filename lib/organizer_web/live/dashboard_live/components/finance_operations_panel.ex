defmodule OrganizerWeb.DashboardLive.Components.FinanceOperationsPanel do
  use Phoenix.Component

  import OrganizerWeb.CoreComponents, only: [icon: 1]
  import OrganizerWeb.DashboardLive.Formatters

  attr :streams, :map, required: true
  attr :finance_filters, :map, required: true
  attr :category_suggestions, :map, default: %{}
  attr :editing_finance_id, :any, default: nil
  attr :finance_edit_modal_entry, :any, default: nil
  attr :ops_counts, :map, required: true
  attr :finance_visible_count, :integer, default: 0
  attr :finance_has_more?, :boolean, default: false
  attr :finance_loading_more?, :boolean, default: false

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
      class="operations-shell surface-card rounded-2xl p-4 scroll-mt-20"
    >
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
          Operação diária financeira
        </h2>
      </div>
      <p id="finance-fixed-guidance" class="mt-2 text-xs text-base-content/68">
        Lançamentos com perfil fixo permanecem ativos até cancelamento para refletir melhor seu fluxo real.
      </p>

      <div class="mt-3 grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
        <article
          id="finance-ops-card-total"
          class="micro-surface rounded-lg p-3"
          aria-label={"Lançamentos no filtro nos últimos #{@finance_filters.days} dias"}
        >
          <div class="flex items-center justify-between">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Lançamentos no filtro</p>
            <span class="text-xs text-base-content/65">{@finance_filters.days}d</span>
          </div>
          <p class="mt-1 text-lg font-semibold text-base-content">{@ops_counts.finances_total}</p>
        </article>

        <article
          id="finance-ops-card-kinds"
          class="micro-surface rounded-lg p-3"
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
          class="micro-surface rounded-lg p-3"
          aria-label={"Saldo financeiro nos últimos #{@finance_filters.days} dias"}
        >
          <div class="flex items-center justify-between">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Saldo no filtro</p>
            <span class="text-xs text-base-content/65">{@finance_filters.days}d</span>
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
        class="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-6"
        aria-label="Filtros de lançamentos"
      >
        <select name="filters[period_mode]" class="select select-bordered select-sm">
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
        <select name="filters[days]" class="select select-bordered select-sm">
          <option value="7" selected={@finance_filters.days == "7"}>Últimos 7 dias</option>
          <option value="30" selected={@finance_filters.days == "30"}>Últimos 30 dias</option>
          <option value="90" selected={@finance_filters.days == "90"}>Últimos 90 dias</option>
          <option value="365" selected={@finance_filters.days == "365"}>Últimos 365 dias</option>
        </select>
        <input
          type="text"
          name="filters[occurred_on]"
          value={@finance_filters.occurred_on}
          placeholder="Data exata: dd/mm/aaaa"
          class="input input-bordered input-sm"
          inputmode="numeric"
          maxlength="10"
          pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
        />
        <input
          type="text"
          name="filters[month]"
          value={@finance_filters.month}
          placeholder="Mês: mm/aaaa"
          class="input input-bordered input-sm"
          inputmode="numeric"
          maxlength="7"
          pattern="^[0-9]{2}/[0-9]{4}$"
        />
        <input
          type="text"
          name="filters[occurred_from]"
          value={@finance_filters.occurred_from}
          placeholder="De: dd/mm/aaaa"
          class="input input-bordered input-sm"
          inputmode="numeric"
          maxlength="10"
          pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
        />
        <input
          type="text"
          name="filters[occurred_to]"
          value={@finance_filters.occurred_to}
          placeholder="Até: dd/mm/aaaa"
          class="input input-bordered input-sm"
          inputmode="numeric"
          maxlength="10"
          pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
        />
        <select name="filters[weekday]" class="select select-bordered select-sm">
          <option value="all" selected={@finance_filters.weekday == "all"}>Todos os dias</option>
          <option value="1" selected={@finance_filters.weekday == "1"}>Segunda</option>
          <option value="2" selected={@finance_filters.weekday == "2"}>Terça</option>
          <option value="3" selected={@finance_filters.weekday == "3"}>Quarta</option>
          <option value="4" selected={@finance_filters.weekday == "4"}>Quinta</option>
          <option value="5" selected={@finance_filters.weekday == "5"}>Sexta</option>
          <option value="6" selected={@finance_filters.weekday == "6"}>Sábado</option>
          <option value="0" selected={@finance_filters.weekday == "0"}>Domingo</option>
        </select>
        <select name="filters[sort_by]" class="select select-bordered select-sm">
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
        <select name="filters[kind]" class="select select-bordered select-sm">
          <option value="all" selected={@finance_filters.kind == "all"}>Todos tipos</option>
          <option value="income" selected={@finance_filters.kind == "income"}>Receita</option>
          <option value="expense" selected={@finance_filters.kind == "expense"}>Despesa</option>
        </select>
        <select name="filters[expense_profile]" class="select select-bordered select-sm">
          <option value="all" selected={@finance_filters.expense_profile == "all"}>
            Todos perfis
          </option>
          <option value="fixed" selected={@finance_filters.expense_profile == "fixed"}>Fixa</option>
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
        <select name="filters[payment_method]" class="select select-bordered select-sm">
          <option value="all" selected={@finance_filters.payment_method == "all"}>
            Todos métodos
          </option>
          <option value="credit" selected={@finance_filters.payment_method == "credit"}>
            Crédito
          </option>
          <option value="debit" selected={@finance_filters.payment_method == "debit"}>Débito</option>
        </select>
        <input
          type="text"
          name="filters[category]"
          value={@finance_filters.category}
          placeholder="Categoria..."
          class="input input-bordered input-sm"
          maxlength="50"
          list="finance-filter-categories"
        />
        <input
          type="text"
          name="filters[q]"
          value={@finance_filters.q}
          placeholder="Buscar descrição..."
          class="input input-bordered input-sm"
          maxlength="100"
        />
        <input
          type="number"
          name="filters[min_amount_cents]"
          value={@finance_filters.min_amount_cents}
          placeholder="Valor mín..."
          class="input input-bordered input-sm"
          min="0"
          step="100"
        />
        <input
          type="number"
          name="filters[max_amount_cents]"
          value={@finance_filters.max_amount_cents}
          placeholder="Valor máx..."
          class="input input-bordered input-sm"
          min="0"
          step="100"
        />
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
        <p :if={@finance_has_more?} class="text-[11px] text-base-content/58">
          Role para carregar mais
        </p>
      </div>

      <div
        id="finances-scroll-area"
        phx-hook="InfiniteScroll"
        data-event="load_more_finances"
        data-has-more={to_string(@finance_has_more?)}
        data-loading={to_string(@finance_loading_more?)}
        data-threshold-px="120"
        class="operations-scroll-area operations-scroll-area--list mt-2 rounded-xl border border-base-content/12 bg-base-100/28 p-2.5"
      >
        <div id="finances" phx-update="stream" class="space-y-2">
          <div id="finances-empty-wrapper" class="hidden only:block">
            <div
              id="empty-state-finances"
              class="rounded-xl border border-dashed border-base-content/25 px-4 py-6 text-center"
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
            class={["micro-surface rounded-xl border p-2.5", finance_row_border_class(entry.kind)]}
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
                    class="badge badge-sm border-info/62 bg-info/24 text-info font-semibold"
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
                    class="ds-inline-btn rounded-md px-2 py-1 text-xs"
                  >
                    Editar
                  </button>
                  <button
                    id={"finance-delete-btn-#{entry.id}"}
                    type="button"
                    phx-click="delete_finance"
                    phx-value-id={entry.id}
                    class="ds-inline-btn ds-inline-btn-danger rounded-md px-2 py-1 text-xs"
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
    </section>
    """
  end

  attr :entry, :any, default: nil
  attr :category_suggestions, :map, default: %{income: [], expense: [], all: []}

  defp finance_edit_modal(assigns) do
    ~H"""
    <div
      :if={is_map(@entry)}
      id="finance-edit-modal"
      class="fixed inset-0 z-[80] flex items-end justify-center p-3 sm:items-center sm:p-6"
      phx-window-keydown="cancel_edit_finance"
      phx-key="escape"
      aria-hidden="false"
    >
      <div id="finance-edit-modal-backdrop" aria-hidden="true" class="absolute inset-0 h-full w-full">
      </div>

      <section
        id="finance-edit-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"finance-edit-title-#{@entry.id}"}
        class="relative z-10 w-full max-w-3xl rounded-2xl border border-base-content/16 bg-base-100 p-5 shadow-[0_24px_70px_rgba(23,33,47,0.34)] sm:p-6"
      >
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
            class="btn btn-ghost btn-sm border border-base-content/16"
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
          class="mt-4 space-y-3 rounded-xl border border-base-content/14 bg-base-100/65 p-3.5 sm:p-4"
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
                class="select select-bordered w-full"
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
                Natureza da despesa
              </label>
              <select
                id={"finance-expense-profile-#{@entry.id}"}
                name="finance[expense_profile]"
                class="select select-bordered w-full"
              >
                <option value="" selected={is_nil(@entry.expense_profile)}>Não se aplica</option>
                <option value="fixed" selected={@entry.expense_profile == :fixed}>Fixa</option>
                <option value="variable" selected={@entry.expense_profile == :variable}>
                  Variável
                </option>
                <option value="recurring_fixed" selected={@entry.expense_profile == :recurring_fixed}>
                  Recorrente fixa
                </option>
                <option
                  value="recurring_variable"
                  selected={@entry.expense_profile == :recurring_variable}
                >
                  Recorrente variável
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
                class="select select-bordered w-full"
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
                class="input input-bordered w-full"
                placeholder="Ex: 330,00"
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
            class="input input-bordered w-full"
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
            class="input input-bordered w-full"
            placeholder="dd/mm/aaaa"
            inputmode="numeric"
            maxlength="10"
            pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
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
            class="input input-bordered w-full"
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
                  class="input input-bordered w-full"
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
                  class="input input-bordered w-full"
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
            <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit_finance">
              Cancelar
            </button>
            <button type="submit" class="btn btn-primary btn-sm">Salvar lançamento</button>
          </div>
        </form>
      </section>
    </div>
    """
  end

  defp finance_balance_cents(ops_counts) do
    Map.get(ops_counts, :finances_income_cents, 0) -
      Map.get(ops_counts, :finances_expense_cents, 0)
  end

  defp finance_row_border_class(:income), do: "border-success/25"
  defp finance_row_border_class(:expense), do: "border-error/25"
  defp finance_row_border_class(_), do: "border-base-content/15"

  defp finance_amount_class(:income), do: "text-sm font-semibold font-mono text-success"
  defp finance_amount_class(:expense), do: "text-sm font-semibold font-mono text-error"
  defp finance_amount_class(_), do: "text-sm font-semibold font-mono text-base-content"

  defp finance_kind_badge_class(:income),
    do: "badge badge-sm border-success/60 bg-success/26 text-success font-semibold"

  defp finance_kind_badge_class(:expense),
    do: "badge badge-sm border-error/62 bg-error/22 text-error font-semibold"

  defp finance_kind_badge_class(_),
    do: "badge badge-sm border-base-content/34 bg-base-100 text-base-content/92 font-semibold"

  defp finance_kind_label(:income), do: "Receita"
  defp finance_kind_label(:expense), do: "Despesa"
  defp finance_kind_label(_), do: "Tipo"

  defp finance_profile_label(:fixed), do: "Fixa"
  defp finance_profile_label(:variable), do: "Variável"
  defp finance_profile_label(:recurring_fixed), do: "Recorrente fixa"
  defp finance_profile_label(:recurring_variable), do: "Recorrente variável"

  defp finance_profile_label(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.capitalize()

  defp finance_profile_label(_), do: "Perfil"

  defp finance_profile_badge_class(:fixed),
    do: "badge badge-sm border-info/60 bg-info/24 text-info font-semibold"

  defp finance_profile_badge_class(:variable),
    do: "badge badge-sm border-warning/66 bg-warning/30 text-warning-content font-semibold"

  defp finance_profile_badge_class(:recurring_fixed),
    do: "badge badge-sm border-primary/62 bg-primary/24 text-primary font-semibold"

  defp finance_profile_badge_class(:recurring_variable),
    do: "badge badge-sm border-accent/64 bg-accent/28 text-accent-content font-semibold"

  defp finance_profile_badge_class(_),
    do: "badge badge-sm border-base-content/34 bg-base-100 text-base-content/92 font-semibold"

  defp finance_payment_label(:debit), do: "Débito"
  defp finance_payment_label(:credit), do: "Crédito"

  defp finance_payment_label(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.capitalize()

  defp finance_payment_label(_), do: "Pagamento"

  defp finance_payment_badge_class(:debit),
    do: "badge badge-sm border-success/60 bg-success/26 text-success font-semibold"

  defp finance_payment_badge_class(:credit),
    do: "badge badge-sm border-error/62 bg-error/22 text-error font-semibold"

  defp finance_payment_badge_class(_),
    do: "badge badge-sm border-base-content/34 bg-base-100 text-base-content/92 font-semibold"

  defp finance_installments_badge_class,
    do: "badge badge-sm border-secondary/62 bg-secondary/22 text-secondary font-semibold"

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

  defp money_input_value(cents) when is_integer(cents) and cents >= 0 do
    integer_part = cents |> div(100) |> Integer.to_string()
    decimal_part = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    integer_part <> "," <> decimal_part
  end

  defp money_input_value(cents) when is_integer(cents), do: Integer.to_string(cents)
  defp money_input_value(_cents), do: ""

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

  defp normalize_category_suggestions(suggestions) when is_map(suggestions) do
    Map.merge(%{income: [], expense: [], all: []}, suggestions)
  end

  defp normalize_category_suggestions(_suggestions), do: %{income: [], expense: [], all: []}
end
