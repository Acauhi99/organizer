defmodule OrganizerWeb.DashboardLive.Components.OperationsPanel do
  use Phoenix.Component
  import OrganizerWeb.CoreComponents, only: [icon: 1]
  import OrganizerWeb.DashboardLive.Formatters

  attr :streams, :map, required: true
  attr :ops_tab, :string, required: true
  attr :task_filters, :map, required: true
  attr :finance_filters, :map, required: true
  attr :editing_task_id, :any, default: nil
  attr :editing_finance_id, :any, default: nil
  attr :ops_counts, :map, required: true

  def operations_panel(assigns) do
    ~H"""
    <section
      id="operations-panel"
      class="surface-card order-6 rounded-2xl p-4 scroll-mt-20"
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

      <div id="operations-panel-content">
        <div class="mt-3 grid gap-2 md:grid-cols-4">
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
            <form
              id="task-filters"
              phx-change="filter_tasks"
              phx-debounce="500"
              class="mt-3 grid gap-2 sm:grid-cols-4"
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

            <div id="tasks" phx-update="stream" class="mt-3 space-y-2">
              <div id="tasks-empty-wrapper" class="hidden only:block">
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

              <article
                :for={{id, task} <- @streams.tasks}
                id={id}
                class={[
                  "micro-surface rounded-xl border p-3",
                  task_status_border_class(task.status)
                ]}
              >
                <% checklist_items = task_checklist_items(task) %>
                <% {checked_items, total_items} = task_checklist_totals(task) %>

                <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                  <div class="min-w-0 flex-1">
                    <p class="truncate text-sm font-semibold text-base-content">{task.title}</p>
                    <p class="mt-1 text-xs text-base-content/65">
                      Prazo: {task_due_label(task.due_on)}
                    </p>
                    <p :if={total_items > 0} class="mt-1 text-xs font-medium text-info/80">
                      Checklist: {checked_items}/{total_items} itens concluídos
                    </p>
                    <p
                      :if={task.notes && String.trim(task.notes) != ""}
                      class="mt-2 line-clamp-2 text-xs text-base-content/72"
                    >
                      {task.notes}
                    </p>
                  </div>

                  <div class="flex shrink-0 flex-wrap gap-1.5">
                    <span class={task_priority_badge_class(task.priority)}>
                      {task_priority_label(task.priority)}
                    </span>
                    <span class={task_status_badge_class(task.status)}>
                      {task_status_label(task.status)}
                    </span>
                  </div>
                </div>

                <div :if={checklist_items != []} class="mt-3 space-y-2">
                  <form
                    :for={item <- checklist_items}
                    id={"task-checklist-item-form-#{task.id}-#{item.id}"}
                    phx-submit="save_task_checklist_item_label"
                    class="flex items-center gap-2 rounded-lg border border-base-content/16 bg-base-100/55 px-2.5 py-2"
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
                  class="mt-3 flex items-center gap-2 rounded-lg bg-base-100/30 p-2"
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

                <div class="mt-3 flex gap-2">
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
                  <div class="flex gap-2">
                    <button type="submit" class="btn btn-primary btn-sm">Salvar</button>
                    <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit_task">
                      Cancelar
                    </button>
                  </div>
                </form>
              </article>
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
              class="mt-3 grid gap-2 sm:grid-cols-4 lg:grid-cols-6"
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
                <div class="flex items-start justify-between gap-3">
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

                <div class="mt-3 flex gap-2">
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
                  <div class="flex gap-2">
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
        </div>
      </div>
    </section>
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
