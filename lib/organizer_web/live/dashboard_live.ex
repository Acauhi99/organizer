defmodule OrganizerWeb.DashboardLive do
  use OrganizerWeb, :live_view

  alias Organizer.Planning
  alias Organizer.Planning.AmountParser
  alias Organizer.SharedFinance
  alias OrganizerWeb.DashboardLive.{Filters, BulkImport, Insights}

  alias OrganizerWeb.DashboardLive.Components.{
    AccountLinkPanel,
    DashboardHeader,
    AnalyticsPanel,
    OperationsPanel
  }

  alias OrganizerWeb.Components.{QuickFinanceHero, QuickTaskHero}

  @analytics_days_filters ["7", "15", "30", "90", "365"]
  @analytics_capacity_filters ["5", "10", "15", "20", "30"]
  @bulk_template_keys ["mixed", "tasks", "finance"]
  @ops_tabs ["tasks", "finances"]
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
  def handle_event("quick_finance_validate", %{"quick_finance" => attrs}, socket) do
    normalized = normalize_quick_finance_attrs(attrs, socket.assigns.account_links)

    {:noreply,
     socket
     |> assign(:quick_finance_kind, normalized["kind"])
     |> assign(:quick_finance_form, to_form(normalized, as: :quick_finance))}
  end

  @impl true
  def handle_event("quick_finance_preset", %{"preset" => preset}, socket) do
    preset_attrs = quick_finance_preset_attrs(preset)
    normalized = normalize_quick_finance_attrs(preset_attrs, socket.assigns.account_links)

    {:noreply,
     socket
     |> assign(:quick_finance_kind, normalized["kind"])
     |> assign(:quick_finance_form, to_form(normalized, as: :quick_finance))}
  end

  @impl true
  def handle_event("create_quick_finance", %{"quick_finance" => attrs}, socket) do
    normalized =
      normalize_quick_finance_attrs(attrs, socket.assigns.account_links, parse_amount?: true)

    case Planning.create_finance_entry(socket.assigns.current_scope, normalized) do
      {:ok, entry} ->
        share_result =
          maybe_share_quick_finance_entry(socket.assigns.current_scope, entry, normalized)

        kind = normalized["kind"]
        reset_form = quick_finance_defaults(kind, socket.assigns.account_links)

        flash_message =
          case share_result do
            :shared ->
              "Lançamento registrado e compartilhado no vínculo."

            {:share_failed, reason} ->
              "Lançamento registrado, mas #{reason}."

            :not_shared ->
              "Lançamento registrado."
          end

        flash_level =
          if match?({:share_failed, _reason}, share_result), do: :error, else: :info

        {:noreply,
         socket
         |> assign(:quick_finance_kind, kind)
         |> assign(:quick_finance_form, to_form(reset_form, as: :quick_finance))
         |> put_flash(flash_level, flash_message)
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

      {:error, {:validation, _details}} ->
        {:noreply,
         socket
         |> assign(:quick_finance_kind, normalized["kind"])
         |> assign(:quick_finance_form, to_form(normalized, as: :quick_finance))
         |> put_flash(:error, "Verifique os campos para registrar o lançamento.")}

      _ ->
        {:noreply,
         socket
         |> assign(:quick_finance_kind, normalized["kind"])
         |> assign(:quick_finance_form, to_form(normalized, as: :quick_finance))
         |> put_flash(:error, "Não foi possível registrar o lançamento.")}
    end
  end

  @impl true
  def handle_event("quick_task_validate", %{"quick_task" => attrs}, socket) do
    normalized = normalize_quick_task_attrs(attrs)

    {:noreply, assign(socket, :quick_task_form, to_form(normalized, as: :quick_task))}
  end

  @impl true
  def handle_event("quick_task_preset", %{"preset" => preset}, socket) do
    preset_attrs = quick_task_preset_attrs(preset)
    normalized = normalize_quick_task_attrs(preset_attrs)

    {:noreply, assign(socket, :quick_task_form, to_form(normalized, as: :quick_task))}
  end

  @impl true
  def handle_event("create_quick_task", %{"quick_task" => attrs}, socket) do
    normalized = normalize_quick_task_attrs(attrs)

    case Planning.create_task(socket.assigns.current_scope, normalized) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> assign(:quick_task_form, to_form(quick_task_defaults(), as: :quick_task))
         |> put_flash(:info, "Tarefa registrada.")
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

      {:error, {:validation, _details}} ->
        {:noreply,
         socket
         |> assign(:quick_task_form, to_form(normalized, as: :quick_task))
         |> put_flash(:error, "Verifique os campos para registrar a tarefa.")}

      _ ->
        {:noreply,
         socket
         |> assign(:quick_task_form, to_form(normalized, as: :quick_task))
         |> put_flash(:error, "Não foi possível registrar a tarefa.")}
    end
  end

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
     |> assign(:task_priority_chart, %{loading: true, chart_svg: nil})
     |> assign(:finance_mix_chart, %{loading: true, chart_svg: nil})
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
     |> assign(:task_priority_chart, %{loading: true, chart_svg: nil})
     |> assign(:finance_mix_chart, %{loading: true, chart_svg: nil})
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
     |> assign(:task_priority_chart, %{loading: true, chart_svg: nil})
     |> assign(:finance_mix_chart, %{loading: true, chart_svg: nil})
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
     |> put_flash(:info, "Atalhos: Alt+B (lançamento rápido), ? (ajuda)")}
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
           selector: "#quick-finance-hero",
           focus: "#quick-finance-amount"
         })}

      normalized_key == "?" ->
        {:noreply,
         socket
         |> assign(:help_menu_open, true)
         |> put_flash(:info, "Atalhos: Alt+B (lançamento rápido), ? (ajuda)")}

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
  def handle_event(
        "add_task_checklist_item",
        %{"task_id" => task_id, "checklist_item" => %{"label" => label}},
        socket
      ) do
    case Planning.add_task_checklist_item(socket.assigns.current_scope, task_id, %{
           "label" => label
         }) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Item adicionado na checklist.")
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Informe um nome válido para o item da checklist.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Tarefa não encontrada.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível adicionar o item da checklist.")}
    end
  end

  @impl true
  def handle_event(
        "save_task_checklist_item_label",
        %{
          "task_id" => task_id,
          "item_id" => item_id,
          "checklist_item" => %{"label" => label}
        },
        socket
      ) do
    case Planning.update_task_checklist_item(
           socket.assigns.current_scope,
           task_id,
           item_id,
           %{"label" => label}
         ) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Item da checklist atualizado.")
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Informe um nome válido para o item da checklist.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Item da checklist não encontrado.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível atualizar o item da checklist.")}
    end
  end

  @impl true
  def handle_event(
        "toggle_task_checklist_item",
        %{"task_id" => task_id, "item_id" => item_id, "checked" => checked},
        socket
      ) do
    case Planning.toggle_task_checklist_item(
           socket.assigns.current_scope,
           task_id,
           item_id,
           checked
         ) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Item da checklist não encontrado.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível atualizar o item da checklist.")}
    end
  end

  @impl true
  def handle_event(
        "delete_task_checklist_item",
        %{"task_id" => task_id, "item_id" => item_id},
        socket
      ) do
    case Planning.delete_task_checklist_item(socket.assigns.current_scope, task_id, item_id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Item removido da checklist.")
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Item da checklist não encontrado.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível remover o item da checklist.")}
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
    has_any_imports = length(tasks) > 0 || length(finances) > 0

    socket
    |> assign(:current_scope, scope)
    |> assign(:quick_finance_kind, "expense")
    |> assign(
      :quick_finance_form,
      to_form(quick_finance_defaults("expense", account_links), as: :quick_finance)
    )
    |> assign(:quick_task_form, to_form(quick_task_defaults(), as: :quick_task))
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
    |> assign(:analytics_filters, Filters.default_analytics_filters())
    |> assign(:editing_task_id, nil)
    |> assign(:editing_finance_id, nil)
    |> assign(:onboarding_active, onboarding_active)
    |> assign(:onboarding_step, onboarding_progress.current_step)
    |> assign(:has_any_imports, has_any_imports)
    |> assign(:help_menu_open, false)
    |> assign(:progress_chart, %{loading: true, chart_svg: nil})
    |> assign(:finance_trend_chart, %{loading: true, chart_svg: nil})
    |> assign(:finance_category_chart, %{loading: true, chart_svg: nil})
    |> assign(:task_priority_chart, %{loading: true, chart_svg: nil})
    |> assign(:finance_mix_chart, %{loading: true, chart_svg: nil})
    |> assign(:analytics_highlights, Insights.default_analytics_highlights())
    |> load_operation_collections()
    |> refresh_dashboard_insights()
  end

  defp load_operation_collections(socket) do
    {:ok, tasks} = Planning.list_tasks(socket.assigns.current_scope, socket.assigns.task_filters)

    {:ok, finances} =
      Planning.list_finance_entries(socket.assigns.current_scope, socket.assigns.finance_filters)

    finance_income = Enum.filter(finances, &(&1.kind == :income))
    finance_expenses = Enum.filter(finances, &(&1.kind == :expense))

    socket
    |> stream(:tasks, tasks, reset: true)
    |> stream(:finances, finances, reset: true)
    |> assign(:ops_counts, %{
      tasks_total: length(tasks),
      tasks_open: Enum.count(tasks, &(&1.status != :done)),
      finances_total: length(finances),
      finances_income_total: length(finance_income),
      finances_expense_total: length(finance_expenses),
      finances_income_cents: Enum.reduce(finance_income, 0, &(&1.amount_cents + &2)),
      finances_expense_cents: Enum.reduce(finance_expenses, 0, &(&1.amount_cents + &2))
    })
  end

  defp refresh_dashboard_insights(socket) do
    Insights.refresh_dashboard_insights(socket)
  end

  defp load_chart_svgs(socket) do
    Insights.load_chart_svgs(socket)
  end

  defp quick_finance_defaults(kind \\ "expense", account_links \\ []) do
    default_shared_with_link_id =
      account_links
      |> List.first()
      |> then(&if is_nil(&1), do: "", else: to_string(&1.id))

    %{
      "kind" => kind,
      "amount_cents" => "",
      "category" => default_quick_finance_category(kind),
      "description" => "",
      "occurred_on" => Date.to_iso8601(Date.utc_today()),
      "expense_profile" => default_quick_expense_profile(kind),
      "payment_method" => default_quick_payment_method(kind),
      "share_with_link" => "false",
      "shared_with_link_id" => if(kind == "expense", do: default_shared_with_link_id, else: ""),
      "shared_split_mode" => "income_ratio",
      "shared_manual_mine_amount" => "",
      "shared_manual_theirs_amount" => ""
    }
  end

  defp quick_finance_preset_attrs("income_salary") do
    %{
      "kind" => "income",
      "category" => "Salário"
    }
  end

  defp quick_finance_preset_attrs("income_extra") do
    %{
      "kind" => "income",
      "category" => "Renda extra"
    }
  end

  defp quick_finance_preset_attrs("expense_fixed") do
    %{
      "kind" => "expense",
      "category" => "Moradia",
      "expense_profile" => "fixed",
      "payment_method" => "debit"
    }
  end

  defp quick_finance_preset_attrs("expense_variable") do
    %{
      "kind" => "expense",
      "category" => "Alimentação",
      "expense_profile" => "variable",
      "payment_method" => "debit"
    }
  end

  defp quick_finance_preset_attrs(_preset), do: quick_finance_defaults()

  defp quick_task_defaults do
    %{
      "title" => "",
      "priority" => "medium",
      "status" => "todo",
      "due_on" => Date.to_iso8601(Date.utc_today()),
      "notes" => ""
    }
  end

  defp quick_task_preset_attrs("today_focus") do
    %{
      "title" => "Foco do dia",
      "priority" => "high",
      "status" => "in_progress",
      "due_on" => Date.to_iso8601(Date.utc_today())
    }
  end

  defp quick_task_preset_attrs("next_action") do
    %{
      "title" => "Próxima ação",
      "priority" => "medium",
      "status" => "todo",
      "due_on" => Date.to_iso8601(Date.utc_today())
    }
  end

  defp quick_task_preset_attrs("backlog") do
    %{
      "title" => "Item de backlog",
      "priority" => "low",
      "status" => "todo",
      "due_on" => Date.utc_today() |> Date.add(7) |> Date.to_iso8601()
    }
  end

  defp quick_task_preset_attrs("shopping_list") do
    %{
      "title" => "Lista de compras do mercado",
      "priority" => "medium",
      "status" => "todo",
      "due_on" => Date.to_iso8601(Date.utc_today()),
      "notes" => "Após salvar, adicione itens na checklist desta tarefa."
    }
  end

  defp quick_task_preset_attrs(_preset), do: quick_task_defaults()

  defp normalize_quick_task_attrs(attrs) when is_map(attrs) do
    defaults = quick_task_defaults()

    attrs
    |> string_key_map()
    |> Map.merge(defaults, fn _key, incoming, default -> default_if_blank(incoming, default) end)
    |> Map.update!("priority", &normalize_quick_task_priority/1)
    |> Map.update!("status", &normalize_quick_task_status/1)
  end

  defp normalize_quick_task_attrs(_attrs), do: quick_task_defaults()

  defp normalize_quick_finance_attrs(attrs, account_links, opts \\ [])

  defp normalize_quick_finance_attrs(attrs, account_links, opts) when is_map(attrs) do
    parse_amount? = Keyword.get(opts, :parse_amount?, false)

    kind =
      attrs
      |> Map.get("kind", "expense")
      |> to_string()
      |> String.trim()
      |> case do
        "income" -> "income"
        _ -> "expense"
      end

    defaults = quick_finance_defaults(kind, account_links)

    merged =
      defaults
      |> Map.merge(string_key_map(attrs))
      |> Map.put("kind", kind)
      |> Map.update!("category", &default_if_blank(&1, default_quick_finance_category(kind)))
      |> Map.update!("occurred_on", &default_if_blank(&1, Date.to_iso8601(Date.utc_today())))
      |> normalize_quick_finance_share_fields(kind, account_links)
      |> maybe_parse_quick_finance_amount(parse_amount?)

    if kind == "income" do
      merged
      |> Map.put("expense_profile", "")
      |> Map.put("payment_method", "")
    else
      merged
      |> Map.update!(
        "expense_profile",
        &default_if_blank(&1, default_quick_expense_profile(kind))
      )
      |> Map.update!("payment_method", &default_if_blank(&1, default_quick_payment_method(kind)))
    end
  end

  defp normalize_quick_finance_attrs(_attrs, account_links, _opts),
    do: quick_finance_defaults("expense", account_links)

  defp maybe_parse_quick_finance_amount(attrs, false), do: attrs

  defp maybe_parse_quick_finance_amount(attrs, true) do
    amount_value = Map.get(attrs, "amount_cents")

    case parse_quick_finance_amount_cents(amount_value) do
      {:ok, cents} -> Map.put(attrs, "amount_cents", Integer.to_string(cents))
      :error -> attrs
    end
  end

  defp parse_quick_finance_amount_cents(value) when is_integer(value), do: {:ok, value}

  defp parse_quick_finance_amount_cents(value) when is_binary(value) do
    cleaned = String.trim(value)

    if cleaned == "" do
      :error
    else
      case AmountParser.parse(cleaned) do
        {:ok, cents} -> {:ok, cents}
        _ -> :error
      end
    end
  end

  defp parse_quick_finance_amount_cents(_value), do: :error

  defp normalize_quick_finance_share_fields(attrs, kind, account_links) do
    link_ids = Enum.map(account_links, &to_string(&1.id))
    valid_link_ids = MapSet.new(link_ids)

    selected_link_id =
      attrs
      |> Map.get("shared_with_link_id", "")
      |> to_string()
      |> String.trim()

    default_link_id = List.first(link_ids) || ""

    normalized_link_id =
      if MapSet.member?(valid_link_ids, selected_link_id),
        do: selected_link_id,
        else: default_link_id

    cond do
      kind != "expense" or MapSet.size(valid_link_ids) == 0 ->
        attrs
        |> Map.put("share_with_link", "false")
        |> Map.put("shared_with_link_id", "")
        |> Map.put("shared_split_mode", "income_ratio")
        |> Map.put("shared_manual_mine_amount", "")
        |> Map.put("shared_manual_theirs_amount", "")

      truthy_quick_finance_value?(Map.get(attrs, "share_with_link")) ->
        attrs
        |> Map.put("share_with_link", "true")
        |> Map.put("shared_with_link_id", normalized_link_id)
        |> normalize_quick_finance_split_mode()
        |> derive_quick_finance_manual_theirs_amount()

      true ->
        attrs
        |> Map.put("share_with_link", "false")
        |> Map.put("shared_with_link_id", normalized_link_id)
        |> Map.put("shared_split_mode", "income_ratio")
        |> Map.put("shared_manual_mine_amount", "")
        |> Map.put("shared_manual_theirs_amount", "")
    end
  end

  defp normalize_quick_finance_split_mode(attrs) do
    mode =
      attrs
      |> Map.get("shared_split_mode", "income_ratio")
      |> to_string()
      |> String.trim()
      |> case do
        "manual" -> "manual"
        _ -> "income_ratio"
      end

    Map.put(attrs, "shared_split_mode", mode)
  end

  defp derive_quick_finance_manual_theirs_amount(attrs) do
    if Map.get(attrs, "shared_split_mode") == "manual" do
      mine_value = Map.get(attrs, "shared_manual_mine_amount", "")

      case {
        parse_quick_finance_amount_cents(Map.get(attrs, "amount_cents")),
        parse_quick_finance_amount_cents(mine_value)
      } do
        {{:ok, total_cents}, {:ok, mine_cents}} ->
          normalized_mine = min(max(mine_cents, 0), total_cents)
          theirs_cents = total_cents - normalized_mine

          attrs
          |> Map.put("shared_manual_mine_amount", format_amount_input(normalized_mine))
          |> Map.put("shared_manual_theirs_amount", format_amount_input(theirs_cents))

        _ ->
          attrs
          |> Map.put("shared_manual_theirs_amount", "")
      end
    else
      attrs
      |> Map.put("shared_manual_mine_amount", "")
      |> Map.put("shared_manual_theirs_amount", "")
    end
  end

  defp truthy_quick_finance_value?(value) when is_boolean(value), do: value
  defp truthy_quick_finance_value?(value) when value in ["true", "on", "1"], do: true
  defp truthy_quick_finance_value?(_value), do: false

  defp maybe_share_quick_finance_entry(_scope, _entry, %{"kind" => "income"}), do: :not_shared

  defp maybe_share_quick_finance_entry(scope, entry, attrs) do
    if truthy_quick_finance_value?(Map.get(attrs, "share_with_link")) do
      case parse_quick_share_link_id(Map.get(attrs, "shared_with_link_id")) do
        {:ok, link_id} ->
          share_attrs = build_quick_share_attrs(attrs, entry.amount_cents)

          case SharedFinance.share_finance_entry(scope, entry.id, link_id, share_attrs) do
            {:ok, _shared_entry} ->
              :shared

            {:error, {:validation, details}} ->
              {:share_failed, quick_share_validation_message(details)}

            _ ->
              {:share_failed, "não foi possível aplicar o compartilhamento"}
          end

        :error ->
          {:share_failed, "vínculo inválido para compartilhamento"}
      end
    else
      :not_shared
    end
  end

  defp build_quick_share_attrs(attrs, total_cents) do
    mode =
      attrs
      |> Map.get("shared_split_mode", "income_ratio")
      |> to_string()
      |> String.trim()
      |> case do
        "manual" -> "manual"
        _ -> "income_ratio"
      end

    if mode == "manual" do
      mine_amount = Map.get(attrs, "shared_manual_mine_amount", "")

      with {:ok, parsed_mine_cents} <- parse_quick_finance_amount_cents(mine_amount),
           true <- parsed_mine_cents >= 0 and parsed_mine_cents <= total_cents do
        %{
          "shared_split_mode" => "manual",
          "shared_manual_mine_cents" => parsed_mine_cents
        }
      else
        _ ->
          %{
            "shared_split_mode" => "manual",
            "shared_manual_mine_amount" => mine_amount
          }
      end
    else
      %{"shared_split_mode" => "income_ratio"}
    end
  end

  defp quick_share_validation_message(details) when is_map(details) do
    cond do
      Map.has_key?(details, :shared_manual_mine_cents) ->
        "no modo manual, informe um valor válido para você sem exceder o total"

      true ->
        "validação do compartilhamento falhou"
    end
  end

  defp quick_share_validation_message(_details), do: "validação do compartilhamento falhou"

  defp format_amount_input(cents) when is_integer(cents) and cents >= 0 do
    integer_part = cents |> div(100) |> Integer.to_string()
    decimal_part = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    integer_part <> "," <> decimal_part
  end

  defp parse_quick_share_link_id(value) do
    value
    |> to_string()
    |> String.trim()
    |> Integer.parse()
    |> case do
      {link_id, ""} when link_id > 0 -> {:ok, link_id}
      _ -> :error
    end
  end

  defp string_key_map(attrs) do
    Enum.reduce(attrs, %{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  defp default_if_blank(value, fallback) when is_binary(value) do
    if String.trim(value) == "", do: fallback, else: value
  end

  defp default_if_blank(nil, fallback), do: fallback
  defp default_if_blank(value, _fallback), do: value

  defp default_quick_finance_category("income"), do: "Salário"
  defp default_quick_finance_category(_kind), do: "Alimentação"

  defp default_quick_expense_profile("income"), do: ""
  defp default_quick_expense_profile(_kind), do: "variable"

  defp default_quick_payment_method("income"), do: ""
  defp default_quick_payment_method(_kind), do: "debit"

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

  defp generate_mixed_example do
    """
    tarefa: Revisar documentação do projeto
    finança: -50 Almoço executivo
    """
  end

  defp normalize_quick_task_priority(priority) do
    case to_string(priority) |> String.trim() do
      "low" -> "low"
      "high" -> "high"
      _ -> "medium"
    end
  end

  defp normalize_quick_task_status(status) do
    case to_string(status) |> String.trim() do
      "in_progress" -> "in_progress"
      "done" -> "done"
      _ -> "todo"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide={true}>
      <nav aria-label="Atalhos de navegação">
        <a href="#quick-finance-hero" class="skip-link">Ir para lançamento rápido</a>
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
        id="notification-permission-modal"
        phx-hook="NotificationPermissionModal"
        phx-update="ignore"
        data-remind-after-days="7"
        class="fixed inset-0 z-[75] hidden items-end justify-center bg-base-content/45 p-3 backdrop-blur-[1px] sm:items-center sm:p-6"
        aria-hidden="true"
      >
        <section
          id="notification-permission-dialog"
          role="dialog"
          aria-modal="true"
          aria-labelledby="notification-permission-title"
          class="w-full max-w-lg rounded-2xl border border-base-content/15 bg-base-100 p-5 shadow-[0_24px_70px_rgba(23,33,47,0.34)] sm:p-6"
        >
          <div class="flex items-start gap-3">
            <div class="mt-0.5 rounded-xl border border-info/30 bg-info/10 p-2 text-info">
              <.icon name="hero-bell-alert" class="size-5" />
            </div>

            <div class="space-y-1">
              <h2
                id="notification-permission-title"
                class="text-lg font-semibold leading-tight text-base-content"
              >
                Ativar notificações de foco
              </h2>
              <p class="text-sm leading-6 text-base-content/75">
                Queremos te avisar quando o Time Box concluir, mesmo com a aba em segundo plano.
              </p>
            </div>
          </div>

          <div class="mt-4 rounded-xl border border-base-content/12 bg-base-100/65 px-3 py-2.5">
            <p id="notification-permission-status" class="text-xs text-base-content/70">
              Clique em "Ativar notificações" para permitir alertas no navegador.
            </p>
          </div>

          <div class="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
            <button
              id="notification-permission-later"
              type="button"
              class="btn btn-ghost btn-sm sm:btn-md"
            >
              Agora não
            </button>
            <button
              id="notification-permission-allow"
              type="button"
              class="btn btn-primary btn-sm sm:btn-md"
            >
              Ativar notificações
            </button>
          </div>
        </section>
      </div>

      <div
        id="dashboard-keyboard-shortcuts"
        class="dashboard-shell flex flex-col gap-4 lg:gap-6"
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

        <QuickFinanceHero.quick_finance_hero
          quick_finance_form={@quick_finance_form}
          quick_finance_kind={@quick_finance_kind}
          account_links={@account_links}
          current_user_id={@current_scope.user.id}
        />

        <QuickTaskHero.quick_task_hero quick_task_form={@quick_task_form} />

        <div id="bulk-import-legacy" class="hidden" aria-hidden="true">
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
        </div>

        <OperationsPanel.operations_panel
          streams={@streams}
          ops_tab={@ops_tab}
          task_filters={@task_filters}
          finance_filters={@finance_filters}
          editing_task_id={@editing_task_id}
          editing_finance_id={@editing_finance_id}
          ops_counts={@ops_counts}
        />

        <AnalyticsPanel.analytics_panel
          analytics_filters={@analytics_filters}
          insights_overview={@insights_overview}
          workload_capacity_snapshot={@workload_capacity_snapshot}
          progress_chart={@progress_chart}
          finance_trend_chart={@finance_trend_chart}
          finance_category_chart={@finance_category_chart}
          task_priority_chart={@task_priority_chart}
          finance_mix_chart={@finance_mix_chart}
          analytics_highlights={@analytics_highlights}
          ops_counts={@ops_counts}
        />
      </div>
    </Layouts.app>
    """
  end
end
