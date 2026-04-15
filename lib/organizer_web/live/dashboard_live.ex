defmodule OrganizerWeb.DashboardLive do
  use OrganizerWeb, :live_view

  alias Organizer.Accounts
  alias Organizer.Accounts.Scope
  alias Organizer.Planning

  @task_status_filters ["all", "todo", "in_progress", "done"]
  @task_priority_filters ["all", "low", "medium", "high"]
  @task_days_filters ["7", "14", "30"]
  @finance_days_filters ["7", "30", "90"]
  @goal_status_filters ["all", "active", "paused", "done"]
  @analytics_days_filters ["30", "90", "365"]
  @analytics_capacity_filters ["5", "10", "15", "20", "30"]
  @finance_category_presets ["moradia", "alimentacao", "transporte", "saude", "lazer", "investimentos"]

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
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tarefa adicionada.")
         |> assign(:task_form, to_form(%{}, as: :task))
         |> reload_dashboard_lists()
         |> refresh_snapshots()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Verifique os campos da tarefa.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível salvar a tarefa.")}
    end
  end

  @impl true
  def handle_event("add_finance", %{"finance" => attrs}, socket) do
    case Planning.create_finance_entry(socket.assigns.current_scope, attrs) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Lançamento financeiro adicionado.")
         |> assign(:finance_form, to_form(%{}, as: :finance))
         |> reload_dashboard_lists()
         |> refresh_snapshots()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Verifique os campos do lançamento.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível salvar o lançamento.")}
    end
  end

  @impl true
  def handle_event("add_goal", %{"goal" => attrs}, socket) do
    case Planning.create_goal(socket.assigns.current_scope, attrs) do
      {:ok, _goal} ->
        {:noreply,
         socket
         |> put_flash(:info, "Meta adicionada.")
         |> assign(:goal_form, to_form(%{}, as: :goal))
         |> reload_dashboard_lists()
         |> refresh_snapshots()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Verifique os campos da meta.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível salvar a meta.")}
    end
  end

  @impl true
  def handle_event("filter_tasks", %{"filters" => filters}, socket) do
    task_filters =
      socket.assigns.task_filters
      |> Map.merge(normalize_task_filters(filters))
      |> sanitize_task_filters()

    {:noreply,
     socket
     |> assign(:task_filters, task_filters)
     |> reload_dashboard_lists()}
  end

  @impl true
  def handle_event("filter_finances", %{"filters" => filters}, socket) do
    finance_filters =
      socket.assigns.finance_filters
      |> Map.merge(normalize_finance_filters(filters))
      |> sanitize_finance_filters()

    {:noreply,
     socket
     |> assign(:finance_filters, finance_filters)
     |> reload_dashboard_lists()}
  end

  @impl true
  def handle_event("filter_goals", %{"filters" => filters}, socket) do
    goal_filters =
      socket.assigns.goal_filters
      |> Map.merge(normalize_goal_filters(filters))
      |> sanitize_goal_filters()

    {:noreply,
     socket
     |> assign(:goal_filters, goal_filters)
     |> reload_dashboard_lists()}
  end

  @impl true
  def handle_event("filter_analytics", %{"filters" => filters}, socket) do
    analytics_filters =
      socket.assigns.analytics_filters
      |> Map.merge(normalize_analytics_filters(filters))
      |> sanitize_analytics_filters()

    {:noreply,
     socket
     |> assign(:analytics_filters, analytics_filters)
     |> refresh_snapshots()}
  end

  @impl true
  def handle_event("use_finance_category_preset", %{"category" => category}, socket) do
    if category in @finance_category_presets do
      {:noreply,
       socket
       |> assign(:finance_form, to_form(%{"category" => category}, as: :finance))
       |> put_flash(:info, "Categoria pronta para cadastro rápido.")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("start_edit_task", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:editing_task_id, id)
     |> reload_dashboard_lists()}
  end

  @impl true
  def handle_event("cancel_edit_task", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_task_id, nil)
     |> reload_dashboard_lists()}
  end

  @impl true
  def handle_event("save_task", %{"_id" => id, "task" => attrs}, socket) do
    case Planning.update_task(socket.assigns.current_scope, id, attrs) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tarefa atualizada.")
         |> assign(:editing_task_id, nil)
         |> reload_dashboard_lists()
         |> refresh_snapshots()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Verifique os campos da tarefa.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Tarefa não encontrada.")
         |> assign(:editing_task_id, nil)}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível atualizar a tarefa.")}
    end
  end

  @impl true
  def handle_event("delete_task", %{"id" => id}, socket) do
    case Planning.delete_task(socket.assigns.current_scope, id) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tarefa removida.")
         |> assign(:editing_task_id, nil)
         |> reload_dashboard_lists()
         |> refresh_snapshots()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Tarefa não encontrada.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível remover a tarefa.")}
    end
  end

  @impl true
  def handle_event("start_edit_finance", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:editing_finance_id, id)
     |> reload_dashboard_lists()}
  end

  @impl true
  def handle_event("cancel_edit_finance", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_finance_id, nil)
     |> reload_dashboard_lists()}
  end

  @impl true
  def handle_event("save_finance", %{"_id" => id, "finance" => attrs}, socket) do
    case Planning.update_finance_entry(socket.assigns.current_scope, id, attrs) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Lançamento atualizado.")
         |> assign(:editing_finance_id, nil)
         |> reload_dashboard_lists()
         |> refresh_snapshots()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Verifique os campos do lançamento.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Lançamento não encontrado.")
         |> assign(:editing_finance_id, nil)}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível atualizar o lançamento.")}
    end
  end

  @impl true
  def handle_event("delete_finance", %{"id" => id}, socket) do
    case Planning.delete_finance_entry(socket.assigns.current_scope, id) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Lançamento removido.")
         |> assign(:editing_finance_id, nil)
         |> reload_dashboard_lists()
         |> refresh_snapshots()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Lançamento não encontrado.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível remover o lançamento.")}
    end
  end

  @impl true
  def handle_event("start_edit_goal", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:editing_goal_id, id)
     |> reload_dashboard_lists()}
  end

  @impl true
  def handle_event("cancel_edit_goal", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_goal_id, nil)
     |> reload_dashboard_lists()}
  end

  @impl true
  def handle_event("save_goal", %{"_id" => id, "goal" => attrs}, socket) do
    case Planning.update_goal(socket.assigns.current_scope, id, attrs) do
      {:ok, _goal} ->
        {:noreply,
         socket
         |> put_flash(:info, "Meta atualizada.")
         |> assign(:editing_goal_id, nil)
         |> reload_dashboard_lists()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Verifique os campos da meta.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Meta não encontrada.")
         |> assign(:editing_goal_id, nil)}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível atualizar a meta.")}
    end
  end

  @impl true
  def handle_event("delete_goal", %{"id" => id}, socket) do
    case Planning.delete_goal(socket.assigns.current_scope, id) do
      {:ok, _goal} ->
        {:noreply,
         socket
         |> put_flash(:info, "Meta removida.")
         |> assign(:editing_goal_id, nil)
         |> reload_dashboard_lists()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Meta não encontrada.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível remover a meta.")}
    end
  end

  defp hydrate_dashboard(socket, scope) do
    socket
    |> assign(:current_scope, scope)
    |> assign(:task_form, to_form(%{}, as: :task))
    |> assign(:finance_form, to_form(%{}, as: :finance))
    |> assign(:goal_form, to_form(%{}, as: :goal))
    |> assign(:finance_category_presets, @finance_category_presets)
    |> assign(:task_filters, default_task_filters())
    |> assign(:finance_filters, default_finance_filters())
    |> assign(:goal_filters, default_goal_filters())
    |> assign(:analytics_filters, default_analytics_filters())
    |> assign(:editing_task_id, nil)
    |> assign(:editing_finance_id, nil)
    |> assign(:editing_goal_id, nil)
    |> reload_dashboard_lists()
    |> refresh_snapshots()
  end

  defp reload_dashboard_lists(socket) do
    {:ok, tasks} = Planning.list_tasks(socket.assigns.current_scope, socket.assigns.task_filters)

    {:ok, finances} =
      Planning.list_finance_entries(socket.assigns.current_scope, socket.assigns.finance_filters)

    {:ok, goals} = Planning.list_goals(socket.assigns.current_scope, socket.assigns.goal_filters)

    socket
    |> stream(:tasks, tasks, reset: true)
    |> stream(:finances, finances, reset: true)
    |> stream(:goals, goals, reset: true)
    |> assign(:onboarding_counts, %{
      goals: length(goals),
      finance_categories: count_unique_finance_categories(finances)
    })
  end

  defp refresh_snapshots(socket) do
    {:ok, workload_capacity_snapshot} =
      Planning.burndown_snapshot(socket.assigns.current_scope, %{
        planned_capacity: socket.assigns.analytics_filters.planned_capacity
      })

    {:ok, insights_overview} =
      Planning.analytics_overview(socket.assigns.current_scope, %{
        days: socket.assigns.analytics_filters.days,
        planned_capacity: socket.assigns.analytics_filters.planned_capacity
      })

    {:ok, finance_summary} = Planning.finance_summary(socket.assigns.current_scope, 30)

    socket
    |> assign(:workload_capacity_snapshot, workload_capacity_snapshot)
    |> assign(:insights_overview, insights_overview)
    |> assign(:finance_summary, finance_summary)
  end

  defp default_task_filters do
    %{status: "all", priority: "all", days: "14"}
  end

  defp default_finance_filters do
    %{days: "30"}
  end

  defp default_goal_filters do
    %{status: "all"}
  end

  defp default_analytics_filters do
    %{days: "365", planned_capacity: "10"}
  end

  defp normalize_task_filters(filters) when is_map(filters) do
    %{
      status: Map.get(filters, "status"),
      priority: Map.get(filters, "priority"),
      days: Map.get(filters, "days")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp normalize_finance_filters(filters) when is_map(filters) do
    %{
      days: Map.get(filters, "days")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp normalize_goal_filters(filters) when is_map(filters) do
    %{
      status: Map.get(filters, "status")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp normalize_analytics_filters(filters) when is_map(filters) do
    %{
      days: Map.get(filters, "days"),
      planned_capacity: Map.get(filters, "planned_capacity")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp sanitize_task_filters(filters) do
    filters
    |> Map.update(:status, "all", fn value ->
      if value in @task_status_filters, do: value, else: "all"
    end)
    |> Map.update(:priority, "all", fn value ->
      if value in @task_priority_filters, do: value, else: "all"
    end)
    |> Map.update(:days, "14", fn value ->
      if value in @task_days_filters, do: value, else: "14"
    end)
  end

  defp sanitize_finance_filters(filters) do
    Map.update(filters, :days, "30", fn value ->
      if value in @finance_days_filters, do: value, else: "30"
    end)
  end

  defp sanitize_goal_filters(filters) do
    Map.update(filters, :status, "all", fn value ->
      if value in @goal_status_filters, do: value, else: "all"
    end)
  end

  defp sanitize_analytics_filters(filters) do
    filters
    |> Map.update(:days, "365", fn value ->
      if value in @analytics_days_filters, do: value, else: "365"
    end)
    |> Map.update(:planned_capacity, "10", fn value ->
      if value in @analytics_capacity_filters, do: value, else: "10"
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide={true}>
      <section class="dashboard-shell space-y-6">
        <header class="brand-hero-card rounded-3xl p-6">
          <h1 class="text-2xl font-bold tracking-tight text-base-content">Painel Diário</h1>
          <p class="mt-1 text-sm text-base-content/80">
            Organize tarefas, financeiro e metas sem trocar de tela.
          </p>
          <div class="mt-4 grid gap-3 sm:grid-cols-3">
            <article class="micro-surface rounded-xl p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Burndown</p>
              <p class="mt-1 text-xl font-semibold text-base-content">
                {@workload_capacity_snapshot.completed}/{@workload_capacity_snapshot.total}
              </p>
              <p class="text-xs text-base-content/65">Concluídas nos próximos 14 dias</p>
            </article>
            <article class="micro-surface rounded-xl p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Receitas (30d)</p>
              <p class="mt-1 text-xl font-semibold text-emerald-300">
                {format_money(@finance_summary.income_cents)}
              </p>
            </article>
            <article class="micro-surface rounded-xl p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Saldo (30d)</p>
              <p class="mt-1 text-xl font-semibold text-cyan-300">
                {format_money(@finance_summary.balance_cents)}
              </p>
            </article>
          </div>
        </header>

        <nav
          class="surface-card rounded-2xl p-2 lg:hidden"
          aria-label="Atalhos rápidos do dashboard"
        >
          <div class="flex gap-2 overflow-x-auto pb-1">
            <a href="#quick-task" class="btn btn-sm btn-ghost whitespace-nowrap">Nova tarefa</a>
            <a href="#quick-finance" class="btn btn-sm btn-ghost whitespace-nowrap">Novo lançamento</a>
            <a href="#quick-goal" class="btn btn-sm btn-ghost whitespace-nowrap">Nova meta</a>
            <a href="#analytics-panel" class="btn btn-sm btn-ghost whitespace-nowrap">Analítico</a>
          </div>
        </nav>

        <section
          id="analytics-panel"
          class="surface-card rounded-2xl p-4 scroll-mt-20"
        >
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">Visão analítica</h2>
              <p class="text-xs text-base-content/65">Comparativo de execução e risco de sobrecarga.</p>
            </div>
            <form
              id="analytics-filters"
              phx-change="filter_analytics"
              class="grid gap-2 sm:grid-cols-2"
              aria-label="Filtros analíticos"
            >
              <select name="filters[days]" class="select select-bordered select-sm">
                <option value="30" selected={@analytics_filters.days == "30"}>30 dias</option>
                <option value="90" selected={@analytics_filters.days == "90"}>90 dias</option>
                <option value="365" selected={@analytics_filters.days == "365"}>365 dias</option>
              </select>
              <select name="filters[planned_capacity]" class="select select-bordered select-sm">
                <option value="5" selected={@analytics_filters.planned_capacity == "5"}>Cap. 5</option>
                <option value="10" selected={@analytics_filters.planned_capacity == "10"}>Cap. 10</option>
                <option value="15" selected={@analytics_filters.planned_capacity == "15"}>Cap. 15</option>
                <option value="20" selected={@analytics_filters.planned_capacity == "20"}>Cap. 20</option>
                <option value="30" selected={@analytics_filters.planned_capacity == "30"}>Cap. 30</option>
              </select>
            </form>
          </div>

          <div class="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-5">
            <article class="micro-surface rounded-xl p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Semanal</p>
              <p class="mt-1 text-lg font-semibold text-base-content">
                {@insights_overview.progress_by_period.weekly.executed}/{@insights_overview.progress_by_period.weekly.planned}
              </p>
              <p class="text-xs text-base-content/65">
                {format_percent(@insights_overview.progress_by_period.weekly.completion_rate)}% de conclusão
              </p>
            </article>

            <article class="micro-surface rounded-xl p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Mensal</p>
              <p class="mt-1 text-lg font-semibold text-base-content">
                {@insights_overview.progress_by_period.monthly.executed}/{@insights_overview.progress_by_period.monthly.planned}
              </p>
              <p class="text-xs text-base-content/65">
                {format_percent(@insights_overview.progress_by_period.monthly.completion_rate)}% de conclusão
              </p>
            </article>

            <article class="micro-surface rounded-xl p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Anual</p>
              <p class="mt-1 text-lg font-semibold text-base-content">
                {@insights_overview.progress_by_period.annual.executed}/{@insights_overview.progress_by_period.annual.planned}
              </p>
              <p class="text-xs text-base-content/65">
                {format_percent(@insights_overview.progress_by_period.annual.completion_rate)}% de conclusão
              </p>
            </article>

            <article class="micro-surface rounded-xl p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Capacidade 14d</p>
              <p class="mt-1 text-lg font-semibold text-base-content">
                {@workload_capacity_snapshot.open_14d}/{@workload_capacity_snapshot.planned_capacity_14d}
              </p>
              <p class="text-xs text-base-content/65">
                Diferença: {@workload_capacity_snapshot.capacity_gap} • Alerta: {if @workload_capacity_snapshot.overload_alert, do: "ligado", else: "desligado"}
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
        </section>

        <section
          :if={!onboarding_complete?(@onboarding_counts)}
          class="surface-card rounded-2xl border border-cyan-400/25 bg-cyan-900/10 p-4"
          aria-label="Onboarding inicial"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-cyan-200">
            Configuração inicial em 2 passos
          </h2>
          <p class="mt-1 text-sm text-cyan-100/80">
            Configure primeiro categorias financeiras e metas para liberar visão completa do painel.
          </p>
          <ol class="mt-3 grid gap-2 md:grid-cols-2" aria-label="Checklist de onboarding">
            <li class={onboarding_step_class(@onboarding_counts.finance_categories)}>
              <span class="font-medium">Configurar categorias financeiras</span>
              <span class="text-xs">
                status: {onboarding_step_label(@onboarding_counts.finance_categories)}
              </span>
            </li>
            <li class={onboarding_step_class(@onboarding_counts.goals)}>
              <span class="font-medium">Definir primeira meta</span>
              <span class="text-xs">status: {onboarding_step_label(@onboarding_counts.goals)}</span>
            </li>
          </ol>
        </section>

        <div class="grid gap-6 lg:grid-cols-3">
          <section
            id="quick-task"
            class="surface-card rounded-2xl p-4 scroll-mt-20"
          >
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Captura rápida de tarefa
            </h2>
            <.form
              for={@task_form}
              id="task-form"
              phx-submit="add_task"
              class="mt-3 space-y-2"
              aria-label="Formulário de captura rápida de tarefa"
            >
              <.input field={@task_form[:title]} type="text" label="Título" required />
              <.input field={@task_form[:due_on]} type="date" label="Data" />
              <.input
                field={@task_form[:priority]}
                type="select"
                label="Prioridade"
                options={[{"Baixa", "low"}, {"Média", "medium"}, {"Alta", "high"}]}
              />
              <.button class="w-full">Adicionar tarefa</.button>
            </.form>
          </section>

          <section
            id="quick-finance"
            class="surface-card rounded-2xl p-4 scroll-mt-20"
          >
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Captura rápida financeira
            </h2>
            <div class="mt-3">
              <p class="text-xs font-medium text-base-content/70">Sugestões de categoria</p>
              <div class="mt-2 flex flex-wrap gap-2">
                <button
                  :for={category <- @finance_category_presets}
                  id={"finance-category-preset-#{category}"}
                  type="button"
                  phx-click="use_finance_category_preset"
                  phx-value-category={category}
                  class="ds-pill-btn rounded-full px-3 py-1 text-xs"
                >
                  {finance_category_label(category)}
                </button>
              </div>
            </div>
            <.form
              for={@finance_form}
              id="finance-form"
              phx-submit="add_finance"
              class="mt-3 space-y-2"
              aria-label="Formulário de captura rápida financeira"
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
              <.button class="w-full">Adicionar lançamento</.button>
            </.form>
          </section>

          <section
            id="quick-goal"
            class="surface-card rounded-2xl p-4 scroll-mt-20"
          >
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Captura rápida de meta
            </h2>
            <.form
              for={@goal_form}
              id="goal-form"
              phx-submit="add_goal"
              class="mt-3 space-y-2"
              aria-label="Formulário de captura rápida de meta"
            >
              <.input field={@goal_form[:title]} type="text" label="Meta" required />
              <.input
                field={@goal_form[:horizon]}
                type="select"
                label="Horizonte"
                options={[{"Curto", "short"}, {"Médio", "medium"}, {"Longo", "long"}]}
                required
              />
              <.input field={@goal_form[:target_value]} type="number" label="Alvo" />
              <.button class="w-full">Adicionar meta</.button>
            </.form>
          </section>
        </div>

        <div class="grid gap-6 lg:grid-cols-3">
          <section class="surface-card rounded-2xl p-4">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Próximas tarefas
            </h2>
            <form
              id="task-filters"
              phx-change="filter_tasks"
              class="mt-3 grid gap-2 sm:grid-cols-3"
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
                <option value="all" selected={@task_filters.priority == "all"}>Todas prioridades</option>
                <option value="low" selected={@task_filters.priority == "low"}>Baixa</option>
                <option value="medium" selected={@task_filters.priority == "medium"}>Média</option>
                <option value="high" selected={@task_filters.priority == "high"}>Alta</option>
              </select>
              <select name="filters[days]" class="select select-bordered select-sm">
                <option value="7" selected={@task_filters.days == "7"}>7 dias</option>
                <option value="14" selected={@task_filters.days == "14"}>14 dias</option>
                <option value="30" selected={@task_filters.days == "30"}>30 dias</option>
              </select>
            </form>
            <div id="tasks" phx-update="stream" class="mt-3 space-y-2">
              <div
                id="tasks-empty"
                class="ds-empty-state hidden only:block rounded-lg p-4 text-sm"
              >
                Nenhuma tarefa cadastrada.
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
                  class="ds-edit-form mt-3 space-y-2 rounded-md p-3"
                >
                  <input type="hidden" name="_id" value={task.id} />
                  <label class="text-xs font-medium text-base-content/70" for={"task-title-#{task.id}"}>
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
                      <label class="text-xs font-medium text-base-content/70" for={"task-priority-#{task.id}"}>
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
                      <label class="text-xs font-medium text-base-content/70" for={"task-status-#{task.id}"}>
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

          <section class="surface-card rounded-2xl p-4">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Lançamentos recentes
            </h2>
            <form
              id="finance-filters"
              phx-change="filter_finances"
              class="mt-3"
              aria-label="Filtros de lançamentos"
            >
              <select name="filters[days]" class="select select-bordered select-sm w-full">
                <option value="7" selected={@finance_filters.days == "7"}>Últimos 7 dias</option>
                <option value="30" selected={@finance_filters.days == "30"}>Últimos 30 dias</option>
                <option value="90" selected={@finance_filters.days == "90"}>Últimos 90 dias</option>
              </select>
            </form>
            <div id="finances" phx-update="stream" class="mt-3 space-y-2">
              <div
                id="finances-empty"
                class="ds-empty-state hidden only:block rounded-lg p-4 text-sm"
              >
                Nenhum lançamento cadastrado.
              </div>
              <article
                :for={{id, entry} <- @streams.finances}
                id={id}
                class="micro-surface rounded-lg p-3"
              >
                <p class="font-medium text-base-content">{entry.category}</p>
                <p class="text-xs text-base-content/65">
                  {to_string(entry.kind)} • {format_money(entry.amount_cents)} • {Date.to_iso8601(entry.occurred_on)}
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
                  class="ds-edit-form mt-3 space-y-2 rounded-md p-3"
                >
                  <input type="hidden" name="_id" value={entry.id} />
                  <div class="grid gap-2 sm:grid-cols-2">
                    <div>
                      <label class="text-xs font-medium text-base-content/70" for={"finance-kind-#{entry.id}"}>
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
                      <label class="text-xs font-medium text-base-content/70" for={"finance-amount-#{entry.id}"}>
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
                  <label class="text-xs font-medium text-base-content/70" for={"finance-category-#{entry.id}"}>
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
                  <label class="text-xs font-medium text-base-content/70" for={"finance-date-#{entry.id}"}>
                    Data
                  </label>
                  <input
                    id={"finance-date-#{entry.id}"}
                    name="finance[occurred_on]"
                    type="date"
                    value={date_input_value(entry.occurred_on)}
                    class="input input-bordered w-full"
                  />
                  <label class="text-xs font-medium text-base-content/70" for={"finance-description-#{entry.id}"}>
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

          <section class="surface-card rounded-2xl p-4">
            <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Metas em andamento
            </h2>
            <form
              id="goal-filters"
              phx-change="filter_goals"
              class="mt-3"
              aria-label="Filtros de metas"
            >
              <select name="filters[status]" class="select select-bordered select-sm w-full">
                <option value="all" selected={@goal_filters.status == "all"}>Todos status</option>
                <option value="active" selected={@goal_filters.status == "active"}>Ativa</option>
                <option value="paused" selected={@goal_filters.status == "paused"}>Pausada</option>
                <option value="done" selected={@goal_filters.status == "done"}>Concluída</option>
              </select>
            </form>
            <div id="goals" phx-update="stream" class="mt-3 space-y-2">
              <div
                id="goals-empty"
                class="ds-empty-state hidden only:block rounded-lg p-4 text-sm"
              >
                Nenhuma meta cadastrada.
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
                  class="ds-edit-form mt-3 space-y-2 rounded-md p-3"
                >
                  <input type="hidden" name="_id" value={goal.id} />
                  <label class="text-xs font-medium text-base-content/70" for={"goal-title-#{goal.id}"}>
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
                      <label class="text-xs font-medium text-base-content/70" for={"goal-horizon-#{goal.id}"}>
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
                      <label class="text-xs font-medium text-base-content/70" for={"goal-status-#{goal.id}"}>
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
                      <label class="text-xs font-medium text-base-content/70" for={"goal-target-#{goal.id}"}>
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
                      <label class="text-xs font-medium text-base-content/70" for={"goal-current-#{goal.id}"}>
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
                  <label class="text-xs font-medium text-base-content/70" for={"goal-date-#{goal.id}"}>
                    Data
                  </label>
                  <input
                    id={"goal-date-#{goal.id}"}
                    name="goal[due_on]"
                    type="date"
                    value={date_input_value(goal.due_on)}
                    class="input input-bordered w-full"
                  />
                  <label class="text-xs font-medium text-base-content/70" for={"goal-notes-#{goal.id}"}>
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
      </section>
    </Layouts.app>
    """
  end

  defp format_money(cents) when is_integer(cents) do
    value = cents / 100
    :erlang.float_to_binary(value, decimals: 2)
  end

  defp date_input_value(nil), do: ""
  defp date_input_value(%Date{} = date), do: Date.to_iso8601(date)

  defp editing?(editing_id, id) do
    to_string(editing_id) == to_string(id)
  end

  defp format_percent(value) when is_number(value), do: Float.round(value * 1.0, 1)

  defp burnout_level_label(:high), do: "Alto"
  defp burnout_level_label(:medium), do: "Médio"
  defp burnout_level_label(_), do: "Baixo"

  defp risk_badge_class(:high), do: "border border-rose-300/30 bg-rose-500/15 text-rose-100"
  defp risk_badge_class(:medium), do: "border border-amber-300/30 bg-amber-500/15 text-amber-100"
  defp risk_badge_class(_), do: "border border-emerald-300/30 bg-emerald-500/15 text-emerald-100"

  defp onboarding_complete?(counts) do
    counts.finance_categories > 0 and counts.goals > 0
  end

  defp onboarding_step_label(count) when count > 0, do: "concluído"
  defp onboarding_step_label(_count), do: "pendente"

  defp onboarding_step_class(count) when count > 0 do
    "rounded-xl border border-emerald-300/35 bg-emerald-500/12 p-3 text-emerald-100 flex flex-col gap-1"
  end

  defp onboarding_step_class(_count) do
    "rounded-xl border border-base-content/15 bg-base-100/70 p-3 text-base-content/80 flex flex-col gap-1"
  end

  defp finance_category_label("alimentacao"), do: "Alimentação"
  defp finance_category_label("saude"), do: "Saúde"
  defp finance_category_label("moradia"), do: "Moradia"
  defp finance_category_label("transporte"), do: "Transporte"
  defp finance_category_label("lazer"), do: "Lazer"
  defp finance_category_label("investimentos"), do: "Investimentos"
  defp finance_category_label(category), do: category

  defp count_unique_finance_categories(finances) do
    finances
    |> Enum.map(&(&1.category || ""))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&String.downcase/1)
    |> length()
  end
end
