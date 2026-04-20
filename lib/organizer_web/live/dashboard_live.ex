defmodule OrganizerWeb.DashboardLive do
  use OrganizerWeb, :live_view

  alias Organizer.Planning
  alias Organizer.SharedFinance
  alias OrganizerWeb.DashboardLive.{Filters, BulkImport, Insights}

  alias OrganizerWeb.DashboardLive.Components.{
    AccountLinkPanel,
    DashboardHeader,
    AnalyticsPanel,
    OperationsPanel
  }

  @analytics_days_filters ["7", "15", "30", "90", "365"]
  @analytics_capacity_filters ["5", "10", "15", "20", "30"]
  @bulk_template_keys ["mixed", "tasks", "finance", "goals"]
  @ops_tabs ["tasks", "finances", "goals"]
  @max_bulk_payload_bytes 50_000

  @impl true
  def mount(_params, _session, socket) do
    # Authentication is handled by live_session :authenticated on_mount callback
    # which ensures current_scope is already assigned to the socket
    case socket.assigns do
      %{current_scope: %{user: user}} when not is_nil(user) ->
        scope = socket.assigns.current_scope
        initialized = initialize_dashboard_state(socket, scope)

        socket =
          if connected?(initialized) do
            load_chart_svgs(initialized)
          else
            initialized
          end

        {:ok, socket}

      _ ->
        # Fallback redirect if authentication somehow failed
        {:ok, redirect(socket, to: ~p"/users/log-in")}
    end
  end

  use OrganizerWeb.DashboardLive.BulkEventHandlers

  @impl true
  def handle_event("filter_tasks", %{"filters" => filters}, socket) do
    task_filters =
      socket.assigns.task_filters
      |> Map.merge(Filters.normalize_task_filters(filters))
      |> Filters.sanitize_task_filters()

    {:noreply,
     socket
     |> assign(:task_filters, task_filters)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("filter_finances", %{"filters" => filters}, socket) do
    finance_filters =
      socket.assigns.finance_filters
      |> Map.merge(Filters.normalize_finance_filters(filters))
      |> Filters.sanitize_finance_filters()

    {:noreply,
     socket
     |> assign(:finance_filters, finance_filters)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("filter_goals", %{"filters" => filters}, socket) do
    goal_filters =
      socket.assigns.goal_filters
      |> Map.merge(Filters.normalize_goal_filters(filters))
      |> Filters.sanitize_goal_filters()

    {:noreply,
     socket
     |> assign(:goal_filters, goal_filters)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("filter_analytics", %{"filters" => filters}, socket) do
    analytics_filters =
      socket.assigns.analytics_filters
      |> Map.merge(Filters.normalize_analytics_filters(filters))
      |> Filters.sanitize_analytics_filters()

    {:noreply,
     socket
     |> assign(:analytics_filters, analytics_filters)
     |> assign(:progress_chart, %{loading: true, chart_svg: nil})
     |> assign(:finance_trend_chart, %{loading: true, chart_svg: nil})
     |> assign(:finance_category_chart, %{loading: true, chart_svg: nil})
     |> refresh_dashboard_insights()
     |> load_chart_svgs()}
  end

  @impl true
  def handle_event("set_analytics_days", %{"days" => days}, socket)
      when days in @analytics_days_filters do
    analytics_filters =
      socket.assigns.analytics_filters
      |> Map.put(:days, days)
      |> Filters.sanitize_analytics_filters()

    {:noreply,
     socket
     |> assign(:analytics_filters, analytics_filters)
     |> assign(:progress_chart, %{loading: true, chart_svg: nil})
     |> assign(:finance_trend_chart, %{loading: true, chart_svg: nil})
     |> assign(:finance_category_chart, %{loading: true, chart_svg: nil})
     |> refresh_dashboard_insights()
     |> load_chart_svgs()}
  end

  @impl true
  def handle_event("set_analytics_capacity", %{"planned_capacity" => capacity}, socket)
      when capacity in @analytics_capacity_filters do
    analytics_filters =
      socket.assigns.analytics_filters
      |> Map.put(:planned_capacity, capacity)
      |> Filters.sanitize_analytics_filters()

    {:noreply,
     socket
     |> assign(:analytics_filters, analytics_filters)
     |> assign(:progress_chart, %{loading: true, chart_svg: nil})
     |> assign(:finance_trend_chart, %{loading: true, chart_svg: nil})
     |> assign(:finance_category_chart, %{loading: true, chart_svg: nil})
     |> refresh_dashboard_insights()
     |> load_chart_svgs()}
  end

  @impl true
  def handle_event("set_ops_tab", %{"tab" => tab}, socket) when tab in @ops_tabs do
    {:noreply, assign(socket, :ops_tab, tab)}
  end

  @impl true
  def handle_event("next_onboarding_step", _params, socket) do
    current_step = socket.assigns.onboarding_step
    new_step = min(current_step + 1, 6)

    case Organizer.Accounts.get_or_create_onboarding_progress(socket.assigns.current_scope.user) do
      {:ok, progress} ->
        case Organizer.Accounts.advance_onboarding_step(progress) do
          {:ok, _updated_progress} ->
            {:noreply, assign(socket, :onboarding_step, new_step)}

          {:error, _} ->
            {:noreply, assign(socket, :onboarding_step, new_step)}
        end

      {:error, _} ->
        {:noreply, assign(socket, :onboarding_step, new_step)}
    end
  end

  @impl true
  def handle_event("prev_onboarding_step", _params, socket) do
    current_step = socket.assigns.onboarding_step
    new_step = max(current_step - 1, 1)
    {:noreply, assign(socket, :onboarding_step, new_step)}
  end

  @impl true
  def handle_event("skip_onboarding", _params, socket) do
    case Organizer.Accounts.get_or_create_onboarding_progress(socket.assigns.current_scope.user) do
      {:ok, progress} ->
        case Organizer.Accounts.dismiss_onboarding(progress) do
          {:ok, _} ->
            {:noreply, assign(socket, :onboarding_active, false)}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:onboarding_active, false)
             |> put_flash(:error, "Não foi possível salvar preferência.")}
        end

      {:error, _} ->
        {:noreply, assign(socket, :onboarding_active, false)}
    end
  end

  @impl true
  def handle_event("complete_onboarding", _params, socket) do
    case Organizer.Accounts.get_or_create_onboarding_progress(socket.assigns.current_scope.user) do
      {:ok, progress} ->
        case Organizer.Accounts.complete_onboarding(progress) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:onboarding_active, false)
             |> put_flash(:info, "Onboarding concluído! Bem-vindo ao Organizer.")}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:onboarding_active, false)
             |> put_flash(:error, "Não foi possível salvar preferência.")}
        end

      {:error, _} ->
        {:noreply, assign(socket, :onboarding_active, false)}
    end
  end

  @impl true
  def handle_event("toggle_help_menu", _params, socket) do
    {:noreply, assign(socket, :help_menu_open, !socket.assigns.help_menu_open)}
  end

  @impl true
  def handle_event("close_help_menu", _params, socket) do
    {:noreply, assign(socket, :help_menu_open, false)}
  end

  @impl true
  def handle_event("show_onboarding_tutorial", _params, socket) do
    case Organizer.Accounts.get_or_create_onboarding_progress(socket.assigns.current_scope.user) do
      {:ok, progress} ->
        case Organizer.Accounts.restart_onboarding(progress) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:onboarding_active, true)
             |> assign(:onboarding_step, 1)
             |> assign(:help_menu_open, false)
             |> put_flash(
               :info,
               "Tutorial iniciado. Siga os passos para aprender a usar a plataforma."
             )}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:onboarding_active, true)
             |> assign(:onboarding_step, 1)
             |> assign(:help_menu_open, false)}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:onboarding_active, true)
         |> assign(:onboarding_step, 1)
         |> assign(:help_menu_open, false)}
    end
  end

  @impl true
  def handle_event("restart_onboarding_tutorial", _params, socket) do
    case Organizer.Accounts.get_or_create_onboarding_progress(socket.assigns.current_scope.user) do
      {:ok, progress} ->
        case Organizer.Accounts.restart_onboarding(progress) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:onboarding_active, true)
             |> assign(:onboarding_step, 1)
             |> assign(:help_menu_open, false)
             |> put_flash(
               :info,
               "Tutorial reiniciado. Siga os passos para aprender a usar a plataforma."
             )}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Não foi possível reiniciar o tutorial.")}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Não foi possível reiniciar o tutorial.")}
    end
  end

  @impl true
  def handle_event("show_keyboard_shortcuts", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Atalhos: Alt+B (focar editor), ? (ajuda)")}
  end

  @impl true
  def handle_event("global_shortcut", params, socket) when is_map(params) do
    normalized_key =
      case Map.get(params, "key") do
        key when is_binary(key) -> String.downcase(key)
        _ -> ""
      end

    alt_pressed? = Map.get(params, "altKey") in [true, "true"]

    cond do
      alt_pressed? and normalized_key == "b" ->
        {:noreply,
         push_event(socket, "scroll-to-element", %{
           selector: "#bulk-import-hero",
           focus: "#bulk-payload-input"
         })}

      normalized_key == "?" ->
        {:noreply,
         socket
         |> assign(:help_menu_open, true)
         |> put_flash(:info, "Atalhos: Alt+B (focar editor), ? (ajuda)")}

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("load_example_to_bulk", %{"entity_type" => entity_type}, socket) do
    example_text =
      case entity_type do
        "tasks" -> generate_task_example()
        "finances" -> generate_finance_example()
        "goals" -> generate_goal_example()
        _ -> generate_mixed_example()
      end

    {:noreply,
     socket
     |> assign(:bulk_payload_text, String.trim(example_text))
     |> assign(:bulk_form, to_form(%{"payload" => String.trim(example_text)}, as: :bulk))
     |> push_event("scroll-to-element", %{
       selector: "#bulk-import-hero",
       focus: "#bulk-payload-input"
     })}
  end

  @impl true
  def handle_event("start_edit_task", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:ops_tab, "tasks")
     |> assign(:editing_task_id, id)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("cancel_edit_task", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_task_id, nil)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("save_task", %{"_id" => id, "task" => attrs}, socket) do
    case Planning.update_task(socket.assigns.current_scope, id, attrs) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tarefa atualizada.")
         |> assign(:editing_task_id, nil)
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

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
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

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
     |> assign(:ops_tab, "finances")
     |> assign(:editing_finance_id, id)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("cancel_edit_finance", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_finance_id, nil)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("save_finance", %{"_id" => id, "finance" => attrs}, socket) do
    case Planning.update_finance_entry(socket.assigns.current_scope, id, attrs) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Lançamento atualizado.")
         |> assign(:editing_finance_id, nil)
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

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
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

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
     |> assign(:ops_tab, "goals")
     |> assign(:editing_goal_id, id)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("cancel_edit_goal", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_goal_id, nil)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("save_goal", %{"_id" => id, "goal" => attrs}, socket) do
    case Planning.update_goal(socket.assigns.current_scope, id, attrs) do
      {:ok, _goal} ->
        {:noreply,
         socket
         |> put_flash(:info, "Meta atualizada.")
         |> assign(:editing_goal_id, nil)
         |> load_operation_collections()}

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
         |> load_operation_collections()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Meta não encontrada.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível remover a meta.")}
    end
  end

  defp initialize_dashboard_state(socket, scope) do
    top_categories = FieldSuggester.suggest_values("category", scope)
    {:ok, account_links} = SharedFinance.list_account_links(scope)
    default_bulk_share_link_id = account_links |> List.first() |> then(&(&1 && &1.id))

    {:ok, user_preferences} = Organizer.Accounts.get_or_create_user_preferences(scope.user)
    {:ok, onboarding_progress} = Organizer.Accounts.get_or_create_onboarding_progress(scope.user)

    onboarding_active =
      !user_preferences.onboarding_completed && !onboarding_progress.dismissed &&
        is_nil(onboarding_progress.completed_at)

    {:ok, tasks} = Planning.list_tasks(scope, Filters.default_task_filters())
    {:ok, finances} = Planning.list_finance_entries(scope, Filters.default_finance_filters())
    {:ok, goals} = Planning.list_goals(scope, Filters.default_goal_filters())
    has_any_imports = length(tasks) > 0 || length(finances) > 0 || length(goals) > 0

    socket
    |> assign(:current_scope, scope)
    |> assign(:bulk_form, to_form(%{"payload" => ""}, as: :bulk))
    |> assign(:bulk_payload_text, "")
    |> assign(:bulk_result, nil)
    |> assign(:bulk_preview, nil)
    |> assign(:bulk_strict_mode, false)
    |> assign(:last_bulk_import, nil)
    |> assign(:bulk_recent_payloads, [])
    |> assign(:bulk_template_favorites, [])
    |> assign(:bulk_import_block_size, 3)
    |> assign(:bulk_import_block_index, 0)
    |> assign(:bulk_top_categories, top_categories)
    |> assign(:bulk_share_finances, false)
    |> assign(:bulk_share_link_id, default_bulk_share_link_id)
    |> assign(:account_links, account_links)
    |> assign(:ops_tab, "tasks")
    |> assign(:task_filters, Filters.default_task_filters())
    |> assign(:finance_filters, Filters.default_finance_filters())
    |> assign(:goal_filters, Filters.default_goal_filters())
    |> assign(:analytics_filters, Filters.default_analytics_filters())
    |> assign(:editing_task_id, nil)
    |> assign(:editing_finance_id, nil)
    |> assign(:editing_goal_id, nil)
    |> assign(:onboarding_active, onboarding_active)
    |> assign(:onboarding_step, onboarding_progress.current_step)
    |> assign(:has_any_imports, has_any_imports)
    |> assign(:help_menu_open, false)
    |> assign(:progress_chart, %{loading: true, chart_svg: nil})
    |> assign(:finance_trend_chart, %{loading: true, chart_svg: nil})
    |> assign(:finance_category_chart, %{loading: true, chart_svg: nil})
    |> load_operation_collections()
    |> refresh_dashboard_insights()
  end

  defp load_operation_collections(socket) do
    {:ok, tasks} = Planning.list_tasks(socket.assigns.current_scope, socket.assigns.task_filters)

    {:ok, finances} =
      Planning.list_finance_entries(socket.assigns.current_scope, socket.assigns.finance_filters)

    {:ok, goals} = Planning.list_goals(socket.assigns.current_scope, socket.assigns.goal_filters)

    socket
    |> stream(:tasks, tasks, reset: true)
    |> stream(:finances, finances, reset: true)
    |> stream(:goals, goals, reset: true)
    |> assign(:ops_counts, %{
      tasks_total: length(tasks),
      tasks_open: Enum.count(tasks, &(&1.status != :done)),
      finances_total: length(finances),
      goals_total: length(goals),
      goals_active: Enum.count(goals, &(&1.status == :active))
    })
  end

  defp refresh_dashboard_insights(socket) do
    Insights.refresh_dashboard_insights(socket)
  end

  defp load_chart_svgs(socket) do
    Insights.load_chart_svgs(socket)
  end

  # Example generators for empty state interactions

  defp generate_task_example do
    """
    tarefa: Comprar mantimentos no supermercado
    tarefa: Agendar consulta médica para check-up
    tarefa: Revisar relatório mensal de vendas
    tarefa: Organizar documentos fiscais
    tarefa: Planejar reunião de equipe
    """
  end

  defp generate_finance_example do
    """
    finança: -120.50 Supermercado - compras da semana
    finança: 3500 Salário mensal
    finança: -45 Transporte - combustível
    finança: -89.90 Restaurante - almoço em família
    finança: -250 Conta de luz
    """
  end

  defp generate_goal_example do
    """
    meta: Economizar R$ 5000 para viagem de férias
    meta: Ler 24 livros durante o ano
    meta: Fazer exercícios 3 vezes por semana
    meta: Aprender um novo idioma
    meta: Reduzir gastos mensais em 15%
    """
  end

  defp generate_mixed_example do
    """
    tarefa: Revisar documentação do projeto
    finança: -50 Almoço executivo
    meta: Ler 12 livros este ano
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide={true}>
      <nav aria-label="Atalhos de navegação">
        <a href="#bulk-import-hero" class="skip-link">Ir para importação em lote</a>
        <a href="#operations-panel" class="skip-link">Ir para operação diária</a>
        <a href="#analytics-panel" class="skip-link">Ir para visão analítica</a>
      </nav>

      <OrganizerWeb.Components.OnboardingOverlay.onboarding_overlay
        active={@onboarding_active}
        current_step={@onboarding_step}
        total_steps={6}
        can_skip={true}
      />

      <div
        id="dashboard-keyboard-shortcuts"
        class="flex flex-col gap-4 lg:gap-6"
        phx-window-keydown="global_shortcut"
      >
        <DashboardHeader.dashboard_header
          workload_capacity_snapshot={@workload_capacity_snapshot}
          finance_summary={@finance_summary}
          onboarding_completed={!@onboarding_active && @onboarding_step >= 6}
          help_menu_open={@help_menu_open}
        />

        <AccountLinkPanel.account_link_panel
          account_links={@account_links}
          current_user_id={@current_scope.user.id}
        />

        <OrganizerWeb.Components.BulkImportHero.bulk_import_hero
          bulk_form={@bulk_form}
          bulk_payload_text={@bulk_payload_text}
          bulk_result={@bulk_result}
          bulk_preview={@bulk_preview}
          bulk_strict_mode={@bulk_strict_mode}
          last_bulk_import={@last_bulk_import}
          bulk_recent_payloads={@bulk_recent_payloads}
          bulk_template_favorites={@bulk_template_favorites}
          bulk_import_block_size={@bulk_import_block_size}
          bulk_import_block_index={@bulk_import_block_index}
          bulk_top_categories={@bulk_top_categories}
          bulk_share_finances={@bulk_share_finances}
          bulk_share_link_id={@bulk_share_link_id}
          account_links={@account_links}
          current_user_id={@current_scope.user.id}
          onboarding_active={@onboarding_active}
          onboarding_step={@onboarding_step}
          has_any_imports={@has_any_imports}
        />

        <OperationsPanel.operations_panel
          streams={@streams}
          ops_tab={@ops_tab}
          task_filters={@task_filters}
          finance_filters={@finance_filters}
          goal_filters={@goal_filters}
          editing_task_id={@editing_task_id}
          editing_finance_id={@editing_finance_id}
          editing_goal_id={@editing_goal_id}
          ops_counts={@ops_counts}
        />

        <AnalyticsPanel.analytics_panel
          analytics_filters={@analytics_filters}
          insights_overview={@insights_overview}
          workload_capacity_snapshot={@workload_capacity_snapshot}
          progress_chart={@progress_chart}
          finance_trend_chart={@finance_trend_chart}
          finance_category_chart={@finance_category_chart}
          ops_counts={@ops_counts}
        />
      </div>
    </Layouts.app>
    """
  end
end
