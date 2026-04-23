defmodule OrganizerWeb.DashboardLive.Components.OperationsPanel do
  use Phoenix.Component
  import OrganizerWeb.CoreComponents, only: [icon: 1]
  import OrganizerWeb.DashboardLive.Formatters

  attr :streams, :map, required: true
  attr :ops_tab, :string, required: true
  attr :task_filters, :map, required: true
  attr :finance_filters, :map, required: true
  attr :account_links, :list, default: []
  attr :current_user_id, :integer, default: nil
  attr :editing_task_id, :any, default: nil
  attr :editing_finance_id, :any, default: nil
  attr :task_details_modal_task, :any, default: nil
  attr :ops_counts, :map, required: true

  def operations_panel(assigns) do
    ~H"""
    <section
      id="operations-panel"
      class="operations-shell surface-card order-6 rounded-2xl p-4 scroll-mt-20"
    >
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
          Operação diária
        </h2>
        <div class="flex flex-wrap gap-2" aria-label="Abas operacionais">
          <button
            id="ops-tab-tasks"
            type="button"
            phx-click="set_ops_tab"
            phx-value-tab="tasks"
            class={[
              "btn btn-sm ds-pill-btn",
              @ops_tab == "tasks" && "btn-primary",
              @ops_tab != "tasks" && "btn-soft"
            ]}
          >
            Tarefas
          </button>
          <button
            id="ops-tab-finances"
            type="button"
            phx-click="set_ops_tab"
            phx-value-tab="finances"
            class={[
              "btn btn-sm ds-pill-btn",
              @ops_tab == "finances" && "btn-primary",
              @ops_tab != "finances" && "btn-soft"
            ]}
          >
            Financeiro
          </button>
        </div>
      </div>

      <section
        id="task-timer-box"
        phx-hook="TaskTimerBox"
        phx-update="ignore"
        data-default-minutes="30"
        data-complete-label="Tempo concluído"
        class="mt-3 rounded-xl border border-base-content/12 bg-base-100/35 p-4"
      >
        <div class="flex flex-wrap items-start justify-between gap-2">
          <div>
            <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/72">
              Time Box
            </h3>
            <p class="text-xs text-base-content/65">
              Timer de foco para tarefa em execução.
            </p>
          </div>
          <span
            id="task-timer-status"
            class="inline-flex items-center rounded-full border border-base-content/20 bg-base-100/80 px-2.5 py-1 text-xs font-semibold text-base-content/72"
          >
            Pronto
          </span>
        </div>

        <div class="mt-3 grid gap-2 lg:grid-cols-[minmax(0,1fr)_126px_110px_auto]">
          <select
            id="task-timer-task-select"
            class="select select-bordered select-sm w-full"
            aria-label="Selecionar tarefa para timer"
          >
            <option value="">Selecione uma tarefa em andamento</option>
            <option :for={{_dom_id, task} <- @streams.tasks_in_progress} value={task.id}>
              {task.title}
            </option>
          </select>

          <select
            id="task-timer-preset"
            class="select select-bordered select-sm w-full"
            aria-label="Preset de duração do timer"
          >
            <option value="15">15 min</option>
            <option value="25">25 min</option>
            <option value="30" selected>30 min</option>
            <option value="45">45 min</option>
            <option value="60">60 min</option>
          </select>

          <input
            id="task-timer-minutes"
            type="number"
            value="30"
            min="1"
            max="720"
            step="1"
            inputmode="numeric"
            class="input input-bordered input-sm w-full"
            aria-label="Minutos customizados do timer"
          />

          <button
            id="task-timer-apply"
            type="button"
            class="btn btn-soft btn-sm whitespace-nowrap"
          >
            Aplicar
          </button>
        </div>

        <div class="mt-3 flex flex-wrap gap-2">
          <button id="task-timer-start" type="button" class="btn btn-primary btn-sm">Iniciar</button>
          <button id="task-timer-pause" type="button" class="btn btn-soft btn-sm">Pausar</button>
          <button id="task-timer-reset" type="button" class="btn btn-ghost btn-sm">Resetar</button>
        </div>

        <div class="mt-3">
          <p id="task-timer-remaining" class="text-sm font-semibold text-base-content/80">
            Restante: 30:00
          </p>

          <div class="mt-2 h-2 overflow-hidden rounded-full bg-base-content/14">
            <div
              id="task-timer-progress"
              class="h-full rounded-full bg-success transition-[width] duration-300 ease-out"
              style="width: 0%;"
            >
            </div>
          </div>

          <p id="task-timer-feedback" class="mt-2 text-xs text-base-content/65">
            Ative as notificações para ser avisado quando o timer terminar.
          </p>
        </div>
      </section>

      <div id="operations-panel-content">
        <div class="mt-3 grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
          <article
            id="ops-card-tasks-open"
            class="micro-surface rounded-lg p-3"
            aria-label={"Tarefas abertas nos últimos #{@task_filters.days} dias"}
          >
            <div class="flex items-center justify-between">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Tarefas abertas</p>
              <span class="text-xs text-base-content/65">{@task_filters.days}d</span>
            </div>
            <p class="mt-1 text-lg font-semibold text-base-content">
              {@ops_counts.tasks_open}
            </p>
          </article>

          <article
            id="ops-card-tasks-total"
            class="micro-surface rounded-lg p-3"
            aria-label={"Tarefas no filtro nos últimos #{@task_filters.days} dias"}
          >
            <div class="flex items-center justify-between">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Tarefas no filtro</p>
              <span class="text-xs text-base-content/65">{@task_filters.days}d</span>
            </div>
            <p class="mt-1 text-lg font-semibold text-base-content">
              {@ops_counts.tasks_total}
            </p>
          </article>

          <article
            id="ops-card-finances-total"
            class="micro-surface rounded-lg p-3"
            aria-label={"Lançamentos no filtro nos últimos #{@finance_filters.days} dias"}
          >
            <div class="flex items-center justify-between">
              <p class="text-xs uppercase tracking-wide text-base-content/65">
                Lançamentos no filtro
              </p>
              <span class="text-xs text-base-content/65">{@finance_filters.days}d</span>
            </div>
            <p class="mt-1 text-lg font-semibold text-base-content">
              {@ops_counts.finances_total}
            </p>
            <p class="mt-1 text-xs text-base-content/65">
              Receitas: {Map.get(@ops_counts, :finances_income_total, 0)} • Despesas: {Map.get(
                @ops_counts,
                :finances_expense_total,
                0
              )}
            </p>
          </article>

          <article
            id="ops-card-finances-balance"
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

        <div class="mt-3 space-y-4">
          <section class={[
            "rounded-xl border border-base-content/12 bg-base-100/35 p-4",
            @ops_tab != "tasks" && "hidden"
          ]}>
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Tarefas
            </h2>

            <section
              id="task-focus-timer"
              phx-hook="TaskFocusTimer"
              data-storage-key={"organizer:task-focus-timer:user:#{@current_user_id || "anon"}"}
              class="mt-3 rounded-xl border border-base-content/12 bg-base-100/50 p-3"
            >
              <div class="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                    Time Box
                  </p>
                  <p class="text-xs text-base-content/65">
                    Timer de foco para tarefa em execução.
                  </p>
                </div>
                <span
                  id="task-focus-state"
                  class="badge badge-sm border-base-content/24 bg-base-100 text-base-content/80"
                >
                  Pronto
                </span>
              </div>

              <div class="mt-3 flex flex-col gap-2 xl:flex-row xl:items-center">
                <select id="task-focus-task" class="select select-bordered select-sm w-full xl:flex-1">
                  <option value="">Selecione uma tarefa em andamento</option>
                  <option :for={{_dom_id, task} <- @streams.tasks_in_progress} value={task.id}>
                    {task.title || "Tarefa em andamento"}
                  </option>
                </select>

                <div class="flex flex-col gap-2 sm:flex-row sm:items-center xl:shrink-0">
                  <select
                    id="task-focus-duration"
                    class="select select-bordered select-sm w-full sm:w-32"
                  >
                    <option value="">Duração</option>
                    <option :for={minutes <- task_focus_duration_presets()} value={minutes}>
                      {minutes} min
                    </option>
                  </select>

                  <div class="flex items-center gap-2">
                    <input
                      id="task-focus-duration-custom"
                      type="number"
                      min="1"
                      max="600"
                      step="1"
                      placeholder="Min personalizado"
                      class="input input-bordered input-sm w-full sm:w-28"
                    />
                    <button
                      id="task-focus-apply-custom"
                      type="button"
                      class="btn btn-ghost btn-sm border border-base-content/18"
                    >
                      Aplicar
                    </button>
                  </div>

                  <div class="grid grid-cols-3 gap-2 sm:flex sm:flex-wrap">
                    <button id="task-focus-start" type="button" class="btn btn-primary btn-sm">
                      Iniciar
                    </button>
                    <button id="task-focus-pause" type="button" class="btn btn-soft btn-sm">
                      Pausar
                    </button>
                    <button id="task-focus-reset" type="button" class="btn btn-ghost btn-sm">
                      Resetar
                    </button>
                  </div>
                </div>
              </div>

              <div class="mt-3 flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
                <p class="text-xs text-base-content/70">
                  Restante:
                  <span id="task-focus-remaining" class="font-semibold text-base-content">30:00</span>
                </p>
                <p id="task-focus-notification-state" class="text-[11px] text-base-content/65">
                  Notificações do navegador desativadas.
                </p>
              </div>

              <div class="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-base-200/70">
                <div
                  id="task-focus-progress"
                  class="h-full w-0 rounded-full bg-info transition-all duration-500"
                >
                </div>
              </div>

              <div class="mt-2 flex justify-end">
                <button
                  id="task-focus-request-notification"
                  type="button"
                  class="btn btn-ghost btn-xs border border-base-content/14"
                >
                  Ativar notificação do navegador
                </button>
              </div>
            </section>

            <form
              id="task-filters"
              phx-change="filter_tasks"
              phx-debounce="500"
              class="mt-3 grid gap-2 sm:grid-cols-2 xl:grid-cols-4"
              aria-label="Filtros de tarefas"
            >
              <select name="filters[status]" class="select select-bordered select-sm">
                <option value="all" selected={@task_filters.status == "all"}>Todos status</option>
                <option value="todo" selected={@task_filters.status == "todo"}>Todo</option>
                <option value="in_progress" selected={@task_filters.status == "in_progress"}>
                  Em andamento
                </option>
                <option value="done" selected={@task_filters.status == "done"}>Concluída</option>
              </select>
              <select name="filters[priority]" class="select select-bordered select-sm">
                <option value="all" selected={@task_filters.priority == "all"}>
                  Todas prioridades
                </option>
                <option value="low" selected={@task_filters.priority == "low"}>Baixa</option>
                <option value="medium" selected={@task_filters.priority == "medium"}>Média</option>
                <option value="high" selected={@task_filters.priority == "high"}>Alta</option>
              </select>
              <select name="filters[days]" class="select select-bordered select-sm">
                <option value="7" selected={@task_filters.days == "7"}>7 dias</option>
                <option value="14" selected={@task_filters.days == "14"}>14 dias</option>
                <option value="30" selected={@task_filters.days == "30"}>30 dias</option>
              </select>
              <input
                type="text"
                name="filters[q]"
                value={@task_filters.q}
                placeholder="Buscar por título ou notas..."
                class="input input-bordered input-sm"
                maxlength="100"
              />
            </form>

            <div id="tasks" class="mt-3">
              <div :if={@ops_counts.tasks_total == 0} id="tasks-empty-wrapper">
                <div
                  id="empty-state-tasks"
                  class="rounded-xl border border-dashed border-base-content/25 px-4 py-6 text-center"
                >
                  <p class="text-sm font-semibold text-base-content/85">Nenhuma tarefa cadastrada</p>
                  <p class="mt-1 text-xs leading-5 text-base-content/65">
                    Use o lançamento rápido de tarefas para começar o planejamento operacional.
                  </p>
                </div>
              </div>

              <div
                :if={@ops_counts.tasks_total > 0}
                id="tasks-kanban-board"
                class="grid gap-3 xl:grid-cols-3"
              >
                <.task_kanban_column
                  column_id="tasks-column-todo"
                  stream={@streams.tasks_todo}
                  title="A fazer"
                  subtitle="Itens prontos para iniciar"
                  status={:todo}
                  count={task_column_count(@ops_counts, :todo)}
                  account_links={@account_links}
                  current_user_id={@current_user_id}
                  editing_task_id={@editing_task_id}
                />
                <.task_kanban_column
                  column_id="tasks-column-in-progress"
                  stream={@streams.tasks_in_progress}
                  title="Em andamento"
                  subtitle="Tarefas em execução"
                  status={:in_progress}
                  count={task_column_count(@ops_counts, :in_progress)}
                  account_links={@account_links}
                  current_user_id={@current_user_id}
                  editing_task_id={@editing_task_id}
                />
                <.task_kanban_column
                  column_id="tasks-column-done"
                  stream={@streams.tasks_done}
                  title="Concluídas"
                  subtitle="Entregas finalizadas"
                  status={:done}
                  count={task_column_count(@ops_counts, :done)}
                  account_links={@account_links}
                  current_user_id={@current_user_id}
                  editing_task_id={@editing_task_id}
                />
              </div>
            </div>
          </section>

          <section class={[
            "rounded-xl border border-base-content/12 bg-base-100/35 p-4",
            @ops_tab != "finances" && "hidden"
          ]}>
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Financeiro
            </h2>
            <form
              id="finance-filters"
              phx-change="filter_finances"
              phx-debounce="500"
              class="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-4 2xl:grid-cols-8"
              aria-label="Filtros de lançamentos"
            >
              <select name="filters[days]" class="select select-bordered select-sm">
                <option value="7" selected={@finance_filters.days == "7"}>Últimos 7 dias</option>
                <option value="30" selected={@finance_filters.days == "30"}>Últimos 30 dias</option>
                <option value="90" selected={@finance_filters.days == "90"}>Últimos 90 dias</option>
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
                <option value="fixed" selected={@finance_filters.expense_profile == "fixed"}>
                  Fixa
                </option>
                <option value="variable" selected={@finance_filters.expense_profile == "variable"}>
                  Variável
                </option>
              </select>
              <select name="filters[payment_method]" class="select select-bordered select-sm">
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
                name="filters[category]"
                value={@finance_filters.category}
                placeholder="Categoria..."
                class="input input-bordered input-sm"
                maxlength="50"
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

            <div id="finances" phx-update="stream" class="mt-3 space-y-2">
              <div id="finances-empty-wrapper" class="hidden only:block">
                <div
                  id="empty-state-finances"
                  class="rounded-xl border border-dashed border-base-content/25 px-4 py-6 text-center"
                >
                  <p class="text-sm font-semibold text-base-content/85">
                    Nenhum lançamento financeiro
                  </p>
                  <p class="mt-1 text-xs leading-5 text-base-content/65">
                    Registre rendas e gastos no card de lançamento rápido para começar seu histórico.
                  </p>
                </div>
              </div>

              <article
                :for={{id, entry} <- @streams.finances}
                id={id}
                class={[
                  "micro-surface rounded-xl border p-3",
                  finance_row_border_class(entry.kind)
                ]}
              >
                <div class="flex flex-wrap items-start justify-between gap-3 sm:flex-nowrap">
                  <div class="min-w-0 flex-1">
                    <p class="truncate text-sm font-semibold text-base-content">{entry.category}</p>
                    <p
                      :if={entry.description && String.trim(entry.description) != ""}
                      class="mt-1 text-xs text-base-content/72"
                    >
                      {entry.description}
                    </p>
                    <p class="mt-1 text-xs text-base-content/65">
                      {date_input_value(entry.occurred_on)}
                    </p>
                  </div>
                  <p class={finance_amount_class(entry.kind)}>
                    {format_money(entry.amount_cents)}
                  </p>
                </div>

                <div class="mt-2 flex flex-wrap gap-1.5">
                  <span class={finance_kind_badge_class(entry.kind)}>
                    {finance_kind_label(entry.kind)}
                  </span>
                  <span :if={entry.expense_profile} class="badge badge-outline badge-sm">
                    {finance_profile_label(entry.expense_profile)}
                  </span>
                  <span :if={entry.payment_method} class="badge badge-outline badge-sm">
                    {finance_payment_label(entry.payment_method)}
                  </span>
                </div>

                <div class="mt-3 flex flex-wrap gap-2">
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

                <form
                  :if={editing?(@editing_finance_id, entry.id)}
                  id={"finance-edit-form-#{entry.id}"}
                  phx-submit="save_finance"
                  class="border border-base-content/16 bg-base-100/80 mt-3 space-y-2 rounded-md p-3"
                >
                  <input type="hidden" name="_id" value={entry.id} />
                  <div class="grid gap-2 sm:grid-cols-2">
                    <div>
                      <label
                        class="text-xs font-medium text-base-content/70"
                        for={"finance-kind-#{entry.id}"}
                      >
                        Tipo
                      </label>
                      <select
                        id={"finance-kind-#{entry.id}"}
                        name="finance[kind]"
                        class="select select-bordered w-full"
                      >
                        <option value="income" selected={entry.kind == :income}>Receita</option>
                        <option value="expense" selected={entry.kind == :expense}>Despesa</option>
                      </select>
                    </div>
                    <div>
                      <label
                        class="text-xs font-medium text-base-content/70"
                        for={"finance-expense-profile-#{entry.id}"}
                      >
                        Natureza da despesa
                      </label>
                      <select
                        id={"finance-expense-profile-#{entry.id}"}
                        name="finance[expense_profile]"
                        class="select select-bordered w-full"
                      >
                        <option value="" selected={is_nil(entry.expense_profile)}>
                          Não se aplica
                        </option>
                        <option value="fixed" selected={entry.expense_profile == :fixed}>
                          Fixa
                        </option>
                        <option value="variable" selected={entry.expense_profile == :variable}>
                          Variável
                        </option>
                      </select>
                    </div>
                    <div>
                      <label
                        class="text-xs font-medium text-base-content/70"
                        for={"finance-payment-method-#{entry.id}"}
                      >
                        Pagamento
                      </label>
                      <select
                        id={"finance-payment-method-#{entry.id}"}
                        name="finance[payment_method]"
                        class="select select-bordered w-full"
                      >
                        <option value="" selected={is_nil(entry.payment_method)}>
                          Não se aplica
                        </option>
                        <option value="debit" selected={entry.payment_method == :debit}>
                          Débito
                        </option>
                        <option value="credit" selected={entry.payment_method == :credit}>
                          Crédito
                        </option>
                      </select>
                    </div>
                    <div>
                      <label
                        class="text-xs font-medium text-base-content/70"
                        for={"finance-amount-#{entry.id}"}
                      >
                        Valor
                      </label>
                      <input
                        id={"finance-amount-#{entry.id}"}
                        name="finance[amount_cents]"
                        type="number"
                        required
                        value={entry.amount_cents}
                        class="input input-bordered w-full"
                      />
                    </div>
                  </div>
                  <label
                    class="text-xs font-medium text-base-content/70"
                    for={"finance-category-#{entry.id}"}
                  >
                    Categoria
                  </label>
                  <input
                    id={"finance-category-#{entry.id}"}
                    name="finance[category]"
                    type="text"
                    required
                    value={entry.category}
                    class="input input-bordered w-full"
                  />
                  <label
                    class="text-xs font-medium text-base-content/70"
                    for={"finance-date-#{entry.id}"}
                  >
                    Data
                  </label>
                  <input
                    id={"finance-date-#{entry.id}"}
                    name="finance[occurred_on]"
                    type="date"
                    value={date_input_value(entry.occurred_on)}
                    class="input input-bordered w-full"
                  />
                  <label
                    class="text-xs font-medium text-base-content/70"
                    for={"finance-description-#{entry.id}"}
                  >
                    Descrição
                  </label>
                  <input
                    id={"finance-description-#{entry.id}"}
                    name="finance[description]"
                    type="text"
                    value={entry.description || ""}
                    class="input input-bordered w-full"
                  />
                  <div class="flex flex-wrap gap-2">
                    <button type="submit" class="btn btn-primary btn-sm">Salvar</button>
                    <button
                      type="button"
                      class="btn btn-ghost btn-sm"
                      phx-click="cancel_edit_finance"
                    >
                      Cancelar
                    </button>
                  </div>
                </form>
              </article>
            </div>
          </section>

          <.task_details_modal task={@task_details_modal_task} />
        </div>
      </div>
    </section>
    """
  end

  attr :column_id, :string, required: true
  attr :stream, :any, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :status, :atom, required: true
  attr :count, :integer, required: true
  attr :account_links, :list, default: []
  attr :current_user_id, :integer, default: nil
  attr :editing_task_id, :any, default: nil

  defp task_kanban_column(assigns) do
    ~H"""
    <section
      id={@column_id}
      class={[
        "rounded-xl border p-3",
        task_column_surface_class(@status)
      ]}
    >
      <div class="flex items-start justify-between gap-2">
        <div class="min-w-0">
          <p class="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-base-content/75">
            <.icon name={task_column_icon(@status)} class="size-3.5" />
            {@title}
          </p>
          <p class="mt-1 text-xs text-base-content/60">{@subtitle}</p>
        </div>
        <span class={task_column_count_badge_class(@status)}>
          {@count}
        </span>
      </div>

      <div id={"#{@column_id}-stream"} phx-update="stream" class="mt-3 space-y-2 min-h-[10rem]">
        <div id={"#{@column_id}-empty-wrapper"} class="hidden only:block">
          <div
            id={"#{@column_id}-empty"}
            class="rounded-lg border border-dashed border-base-content/18 bg-base-100/45 px-3 py-4 text-center"
          >
            <p class="text-xs font-medium text-base-content/70">Sem tarefas nesta coluna</p>
          </div>
        </div>

        <article
          :for={{id, task} <- @stream}
          id={id}
          class={[
            "micro-surface rounded-xl border p-3 transition duration-200 ease-out hover:-translate-y-0.5 hover:shadow-md",
            task_status_border_class(task.status),
            task.status == :done && "bg-success/8"
          ]}
        >
          <% checklist_items = task_checklist_items(task) %>
          <% {checked_items, total_items} = task_checklist_totals(task) %>

          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm font-semibold text-base-content">{task.title}</p>
              <p class="mt-1 flex items-center gap-1 text-xs text-base-content/65">
                <.icon name="hero-calendar-days" class="size-3.5" />
                <span>Prazo: {task_due_label(task.due_on)}</span>
              </p>
              <p :if={total_items > 0} class="mt-1 text-xs font-medium text-info/80">
                Checklist: {checked_items}/{total_items} itens concluídos
              </p>
              <.task_notes_text
                :if={task.notes && String.trim(task.notes) != ""}
                notes={task.notes}
                class="mt-2 text-xs text-base-content/72"
                truncate={true}
              />
            </div>

            <div class="flex shrink-0 flex-wrap gap-1.5">
              <span class={task_priority_badge_class(task.priority)}>
                {task_priority_label(task.priority)}
              </span>
              <span class={task_status_badge_class(task.status)}>
                {task_status_label(task.status)}
              </span>
              <span class={task_privacy_badge_class(task)}>
                {task_privacy_label(task)}
              </span>
            </div>
          </div>

          <div :if={checklist_items != []} class="mt-3 space-y-2">
            <form
              :for={item <- checklist_items}
              id={"task-checklist-item-form-#{task.id}-#{item.id}"}
              phx-submit="save_task_checklist_item_label"
              class="flex flex-wrap items-center gap-2 rounded-lg border border-base-content/16 bg-base-100/55 px-2.5 py-2 sm:flex-nowrap"
            >
              <input type="hidden" name="task_id" value={task.id} />
              <input type="hidden" name="item_id" value={item.id} />
              <button
                id={"task-checklist-toggle-#{task.id}-#{item.id}"}
                type="button"
                phx-click="toggle_task_checklist_item"
                phx-value-task_id={task.id}
                phx-value-item_id={item.id}
                phx-value-checked={if(item.checked, do: "false", else: "true")}
                class={[
                  "h-5 w-5 shrink-0 flex items-center justify-center rounded border transition",
                  item.checked &&
                    "border-success/50 bg-success/20 text-success-content hover:border-success/60 hover:bg-success/28",
                  !item.checked &&
                    "border-base-content/28 bg-transparent text-base-content/50 hover:border-base-content/40 hover:bg-base-content/6"
                ]}
                aria-label={
                  if item.checked,
                    do: "Desmarcar item da checklist",
                    else: "Marcar item da checklist"
                }
              >
                <%= if item.checked do %>
                  <.icon name="hero-check" class="size-3.5" />
                <% else %>
                  <span class="inline-block h-3 w-3 border border-current rounded-full"></span>
                <% end %>
              </button>

              <input
                id={"task-checklist-label-#{task.id}-#{item.id}"}
                name="checklist_item[label]"
                type="text"
                value={item.label}
                maxlength="140"
                class={[
                  "flex-1 input input-sm bg-base-100/80 border border-base-content/14 px-2.5 py-1.5 text-sm transition focus:border-info/50 focus:outline-none focus:ring-1 focus:ring-info/20",
                  item.checked && "line-through text-base-content/45"
                ]}
              />

              <button
                id={"task-checklist-save-#{task.id}-#{item.id}"}
                type="submit"
                class="btn btn-ghost btn-xs px-2 hover:bg-info/10 hover:text-info/90"
              >
                Salvar
              </button>
              <button
                id={"task-checklist-delete-#{task.id}-#{item.id}"}
                type="button"
                phx-click="delete_task_checklist_item"
                phx-value-task_id={task.id}
                phx-value-item_id={item.id}
                class="btn btn-ghost btn-xs px-2 text-error/75 hover:bg-error/10 hover:text-error/90"
              >
                Excluir
              </button>
            </form>
          </div>

          <form
            id={"task-checklist-add-form-#{task.id}"}
            phx-submit="add_task_checklist_item"
            class="mt-3 flex flex-wrap items-center gap-2 rounded-lg bg-base-100/30 p-2 sm:flex-nowrap"
          >
            <input type="hidden" name="task_id" value={task.id} />
            <input
              id={"task-checklist-add-input-#{task.id}"}
              name="checklist_item[label]"
              type="text"
              maxlength="140"
              placeholder="Novo item..."
              class="flex-1 input input-sm bg-base-100 border border-base-content/12 px-2.5 py-1.5 text-sm transition focus:border-info/50 focus:outline-none focus:ring-1 focus:ring-info/20"
            />
            <button
              id={"task-checklist-add-btn-#{task.id}"}
              type="submit"
              class="btn btn-soft btn-xs shrink-0 border-base-content/16 hover:border-info/40 hover:bg-info/12"
            >
              Adicionar
            </button>
          </form>

          <div class="mt-3 flex flex-wrap gap-2">
            <button
              id={"task-details-btn-#{task.id}"}
              type="button"
              phx-click="open_task_details"
              phx-value-id={task.id}
              class="btn btn-ghost btn-xs border border-base-content/18 hover:border-info/34 hover:bg-info/10"
            >
              <.icon name="hero-eye" class="size-3.5" /> Detalhes
            </button>
            <button
              id={"task-status-quick-btn-#{task.id}"}
              type="button"
              phx-click="set_task_status"
              phx-value-id={task.id}
              phx-value-status={task_primary_action_status(task.status)}
              class={task_primary_action_class(task.status)}
            >
              <.icon name={task_primary_action_icon(task.status)} class="size-3.5" />
              {task_primary_action_label(task.status)}
            </button>
            <button
              :if={task.status == :in_progress}
              id={"task-back-to-todo-btn-#{task.id}"}
              type="button"
              phx-click="set_task_status"
              phx-value-id={task.id}
              phx-value-status="todo"
              class="btn btn-ghost btn-xs border border-base-content/18 hover:border-base-content/34"
            >
              Voltar
            </button>
            <button
              id={"task-edit-btn-#{task.id}"}
              type="button"
              phx-click="start_edit_task"
              phx-value-id={task.id}
              class="ds-inline-btn rounded-md px-2 py-1 text-xs"
            >
              Editar
            </button>
            <button
              id={"task-delete-btn-#{task.id}"}
              type="button"
              phx-click="delete_task"
              phx-value-id={task.id}
              class="ds-inline-btn ds-inline-btn-danger rounded-md px-2 py-1 text-xs"
            >
              Excluir
            </button>
          </div>

          <div
            :if={task_linked_sync?(task)}
            id={"task-share-state-#{task.id}"}
            class="mt-3 rounded-lg border border-success/24 bg-success/8 p-2.5"
          >
            <p class="flex items-center gap-1.5 text-xs font-semibold text-success-content">
              <.icon name="hero-link" class="size-3.5" /> Atrelada ao vínculo (sincronizado)
            </p>
            <p class="mt-1 text-[11px] text-base-content/70">
              {task_share_link_name_by_id(@account_links, @current_user_id, task.shared_with_link_id)}
            </p>
          </div>

          <form
            :if={!task_linked_sync?(task)}
            id={"task-share-form-#{task.id}"}
            phx-submit="share_task_with_link"
            class="mt-3 rounded-lg border border-base-content/14 bg-base-100/45 p-2.5"
          >
            <input type="hidden" name="task_id" value={task.id} />
            <input type="hidden" name="share_task[attach_to_link]" value="false" />

            <input
              id={"task-share-check-#{task.id}"}
              name="share_task[attach_to_link]"
              type="checkbox"
              value="true"
              class="peer sr-only"
              disabled={Enum.empty?(@account_links)}
            />
            <label
              for={"task-share-check-#{task.id}"}
              class={[
                "flex w-full items-center justify-between gap-2 rounded-md border border-base-content/12 px-2 py-1.5 transition",
                Enum.empty?(@account_links) &&
                  "cursor-not-allowed opacity-60",
                !Enum.empty?(@account_links) &&
                  "cursor-pointer hover:border-info/30 hover:bg-info/6"
              ]}
            >
              <span class="inline-flex items-center gap-1.5 text-xs font-medium text-base-content/80">
                <.icon name="hero-lock-closed" class="size-3.5" /> Tarefa privada por padrão
              </span>
              <span class="text-[11px] text-base-content/65">
                Marque para atrelar ao vínculo
              </span>
            </label>

            <div class="mt-2 hidden w-full items-center gap-2 peer-checked:flex">
              <select
                id={"task-share-link-#{task.id}"}
                name="share_task[link_id]"
                class="select select-bordered select-xs min-w-56 flex-1"
              >
                <option :if={Enum.empty?(@account_links)} value="">
                  Sem vínculos ativos
                </option>
                <option
                  :for={{label, value} <- task_share_link_options(@account_links, @current_user_id)}
                  value={value}
                >
                  {label}
                </option>
              </select>
              <button
                id={"task-share-btn-#{task.id}"}
                type="submit"
                class="btn btn-soft btn-xs border-base-content/18"
              >
                <.icon name="hero-link" class="size-3.5" /> Atrelar vínculo
              </button>
            </div>

            <p :if={Enum.empty?(@account_links)} class="mt-2 text-[11px] text-base-content/65">
              Crie um vínculo para permitir compartilhamento.
            </p>
          </form>

          <form
            :if={editing?(@editing_task_id, task.id)}
            id={"task-edit-form-#{task.id}"}
            phx-submit="save_task"
            class="border border-base-content/16 bg-base-100/80 mt-3 space-y-2 rounded-md p-3"
          >
            <input type="hidden" name="_id" value={task.id} />
            <label
              class="text-xs font-medium text-base-content/70"
              for={"task-title-#{task.id}"}
            >
              Título
            </label>
            <input
              id={"task-title-#{task.id}"}
              name="task[title]"
              type="text"
              value={task.title}
              required
              class="input input-bordered w-full"
            />
            <label class="text-xs font-medium text-base-content/70" for={"task-due-#{task.id}"}>
              Data
            </label>
            <input
              id={"task-due-#{task.id}"}
              name="task[due_on]"
              type="date"
              value={date_input_value(task.due_on)}
              class="input input-bordered w-full"
            />
            <div class="grid gap-2 sm:grid-cols-2">
              <div>
                <label
                  class="text-xs font-medium text-base-content/70"
                  for={"task-priority-#{task.id}"}
                >
                  Prioridade
                </label>
                <select
                  id={"task-priority-#{task.id}"}
                  name="task[priority]"
                  class="select select-bordered w-full"
                >
                  <option value="low" selected={task.priority == :low}>Baixa</option>
                  <option value="medium" selected={task.priority == :medium}>Média</option>
                  <option value="high" selected={task.priority == :high}>Alta</option>
                </select>
              </div>
              <div>
                <label
                  class="text-xs font-medium text-base-content/70"
                  for={"task-status-#{task.id}"}
                >
                  Status
                </label>
                <select
                  id={"task-status-#{task.id}"}
                  name="task[status]"
                  class="select select-bordered w-full"
                >
                  <option value="todo" selected={task.status == :todo}>Todo</option>
                  <option value="in_progress" selected={task.status == :in_progress}>
                    Em andamento
                  </option>
                  <option value="done" selected={task.status == :done}>Concluída</option>
                </select>
              </div>
            </div>
            <div class="flex flex-wrap gap-2">
              <button type="submit" class="btn btn-primary btn-sm">Salvar</button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit_task">
                Cancelar
              </button>
            </div>
          </form>
        </article>
      </div>
    </section>
    """
  end

  attr :task, :any, default: nil

  defp task_details_modal(assigns) do
    ~H"""
    <div
      :if={is_map(@task)}
      id="task-details-modal"
      class="fixed inset-0 z-[80] flex items-end justify-center p-3 sm:items-center sm:p-6"
      phx-window-keydown="close_task_details"
      phx-key="escape"
      aria-hidden="false"
    >
      <div
        id="task-details-modal-backdrop"
        aria-hidden="true"
        class="absolute inset-0 h-full w-full"
      >
      </div>

      <% checklist_items = task_checklist_items(@task) %>
      <% {checked_items, total_items} = task_checklist_totals(@task) %>

      <section
        id="task-details-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="task-details-title"
        class="relative z-10 w-full max-w-2xl rounded-2xl border border-base-content/16 bg-base-100 p-5 shadow-[0_24px_70px_rgba(23,33,47,0.34)] sm:p-6"
      >
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/65">
              Detalhes da tarefa
            </p>
            <h2
              id="task-details-title"
              class="mt-1 break-words text-xl font-semibold text-base-content"
            >
              {@task.title}
            </h2>
          </div>

          <button
            id="task-details-close-btn"
            type="button"
            phx-click="close_task_details"
            class="btn btn-ghost btn-sm border border-base-content/16"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <div class="mt-3 flex flex-wrap gap-1.5">
          <span class={task_priority_badge_class(@task.priority)}>
            {task_priority_label(@task.priority)}
          </span>
          <span class={task_status_badge_class(@task.status)}>
            {task_status_label(@task.status)}
          </span>
          <span class={task_privacy_badge_class(@task)}>
            {task_privacy_label(@task)}
          </span>
        </div>

        <div class="mt-3 rounded-xl border border-base-content/12 bg-base-100/65 px-3 py-2.5">
          <p class="flex items-center gap-1.5 text-xs text-base-content/76">
            <.icon name="hero-calendar-days" class="size-3.5" /> Prazo: {task_due_label(@task.due_on)}
          </p>
          <p :if={total_items > 0} class="mt-1 text-xs font-medium text-info/80">
            Checklist: {checked_items}/{total_items} itens concluídos
          </p>
        </div>

        <div class="mt-4">
          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/65">Descrição</p>
          <div
            id="task-details-notes"
            class="mt-1 rounded-xl border border-base-content/12 bg-base-100/65 px-3 py-2.5"
          >
            <.task_notes_text
              :if={@task.notes && String.trim(@task.notes) != ""}
              notes={@task.notes}
              class="text-sm leading-6 text-base-content/80 break-words"
            />
            <p
              :if={!@task.notes || String.trim(@task.notes) == ""}
              class="text-sm text-base-content/60"
            >
              Sem descrição informada.
            </p>
          </div>
        </div>

        <div :if={checklist_items != []} class="mt-4">
          <p class="text-xs font-semibold uppercase tracking-wide text-base-content/65">Checklist</p>
          <ul class="mt-1 space-y-1.5 rounded-xl border border-base-content/12 bg-base-100/65 p-2.5">
            <li :for={item <- checklist_items} class="flex items-start gap-2">
              <.icon
                name={if(item.checked, do: "hero-check-circle", else: "hero-minus-circle")}
                class={task_checklist_state_icon_class(item.checked)}
              />
              <span class={[
                item.checked && "line-through text-base-content/45",
                "text-sm break-words"
              ]}>
                {item.label}
              </span>
            </li>
          </ul>
        </div>

        <div class="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <button
            id={"task-details-edit-btn-#{@task.id}"}
            type="button"
            phx-click="start_edit_task"
            phx-value-id={@task.id}
            class="btn btn-soft btn-sm border-base-content/18"
          >
            Editar tarefa
          </button>
          <button
            id="task-details-close-footer-btn"
            type="button"
            phx-click="close_task_details"
            class="btn btn-primary btn-sm"
          >
            Fechar
          </button>
        </div>
      </section>
    </div>
    """
  end

  attr :notes, :string, required: true
  attr :class, :string, default: nil
  attr :truncate, :boolean, default: false

  defp task_notes_text(assigns) do
    assigns = assign(assigns, :lines, notes_lines_with_links(assigns.notes))

    ~H"""
    <p class={[@class, @truncate && "line-clamp-2"]}>
      <span :for={{line, line_index} <- Enum.with_index(@lines)}>
        <span :for={segment <- line}>
          <a
            :if={segment.type == :link}
            href={segment.href}
            target="_blank"
            rel="noopener noreferrer"
            class="font-medium text-info/85 underline decoration-info/45 underline-offset-2 break-all hover:text-info"
          >
            {segment.text}
          </a>
          <span :if={segment.type == :text}>{segment.text}</span>
        </span>
        <br :if={line_index < length(@lines) - 1} />
      </span>
    </p>
    """
  end

  defp finance_balance_cents(ops_counts) do
    Map.get(ops_counts, :finances_income_cents, 0) -
      Map.get(ops_counts, :finances_expense_cents, 0)
  end

  defp task_checklist_items(task) do
    case Map.get(task, :checklist_items) do
      items when is_list(items) -> items
      _ -> []
    end
  end

  defp task_checklist_totals(task) do
    items = task_checklist_items(task)
    {Enum.count(items, & &1.checked), length(items)}
  end

  @notes_url_regex ~r/((?:https?:\/\/|www\.)[^\s<>"']+)/iu
  @url_with_scheme_regex ~r/^https?:\/\//i
  @url_trailing_punctuation_regex ~r/[.,!?;:]+$/u

  defp notes_lines_with_links(notes) when is_binary(notes) do
    notes
    |> String.split(~r/\R/u, trim: false)
    |> Enum.map(&line_segments_with_links/1)
  end

  defp notes_lines_with_links(_notes), do: []

  defp line_segments_with_links(line) do
    line
    |> then(&Regex.split(@notes_url_regex, &1, include_captures: true, trim: false))
    |> Enum.flat_map(&segment_to_note_parts/1)
  end

  defp segment_to_note_parts(""), do: []

  defp segment_to_note_parts(segment) do
    if Regex.match?(@notes_url_regex, segment) do
      {url, trailing_punctuation} = split_trailing_url_punctuation(segment)

      if url == "" do
        [%{type: :text, text: segment}]
      else
        url_part = [%{type: :link, text: url, href: normalize_note_url(url)}]

        if trailing_punctuation == "" do
          url_part
        else
          url_part ++ [%{type: :text, text: trailing_punctuation}]
        end
      end
    else
      [%{type: :text, text: segment}]
    end
  end

  defp split_trailing_url_punctuation(url) do
    trailing_punctuation =
      case Regex.run(@url_trailing_punctuation_regex, url) do
        [match] -> match
        _ -> ""
      end

    if trailing_punctuation == "" do
      {url, ""}
    else
      {String.trim_trailing(url, trailing_punctuation), trailing_punctuation}
    end
  end

  defp normalize_note_url(url) do
    normalized_url = String.trim(url)

    if Regex.match?(@url_with_scheme_regex, normalized_url) do
      normalized_url
    else
      "https://#{normalized_url}"
    end
  end

  defp task_due_label(nil), do: "sem prazo"
  defp task_due_label(%Date{} = due_on), do: Date.to_iso8601(due_on)
  defp task_due_label(_), do: "sem prazo"

  defp task_priority_label(:high), do: "Alta"
  defp task_priority_label(:low), do: "Baixa"
  defp task_priority_label(_), do: "Média"

  defp task_status_label(:in_progress), do: "Em andamento"
  defp task_status_label(:done), do: "Concluída"
  defp task_status_label(_), do: "A fazer"

  defp task_priority_badge_class(:high),
    do: "badge badge-sm border-error/40 bg-error/14 text-error-content"

  defp task_priority_badge_class(:low),
    do: "badge badge-sm border-success/40 bg-success/14 text-success-content"

  defp task_priority_badge_class(_),
    do: "badge badge-sm border-warning/40 bg-warning/14 text-warning-content"

  defp task_status_badge_class(:done),
    do: "badge badge-sm border-success/40 bg-success/14 text-success-content"

  defp task_status_badge_class(:in_progress),
    do: "badge badge-sm border-info/40 bg-info/14 text-info-content"

  defp task_status_badge_class(_),
    do: "badge badge-sm border-base-content/25 bg-base-100 text-base-content/80"

  defp task_status_border_class(:done), do: "border-success/25"
  defp task_status_border_class(:in_progress), do: "border-info/25"
  defp task_status_border_class(_), do: "border-base-content/15"

  defp task_checklist_state_icon_class(true), do: "mt-0.5 size-4 shrink-0 text-success"
  defp task_checklist_state_icon_class(false), do: "mt-0.5 size-4 shrink-0 text-base-content/40"

  defp task_linked_sync?(task) do
    Map.get(task, :shared_sync_mode) == :sync and is_integer(Map.get(task, :shared_with_link_id))
  end

  defp task_privacy_label(task) do
    if task_linked_sync?(task), do: "Vinculada", else: "Privada"
  end

  defp task_privacy_badge_class(task) do
    if task_linked_sync?(task) do
      "badge badge-sm border-success/35 bg-success/14 text-success-content"
    else
      "badge badge-sm border-base-content/24 bg-base-100 text-base-content/78"
    end
  end

  defp task_column_count(ops_counts, :todo), do: Map.get(ops_counts, :tasks_todo, 0)
  defp task_column_count(ops_counts, :in_progress), do: Map.get(ops_counts, :tasks_in_progress, 0)
  defp task_column_count(ops_counts, :done), do: Map.get(ops_counts, :tasks_done, 0)

  defp task_column_surface_class(:todo), do: "border-base-content/14 bg-base-100/45"
  defp task_column_surface_class(:in_progress), do: "border-info/20 bg-info/6"
  defp task_column_surface_class(:done), do: "border-success/22 bg-success/7"

  defp task_column_icon(:todo), do: "hero-inbox-stack"
  defp task_column_icon(:in_progress), do: "hero-play-circle"
  defp task_column_icon(:done), do: "hero-check-badge"

  defp task_column_count_badge_class(:todo),
    do: "badge badge-sm border-base-content/24 bg-base-100 text-base-content/80"

  defp task_column_count_badge_class(:in_progress),
    do: "badge badge-sm border-info/35 bg-info/14 text-info-content"

  defp task_column_count_badge_class(:done),
    do: "badge badge-sm border-success/35 bg-success/14 text-success-content"

  defp task_primary_action_status(:todo), do: "in_progress"
  defp task_primary_action_status(:in_progress), do: "done"
  defp task_primary_action_status(:done), do: "todo"

  defp task_primary_action_label(:todo), do: "Iniciar"
  defp task_primary_action_label(:in_progress), do: "Concluir"
  defp task_primary_action_label(:done), do: "Reabrir"

  defp task_primary_action_icon(:todo), do: "hero-play"
  defp task_primary_action_icon(:in_progress), do: "hero-check-circle"
  defp task_primary_action_icon(:done), do: "hero-arrow-uturn-left"

  defp task_primary_action_class(:todo),
    do:
      "btn btn-xs btn-soft border-info/30 text-info-content hover:border-info/50 hover:bg-info/18"

  defp task_primary_action_class(:in_progress),
    do:
      "btn btn-xs btn-soft border-success/32 text-success-content hover:border-success/55 hover:bg-success/18"

  defp task_primary_action_class(:done),
    do:
      "btn btn-xs btn-soft border-base-content/24 text-base-content/78 hover:border-base-content/45 hover:bg-base-content/8"

  defp task_share_link_options([], _current_user_id), do: []

  defp task_share_link_options(account_links, current_user_id) do
    Enum.map(account_links, fn link ->
      {task_share_link_label(link, current_user_id), to_string(link.id)}
    end)
  end

  defp task_share_link_label(link, current_user_id) do
    partner_email =
      cond do
        current_user_id == link.user_a_id and is_map(link.user_b) ->
          Map.get(link.user_b, :email, "conta vinculada")

        current_user_id == link.user_b_id and is_map(link.user_a) ->
          Map.get(link.user_a, :email, "conta vinculada")

        true ->
          "conta vinculada"
      end

    "Vínculo ##{link.id} • #{partner_email}"
  end

  defp task_share_link_name_by_id(account_links, current_user_id, link_id)
       when is_integer(link_id) do
    case Enum.find(account_links, &(&1.id == link_id)) do
      nil -> "Vínculo ##{link_id}"
      link -> task_share_link_label(link, current_user_id)
    end
  end

  defp task_share_link_name_by_id(_account_links, _current_user_id, _link_id), do: "Vínculo"

  defp task_focus_duration_presets, do: Enum.to_list(15..180//15)

  defp finance_row_border_class(:income), do: "border-success/25"
  defp finance_row_border_class(:expense), do: "border-error/25"
  defp finance_row_border_class(_), do: "border-base-content/15"

  defp finance_amount_class(:income), do: "text-sm font-semibold font-mono text-success"
  defp finance_amount_class(:expense), do: "text-sm font-semibold font-mono text-error"
  defp finance_amount_class(_), do: "text-sm font-semibold font-mono text-base-content"

  defp finance_kind_badge_class(:income),
    do: "badge badge-sm border-success/40 bg-success/14 text-success-content"

  defp finance_kind_badge_class(:expense),
    do: "badge badge-sm border-error/40 bg-error/14 text-error-content"

  defp finance_kind_badge_class(_),
    do: "badge badge-sm border-base-content/25 bg-base-100 text-base-content/80"

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

  defp finance_payment_label(:debit), do: "Débito"
  defp finance_payment_label(:credit), do: "Crédito"

  defp finance_payment_label(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.capitalize()

  defp finance_payment_label(_), do: "Pagamento"
end
