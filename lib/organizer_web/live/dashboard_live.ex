defmodule OrganizerWeb.DashboardLive do
  use OrganizerWeb, :live_view

  alias Organizer.Accounts
  alias Organizer.Accounts.Scope
  alias Organizer.Planning

  @impl true
  def mount(_params, session, socket) do
    with token when is_binary(token) <- session["user_token"],
         {user, _inserted_at} <- Accounts.get_user_by_session_token(token) do
      scope = Scope.for_user(user)
      {:ok, hydrate_dashboard(socket, scope)}
    else
      _ -> {:ok, redirect(socket, to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("add_task", %{"task" => attrs}, socket) do
    case Planning.create_task(socket.assigns.current_scope, attrs) do
      {:ok, task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tarefa adicionada.")
         |> stream_insert(:tasks, task, at: 0)
         |> assign(:task_form, to_form(%{}, as: :task))
         |> refresh_snapshots()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Verifique os campos da tarefa.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel salvar a tarefa.")}
    end
  end

  @impl true
  def handle_event("add_finance", %{"finance" => attrs}, socket) do
    case Planning.create_finance_entry(socket.assigns.current_scope, attrs) do
      {:ok, entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Lancamento financeiro adicionado.")
         |> stream_insert(:finances, entry, at: 0)
         |> assign(:finance_form, to_form(%{}, as: :finance))
         |> refresh_snapshots()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Verifique os campos do lancamento.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel salvar o lancamento.")}
    end
  end

  @impl true
  def handle_event("add_goal", %{"goal" => attrs}, socket) do
    case Planning.create_goal(socket.assigns.current_scope, attrs) do
      {:ok, goal} ->
        {:noreply,
         socket
         |> put_flash(:info, "Meta adicionada.")
         |> stream_insert(:goals, goal, at: 0)
         |> assign(:goal_form, to_form(%{}, as: :goal))
         |> refresh_snapshots()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Verifique os campos da meta.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Nao foi possivel salvar a meta.")}
    end
  end

  defp hydrate_dashboard(socket, scope) do
    {:ok, tasks} = Planning.list_tasks(scope, %{days: 14})
    {:ok, finances} = Planning.list_finance_entries(scope, %{days: 30})
    {:ok, goals} = Planning.list_goals(scope)

    socket
    |> assign(:current_scope, scope)
    |> assign(:task_form, to_form(%{}, as: :task))
    |> assign(:finance_form, to_form(%{}, as: :finance))
    |> assign(:goal_form, to_form(%{}, as: :goal))
    |> stream(:tasks, tasks, reset: true)
    |> stream(:finances, finances, reset: true)
    |> stream(:goals, goals, reset: true)
    |> refresh_snapshots()
  end

  defp refresh_snapshots(socket) do
    {:ok, burndown} = Planning.burndown_snapshot(socket.assigns.current_scope)
    {:ok, finance_summary} = Planning.finance_summary(socket.assigns.current_scope, 30)

    socket
    |> assign(:burndown, burndown)
    |> assign(:finance_summary, finance_summary)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="space-y-6">
        <header class="rounded-3xl border border-base-300 bg-gradient-to-r from-sky-50 to-emerald-50 p-6 shadow-sm">
          <h1 class="text-2xl font-bold tracking-tight text-slate-900">Painel Diario</h1>
          <p class="mt-1 text-sm text-slate-600">
            Organize tarefas, financeiro e metas sem trocar de tela.
          </p>
          <div class="mt-4 grid gap-3 sm:grid-cols-3">
            <article class="rounded-xl border border-slate-200 bg-white p-3">
              <p class="text-xs uppercase tracking-wide text-slate-500">Burndown</p>
              <p class="mt-1 text-xl font-semibold text-slate-900">
                {@burndown.completed}/{@burndown.total}
              </p>
              <p class="text-xs text-slate-500">Concluidas nos proximos 14 dias</p>
            </article>
            <article class="rounded-xl border border-slate-200 bg-white p-3">
              <p class="text-xs uppercase tracking-wide text-slate-500">Receitas (30d)</p>
              <p class="mt-1 text-xl font-semibold text-emerald-700">
                {format_money(@finance_summary.income_cents)}
              </p>
            </article>
            <article class="rounded-xl border border-slate-200 bg-white p-3">
              <p class="text-xs uppercase tracking-wide text-slate-500">Saldo (30d)</p>
              <p class="mt-1 text-xl font-semibold text-sky-700">
                {format_money(@finance_summary.balance_cents)}
              </p>
            </article>
          </div>
        </header>

        <div class="grid gap-6 lg:grid-cols-3">
          <section class="rounded-2xl border border-base-300 bg-white p-4 shadow-sm">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-600">
              Quick Add Tarefa
            </h2>
            <.form for={@task_form} id="task-form" phx-submit="add_task" class="mt-3 space-y-2">
              <.input field={@task_form[:title]} type="text" label="Titulo" required />
              <.input field={@task_form[:due_on]} type="date" label="Data" />
              <.input
                field={@task_form[:priority]}
                type="select"
                label="Prioridade"
                options={[{"Baixa", "low"}, {"Media", "medium"}, {"Alta", "high"}]}
              />
              <.button class="w-full">Adicionar tarefa</.button>
            </.form>
          </section>

          <section class="rounded-2xl border border-base-300 bg-white p-4 shadow-sm">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-600">
              Quick Add Financeiro
            </h2>
            <.form
              for={@finance_form}
              id="finance-form"
              phx-submit="add_finance"
              class="mt-3 space-y-2"
            >
              <.input
                field={@finance_form[:kind]}
                type="select"
                label="Tipo"
                options={[{"Receita", "income"}, {"Despesa", "expense"}]}
              />
              <.input
                field={@finance_form[:amount_cents]}
                type="number"
                label="Valor (centavos)"
                required
              />
              <.input field={@finance_form[:category]} type="text" label="Categoria" required />
              <.input field={@finance_form[:occurred_on]} type="date" label="Data" />
              <.button class="w-full">Adicionar lancamento</.button>
            </.form>
          </section>

          <section class="rounded-2xl border border-base-300 bg-white p-4 shadow-sm">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-600">
              Quick Add Meta
            </h2>
            <.form for={@goal_form} id="goal-form" phx-submit="add_goal" class="mt-3 space-y-2">
              <.input field={@goal_form[:title]} type="text" label="Meta" required />
              <.input
                field={@goal_form[:horizon]}
                type="select"
                label="Horizonte"
                options={[{"Curto", "short"}, {"Medio", "medium"}, {"Longo", "long"}]}
                required
              />
              <.input field={@goal_form[:target_value]} type="number" label="Alvo" />
              <.button class="w-full">Adicionar meta</.button>
            </.form>
          </section>
        </div>

        <div class="grid gap-6 lg:grid-cols-2">
          <section class="rounded-2xl border border-base-300 bg-white p-4 shadow-sm">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-600">
              Proximas tarefas
            </h2>
            <div id="tasks" phx-update="stream" class="mt-3 space-y-2">
              <div class="hidden only:block rounded-lg border border-dashed border-slate-300 p-4 text-sm text-slate-500">
                Nenhuma tarefa cadastrada.
              </div>
              <article
                :for={{id, task} <- @streams.tasks}
                id={id}
                class="rounded-lg border border-slate-200 p-3"
              >
                <p class="font-medium text-slate-800">{task.title}</p>
                <p class="text-xs text-slate-500">
                  {to_string(task.priority)} • {if task.due_on,
                    do: Date.to_iso8601(task.due_on),
                    else: "sem data"}
                </p>
              </article>
            </div>
          </section>

          <section class="rounded-2xl border border-base-300 bg-white p-4 shadow-sm">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-600">
              Metas em andamento
            </h2>
            <div id="goals" phx-update="stream" class="mt-3 space-y-2">
              <div class="hidden only:block rounded-lg border border-dashed border-slate-300 p-4 text-sm text-slate-500">
                Nenhuma meta cadastrada.
              </div>
              <article
                :for={{id, goal} <- @streams.goals}
                id={id}
                class="rounded-lg border border-slate-200 p-3"
              >
                <p class="font-medium text-slate-800">{goal.title}</p>
                <p class="text-xs text-slate-500">
                  {to_string(goal.horizon)} • {to_string(goal.status)}
                </p>
              </article>
            </div>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp format_money(cents) when is_integer(cents) do
    value = cents / 100
    :erlang.float_to_binary(value, decimals: 2)
  end
end
