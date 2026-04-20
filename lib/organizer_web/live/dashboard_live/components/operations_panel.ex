defmodule OrganizerWeb.DashboardLive.Components.OperationsPanel do
  use Phoenix.Component
  import OrganizerWeb.DashboardLive.Formatters

  attr :streams, :map, required: true
  attr :ops_tab, :string, required: true
  attr :task_filters, :map, required: true
  attr :finance_filters, :map, required: true
  attr :goal_filters, :map, required: true
  attr :editing_task_id, :any, default: nil
  attr :editing_finance_id, :any, default: nil
  attr :editing_goal_id, :any, default: nil
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
          <button
            id="ops-tab-goals"
            type="button"
            phx-click="set_ops_tab"
            phx-value-tab="goals"
            class={[
              "btn btn-sm ds-pill-btn",
              @ops_tab == "goals" && "btn-primary",
              @ops_tab != "goals" && "btn-soft"
            ]}
          >
            Metas
          </button>
        </div>
      </div>

      <%!-- Panel content --%>
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
          </article>
          <article
            id="ops-card-goals-active"
            class="micro-surface rounded-lg p-3"
            aria-label={"Metas ativas nos próximos #{@goal_filters.days} dias"}
          >
            <div class="flex items-center justify-between">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Metas ativas</p>
              <span class="text-xs text-base-content/65">{@goal_filters.days}d</span>
            </div>
            <p class="mt-1 text-lg font-semibold text-base-content">
              {@ops_counts.goals_active}/{@ops_counts.goals_total}
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
                    Use os formulários da plataforma para começar a registrar suas tarefas.
                  </p>
                </div>
              </div>
              <article
                :for={{id, task} <- @streams.tasks}
                id={id}
                class="micro-surface rounded-lg p-3"
              >
                <p class="font-medium text-base-content">{task.title}</p>
                <p class="text-xs text-base-content/65">
                  {to_string(task.priority)} • {if task.due_on,
                    do: Date.to_iso8601(task.due_on),
                    else: "sem data"}
                </p>
                <div class="mt-2 flex gap-2">
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
                  <label
                    class="text-xs font-medium text-base-content/70"
                    for={"task-due-#{task.id}"}
                  >
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
                    <button
                      type="button"
                      class="btn btn-ghost btn-sm"
                      phx-click="cancel_edit_task"
                    >
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
                <option value="expense" selected={@finance_filters.kind == "expense"}>
                  Despesa
                </option>
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
                class="micro-surface rounded-lg p-3"
              >
                <p class="font-medium text-base-content">{entry.category}</p>
                <p class="text-xs text-base-content/65">
                  {finance_entry_meta_line(entry)}
                </p>
                <div class="mt-2 flex gap-2">
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

          <section class={[
            "rounded-xl border border-base-content/12 bg-base-100/35 p-4",
            @ops_tab != "goals" && "hidden"
          ]}>
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Metas
            </h2>
            <form
              id="goal-filters"
              phx-change="filter_goals"
              phx-debounce="500"
              class="mt-3 grid gap-2 sm:grid-cols-4 lg:grid-cols-6"
              aria-label="Filtros de metas"
            >
              <select name="filters[status]" class="select select-bordered select-sm">
                <option value="all" selected={@goal_filters.status == "all"}>Todos status</option>
                <option value="active" selected={@goal_filters.status == "active"}>Ativa</option>
                <option value="paused" selected={@goal_filters.status == "paused"}>Pausada</option>
                <option value="done" selected={@goal_filters.status == "done"}>Concluída</option>
              </select>
              <select name="filters[horizon]" class="select select-bordered select-sm">
                <option value="all" selected={@goal_filters.horizon == "all"}>
                  Todos horizontes
                </option>
                <option value="short" selected={@goal_filters.horizon == "short"}>
                  Curto prazo
                </option>
                <option value="medium" selected={@goal_filters.horizon == "medium"}>
                  Médio prazo
                </option>
                <option value="long" selected={@goal_filters.horizon == "long"}>Longo prazo</option>
              </select>
              <input
                type="number"
                name="filters[days]"
                value={@goal_filters.days}
                placeholder="Próximos dias..."
                class="input input-bordered input-sm"
                min="1"
                max="3650"
              />
              <input
                type="number"
                name="filters[progress_min]"
                value={@goal_filters.progress_min}
                placeholder="Progresso mín %..."
                class="input input-bordered input-sm"
                min="0"
                max="100"
              />
              <input
                type="number"
                name="filters[progress_max]"
                value={@goal_filters.progress_max}
                placeholder="Progresso máx %..."
                class="input input-bordered input-sm"
                min="0"
                max="100"
              />
              <input
                type="text"
                name="filters[q]"
                value={@goal_filters.q}
                placeholder="Buscar por título ou descrição..."
                class="input input-bordered input-sm"
                maxlength="100"
              />
            </form>
            <div id="goals" phx-update="stream" class="mt-3 space-y-2">
              <div id="goals-empty-wrapper" class="hidden only:block">
                <div
                  id="empty-state-goals"
                  class="rounded-xl border border-dashed border-base-content/25 px-4 py-6 text-center"
                >
                  <p class="text-sm font-semibold text-base-content/85">Nenhuma meta cadastrada</p>
                  <p class="mt-1 text-xs leading-5 text-base-content/65">
                    Cadastre metas pelo painel para acompanhar evolução e próximos prazos.
                  </p>
                </div>
              </div>
              <article
                :for={{id, goal} <- @streams.goals}
                id={id}
                class="micro-surface rounded-lg p-3"
              >
                <p class="font-medium text-base-content">{goal.title}</p>
                <p class="text-xs text-base-content/65">
                  {to_string(goal.horizon)} • {to_string(goal.status)}
                </p>
                <div class="mt-2 flex gap-2">
                  <button
                    id={"goal-edit-btn-#{goal.id}"}
                    type="button"
                    phx-click="start_edit_goal"
                    phx-value-id={goal.id}
                    class="ds-inline-btn rounded-md px-2 py-1 text-xs"
                  >
                    Editar
                  </button>
                  <button
                    id={"goal-delete-btn-#{goal.id}"}
                    type="button"
                    phx-click="delete_goal"
                    phx-value-id={goal.id}
                    class="ds-inline-btn ds-inline-btn-danger rounded-md px-2 py-1 text-xs"
                  >
                    Excluir
                  </button>
                </div>

                <form
                  :if={editing?(@editing_goal_id, goal.id)}
                  id={"goal-edit-form-#{goal.id}"}
                  phx-submit="save_goal"
                  class="border border-base-content/16 bg-base-100/80 mt-3 space-y-2 rounded-md p-3"
                >
                  <input type="hidden" name="_id" value={goal.id} />
                  <label
                    class="text-xs font-medium text-base-content/70"
                    for={"goal-title-#{goal.id}"}
                  >
                    Título
                  </label>
                  <input
                    id={"goal-title-#{goal.id}"}
                    name="goal[title]"
                    type="text"
                    required
                    value={goal.title}
                    class="input input-bordered w-full"
                  />
                  <div class="grid gap-2 sm:grid-cols-2">
                    <div>
                      <label
                        class="text-xs font-medium text-base-content/70"
                        for={"goal-horizon-#{goal.id}"}
                      >
                        Horizonte
                      </label>
                      <select
                        id={"goal-horizon-#{goal.id}"}
                        name="goal[horizon]"
                        class="select select-bordered w-full"
                      >
                        <option value="short" selected={goal.horizon == :short}>Curto</option>
                        <option value="medium" selected={goal.horizon == :medium}>Médio</option>
                        <option value="long" selected={goal.horizon == :long}>Longo</option>
                      </select>
                    </div>
                    <div>
                      <label
                        class="text-xs font-medium text-base-content/70"
                        for={"goal-status-#{goal.id}"}
                      >
                        Status
                      </label>
                      <select
                        id={"goal-status-#{goal.id}"}
                        name="goal[status]"
                        class="select select-bordered w-full"
                      >
                        <option value="active" selected={goal.status == :active}>Ativa</option>
                        <option value="paused" selected={goal.status == :paused}>Pausada</option>
                        <option value="done" selected={goal.status == :done}>Concluída</option>
                      </select>
                    </div>
                  </div>
                  <div class="grid gap-2 sm:grid-cols-2">
                    <div>
                      <label
                        class="text-xs font-medium text-base-content/70"
                        for={"goal-target-#{goal.id}"}
                      >
                        Alvo
                      </label>
                      <input
                        id={"goal-target-#{goal.id}"}
                        name="goal[target_value]"
                        type="number"
                        value={goal.target_value || ""}
                        class="input input-bordered w-full"
                      />
                    </div>
                    <div>
                      <label
                        class="text-xs font-medium text-base-content/70"
                        for={"goal-current-#{goal.id}"}
                      >
                        Atual
                      </label>
                      <input
                        id={"goal-current-#{goal.id}"}
                        name="goal[current_value]"
                        type="number"
                        value={goal.current_value || 0}
                        class="input input-bordered w-full"
                      />
                    </div>
                  </div>
                  <label
                    class="text-xs font-medium text-base-content/70"
                    for={"goal-date-#{goal.id}"}
                  >
                    Data
                  </label>
                  <input
                    id={"goal-date-#{goal.id}"}
                    name="goal[due_on]"
                    type="date"
                    value={date_input_value(goal.due_on)}
                    class="input input-bordered w-full"
                  />
                  <label
                    class="text-xs font-medium text-base-content/70"
                    for={"goal-notes-#{goal.id}"}
                  >
                    Notas
                  </label>
                  <input
                    id={"goal-notes-#{goal.id}"}
                    name="goal[notes]"
                    type="text"
                    value={goal.notes || ""}
                    class="input input-bordered w-full"
                  />
                  <div class="flex gap-2">
                    <button type="submit" class="btn btn-primary btn-sm">Salvar</button>
                    <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit_goal">
                      Cancelar
                    </button>
                  </div>
                </form>
              </article>
            </div>
          </section>
        </div>
        <%!-- End of space-y-4 tabs container --%>
      </div>
      <%!-- End of panel content --%>
    </section>
    """
  end
end
