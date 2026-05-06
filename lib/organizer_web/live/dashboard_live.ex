defmodule OrganizerWeb.DashboardLive do
  use OrganizerWeb, :live_view

  alias Organizer.Accounts
  alias Organizer.DateSupport
  alias Organizer.Planning
  alias Organizer.Planning.AmountParser
  alias Organizer.Repo
  alias Organizer.SharedFinance
  alias OrganizerWeb.DashboardLive.{Filters, Insights}
  alias OrganizerWeb.{FlashFeedback, FunnelTelemetry}

  alias OrganizerWeb.DashboardLive.Components.{
    FinanceMetricsPanel,
    FinanceOperationsPanel,
    PlanningOperationsPanel
  }

  alias OrganizerWeb.Components.QuickFinanceHero

  @finance_metrics_days_filters ["7", "30", "90", "365"]
  @finance_page_size 10

  @impl true
  def mount(_params, _session, socket) do
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
        {:ok, redirect(socket, to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :page_title, page_title(:finances))}
  end

  @impl true
  def handle_event("quick_finance_validate", %{"quick_finance" => attrs}, socket) do
    normalized = normalize_quick_finance_attrs(attrs, socket.assigns.account_links)

    {:noreply,
     socket
     |> assign(:quick_finance_kind, normalized["kind"])
     |> assign(:quick_finance_preset, nil)
     |> assign(:quick_finance_form, to_form(normalized, as: :quick_finance))}
  end

  @impl true
  def handle_event("quick_finance_preset", %{"preset" => preset}, socket) do
    preset_attrs = quick_finance_preset_attrs(preset)
    normalized = normalize_quick_finance_attrs(preset_attrs, socket.assigns.account_links)

    {:noreply,
     socket
     |> assign(:quick_finance_kind, normalized["kind"])
     |> assign(:quick_finance_preset, preset)
     |> assign(:quick_finance_form, to_form(normalized, as: :quick_finance))}
  end

  @impl true
  def handle_event("create_quick_finance", %{"quick_finance" => attrs}, socket) do
    normalized =
      normalize_quick_finance_attrs(attrs, socket.assigns.account_links, parse_amount?: true)

    track_funnel(:quick_finance_create, :start)

    case create_quick_finance_entry(socket.assigns.current_scope, normalized) do
      {:ok, _entry, share_result} ->
        kind = normalized["kind"]
        reset_form = quick_finance_defaults(kind, socket.assigns.account_links)
        track_funnel(:quick_finance_create, :success, %{shared: share_result == :shared})

        {happened, next_step} =
          case share_result do
            :shared ->
              {"Lançamento registrado e compartilhado no vínculo selecionado",
               "Acompanhe o saldo atualizado na seção de colaboração"}

            :not_shared ->
              {"Lançamento registrado",
               "Revise os detalhes na lista abaixo e ajuste se necessário"}
          end

        {:noreply,
         socket
         |> assign(:quick_finance_kind, kind)
         |> assign(:quick_finance_preset, default_quick_finance_preset(kind))
         |> assign(:quick_finance_form, to_form(reset_form, as: :quick_finance))
         |> info_feedback(happened, next_step)
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

      {:error, {:validation, details}} ->
        track_funnel(:quick_finance_create, :error, %{reason: "validation"})

        {:noreply,
         socket
         |> assign(:quick_finance_kind, normalized["kind"])
         |> assign(:quick_finance_form, to_form(normalized, as: :quick_finance))
         |> error_feedback(
           quick_finance_creation_error_message(details),
           quick_finance_creation_error_next_step(details)
         )}

      _ ->
        track_funnel(:quick_finance_create, :error, %{reason: "unexpected"})

        {:noreply,
         socket
         |> assign(:quick_finance_kind, normalized["kind"])
         |> assign(:quick_finance_form, to_form(normalized, as: :quick_finance))
         |> error_feedback(
           "Não foi possível registrar o lançamento",
           "Tente novamente em instantes"
         )}
    end
  end

  @impl true
  def handle_event("filter_finances", %{"filters" => filters}, socket) do
    finance_filters =
      socket.assigns.finance_filters
      |> Map.merge(Filters.normalize_finance_filters(filters))
      |> Map.put(:page, 1)
      |> Filters.sanitize_finance_filters()

    {:noreply,
     socket
     |> assign(:finance_filters, finance_filters)
     |> assign(:finance_loading_more?, false)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("load_more_finances", params, socket) do
    cond do
      socket.assigns.finance_loading_more? ->
        {:noreply, socket}

      not socket.assigns.finance_has_more? ->
        {:noreply, socket}

      true ->
        current_page = Map.get(socket.assigns.finance_filters, :page, 1)

        page_number =
          case Integer.parse(to_string(Map.get(params, "page", current_page + 1))) do
            {value, ""} when value > 0 -> value
            _ -> current_page + 1
          end

        finance_filters =
          socket.assigns.finance_filters
          |> Map.put(:page, page_number)
          |> Filters.sanitize_finance_filters()

        {:noreply,
         socket
         |> assign(:finance_filters, finance_filters)
         |> assign(:finance_loading_more?, true)
         |> load_operation_collections(reset: false)}
    end
  end

  @impl true
  def handle_event("set_finance_metrics_days", %{"days" => days}, socket)
      when days in @finance_metrics_days_filters do
    finance_metrics_filters =
      socket.assigns.finance_metrics_filters
      |> Map.put(:days, days)
      |> Filters.sanitize_finance_metrics_filters()

    {:noreply,
     socket
     |> assign(:finance_metrics_filters, finance_metrics_filters)
     |> assign(:finance_flow_chart, %{loading: true, chart_svg: nil})
     |> assign(:finance_category_chart, %{loading: true, chart_svg: nil})
     |> assign(:finance_composition_chart, %{loading: true, chart_svg: nil})
     |> load_chart_svgs()}
  end

  @impl true
  def handle_event("create_fixed_cost", %{"fixed_cost" => attrs}, socket) do
    normalized = normalize_fixed_cost_attrs(attrs)

    track_funnel(:fixed_cost_create, :start)

    case Planning.create_fixed_cost(socket.assigns.current_scope, normalized) do
      {:ok, _cost} ->
        track_funnel(:fixed_cost_create, :success)

        {:noreply,
         socket
         |> assign(:fixed_cost_form, to_form(fixed_cost_defaults(), as: :fixed_cost))
         |> load_planning_collections()
         |> info_feedback(
           "Custo fixo salvo com sucesso",
           "Confira se ele já aparece na lista de planejamento"
         )}

      {:error, {:validation, _details}} ->
        track_funnel(:fixed_cost_create, :error, %{reason: "validation"})

        {:noreply,
         socket
         |> assign(:fixed_cost_form, to_form(normalized, as: :fixed_cost))
         |> error_feedback(
           "Verifique os campos do custo fixo",
           "Corrija os campos destacados e tente salvar novamente"
         )}

      _ ->
        track_funnel(:fixed_cost_create, :error, %{reason: "unexpected"})

        {:noreply,
         error_feedback(
           socket,
           "Não foi possível salvar o custo fixo",
           "Tente novamente em instantes"
         )}
    end
  end

  @impl true
  def handle_event("start_edit_fixed_cost", %{"id" => id}, socket) do
    case Planning.get_fixed_cost(socket.assigns.current_scope, id) do
      {:ok, cost} ->
        {:noreply,
         socket
         |> assign(:fixed_cost_edit_entry, cost)
         |> assign(
           :fixed_cost_edit_form,
           to_form(fixed_cost_form_params(cost), as: :fixed_cost_edit)
         )}

      {:error, :not_found} ->
        {:noreply,
         error_feedback(
           socket,
           "Custo fixo não encontrado",
           "Atualize a página para recarregar a lista e tente novamente"
         )}

      _ ->
        {:noreply,
         error_feedback(
           socket,
           "Não foi possível carregar o custo fixo",
           "Atualize a página e tente novamente"
         )}
    end
  end

  @impl true
  def handle_event("cancel_edit_fixed_cost", _params, socket) do
    {:noreply,
     socket
     |> assign(:fixed_cost_edit_entry, nil)
     |> assign(:fixed_cost_edit_form, to_form(%{}, as: :fixed_cost_edit))}
  end

  @impl true
  def handle_event("save_fixed_cost", %{"_id" => id, "fixed_cost_edit" => attrs}, socket) do
    normalized = normalize_fixed_cost_attrs(attrs)

    track_funnel(:fixed_cost_update, :start)

    case Planning.update_fixed_cost(socket.assigns.current_scope, id, normalized) do
      {:ok, _cost} ->
        track_funnel(:fixed_cost_update, :success)

        {:noreply,
         socket
         |> assign(:fixed_cost_edit_entry, nil)
         |> assign(:fixed_cost_edit_form, to_form(%{}, as: :fixed_cost_edit))
         |> load_planning_collections()
         |> info_feedback(
           "Custo fixo atualizado",
           "Revise a lista para garantir que os dados ficaram corretos"
         )}

      {:error, {:validation, _details}} ->
        track_funnel(:fixed_cost_update, :error, %{reason: "validation"})

        {:noreply,
         socket
         |> assign(:fixed_cost_edit_form, to_form(normalized, as: :fixed_cost_edit))
         |> error_feedback(
           "Verifique os campos do custo fixo",
           "Corrija os campos destacados e salve novamente"
         )}

      {:error, :not_found} ->
        track_funnel(:fixed_cost_update, :error, %{reason: "not_found"})

        {:noreply,
         socket
         |> assign(:fixed_cost_edit_entry, nil)
         |> assign(:fixed_cost_edit_form, to_form(%{}, as: :fixed_cost_edit))
         |> error_feedback(
           "Custo fixo não encontrado",
           "Atualize a página para recarregar os dados"
         )}

      _ ->
        track_funnel(:fixed_cost_update, :error, %{reason: "unexpected"})

        {:noreply,
         error_feedback(
           socket,
           "Não foi possível atualizar o custo fixo",
           "Tente novamente em instantes"
         )}
    end
  end

  @impl true
  def handle_event("prompt_delete_fixed_cost", %{"id" => id}, socket) do
    track_funnel(:fixed_cost_delete, :start)
    {:noreply, prepare_fixed_cost_delete_confirmation(socket, id)}
  end

  @impl true
  def handle_event("cancel_delete_fixed_cost", _params, socket) do
    track_funnel(:fixed_cost_delete, :cancel)
    {:noreply, assign(socket, :pending_fixed_cost_delete, nil)}
  end

  @impl true
  def handle_event("confirm_delete_fixed_cost", _params, socket) do
    case socket.assigns.pending_fixed_cost_delete do
      %{id: id} ->
        {:noreply, perform_fixed_cost_deletion(socket, id)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("create_important_date", %{"important_date" => attrs}, socket) do
    normalized = normalize_important_date_attrs(attrs)

    track_funnel(:important_date_create, :start)

    case Planning.create_important_date(socket.assigns.current_scope, normalized) do
      {:ok, _important_date} ->
        track_funnel(:important_date_create, :success)

        {:noreply,
         socket
         |> assign(:important_date_form, to_form(important_date_defaults(), as: :important_date))
         |> load_planning_collections()
         |> info_feedback(
           "Data importante salva com sucesso",
           "Confira se ela já aparece na linha do tempo de planejamento"
         )}

      {:error, {:validation, _details}} ->
        track_funnel(:important_date_create, :error, %{reason: "validation"})

        {:noreply,
         socket
         |> assign(:important_date_form, to_form(normalized, as: :important_date))
         |> error_feedback(
           "Verifique os campos da data importante",
           "Corrija os campos destacados e tente salvar novamente"
         )}

      _ ->
        track_funnel(:important_date_create, :error, %{reason: "unexpected"})

        {:noreply,
         error_feedback(
           socket,
           "Não foi possível salvar a data importante",
           "Tente novamente em instantes"
         )}
    end
  end

  @impl true
  def handle_event("start_edit_important_date", %{"id" => id}, socket) do
    case Planning.get_important_date(socket.assigns.current_scope, id) do
      {:ok, important_date} ->
        {:noreply,
         socket
         |> assign(:important_date_edit_entry, important_date)
         |> assign(
           :important_date_edit_form,
           to_form(important_date_form_params(important_date), as: :important_date_edit)
         )}

      {:error, :not_found} ->
        {:noreply,
         error_feedback(
           socket,
           "Data importante não encontrada",
           "Atualize a página para recarregar a lista e tente novamente"
         )}

      _ ->
        {:noreply,
         error_feedback(
           socket,
           "Não foi possível carregar a data importante",
           "Atualize a página e tente novamente"
         )}
    end
  end

  @impl true
  def handle_event("cancel_edit_important_date", _params, socket) do
    {:noreply,
     socket
     |> assign(:important_date_edit_entry, nil)
     |> assign(:important_date_edit_form, to_form(%{}, as: :important_date_edit))}
  end

  @impl true
  def handle_event(
        "save_important_date",
        %{"_id" => id, "important_date_edit" => attrs},
        socket
      ) do
    normalized = normalize_important_date_attrs(attrs)

    track_funnel(:important_date_update, :start)

    case Planning.update_important_date(socket.assigns.current_scope, id, normalized) do
      {:ok, _important_date} ->
        track_funnel(:important_date_update, :success)

        {:noreply,
         socket
         |> assign(:important_date_edit_entry, nil)
         |> assign(:important_date_edit_form, to_form(%{}, as: :important_date_edit))
         |> load_planning_collections()
         |> info_feedback(
           "Data importante atualizada",
           "Revise a linha do tempo para validar os detalhes"
         )}

      {:error, {:validation, _details}} ->
        track_funnel(:important_date_update, :error, %{reason: "validation"})

        {:noreply,
         socket
         |> assign(:important_date_edit_form, to_form(normalized, as: :important_date_edit))
         |> error_feedback(
           "Verifique os campos da data importante",
           "Corrija os campos destacados e salve novamente"
         )}

      {:error, :not_found} ->
        track_funnel(:important_date_update, :error, %{reason: "not_found"})

        {:noreply,
         socket
         |> assign(:important_date_edit_entry, nil)
         |> assign(:important_date_edit_form, to_form(%{}, as: :important_date_edit))
         |> error_feedback(
           "Data importante não encontrada",
           "Atualize a página para recarregar os dados"
         )}

      _ ->
        track_funnel(:important_date_update, :error, %{reason: "unexpected"})

        {:noreply,
         error_feedback(
           socket,
           "Não foi possível atualizar a data importante",
           "Tente novamente em instantes"
         )}
    end
  end

  @impl true
  def handle_event("prompt_delete_important_date", %{"id" => id}, socket) do
    track_funnel(:important_date_delete, :start)
    {:noreply, prepare_important_date_delete_confirmation(socket, id)}
  end

  @impl true
  def handle_event("cancel_delete_important_date", _params, socket) do
    track_funnel(:important_date_delete, :cancel)
    {:noreply, assign(socket, :pending_important_date_delete, nil)}
  end

  @impl true
  def handle_event("confirm_delete_important_date", _params, socket) do
    case socket.assigns.pending_important_date_delete do
      %{id: id} ->
        {:noreply, perform_important_date_deletion(socket, id)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("next_onboarding_step", _params, socket) do
    current_step = socket.assigns.onboarding_step
    new_step = min(current_step + 1, 6)

    case Accounts.get_or_create_onboarding_progress(socket.assigns.current_scope.user) do
      {:ok, progress} ->
        case Accounts.advance_onboarding_step(progress) do
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
    case Accounts.get_or_create_onboarding_progress(socket.assigns.current_scope.user) do
      {:ok, progress} ->
        case Accounts.dismiss_onboarding(progress) do
          {:ok, _} ->
            {:noreply, assign(socket, :onboarding_active, false)}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:onboarding_active, false)
             |> error_feedback(
               "Não foi possível salvar sua preferência de onboarding",
               "Tente novamente em instantes"
             )}
        end

      {:error, _} ->
        {:noreply, assign(socket, :onboarding_active, false)}
    end
  end

  @impl true
  def handle_event("complete_onboarding", _params, socket) do
    case Accounts.get_or_create_onboarding_progress(socket.assigns.current_scope.user) do
      {:ok, progress} ->
        case Accounts.complete_onboarding(progress) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:onboarding_active, false)
             |> info_feedback(
               "Onboarding concluído",
               "Use os atalhos e blocos da página para acelerar sua rotina"
             )}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:onboarding_active, false)
             |> error_feedback(
               "Não foi possível salvar sua preferência de onboarding",
               "Tente novamente em instantes"
             )}
        end

      {:error, _} ->
        {:noreply, assign(socket, :onboarding_active, false)}
    end
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
         |> info_feedback(
           "Atalhos disponíveis: Alt+B (lançamento rápido) e ? (ajuda)",
           "Use Alt+B para focar direto no formulário de lançamento"
         )}

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("start_edit_finance", %{"id" => id}, socket) do
    case Planning.get_finance_entry(socket.assigns.current_scope, id) do
      {:ok, entry} ->
        {:noreply,
         socket
         |> assign(:editing_finance_id, id)
         |> assign(:finance_edit_modal_entry, entry)}

      {:error, :not_found} ->
        {:noreply,
         error_feedback(
           socket,
           "Lançamento não encontrado",
           "Atualize a lista para sincronizar os dados"
         )}

      _ ->
        {:noreply,
         error_feedback(
           socket,
           "Não foi possível carregar o lançamento",
           "Tente novamente em instantes"
         )}
    end
  end

  @impl true
  def handle_event("cancel_edit_finance", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_finance_id, nil)
     |> assign(:finance_edit_modal_entry, nil)}
  end

  @impl true
  def handle_event("save_finance", %{"_id" => id, "finance" => attrs}, socket) do
    normalized = normalize_finance_edit_attrs(attrs)

    track_funnel(:finance_edit, :start)

    case Planning.update_finance_entry(socket.assigns.current_scope, id, normalized) do
      {:ok, _entry} ->
        track_funnel(:finance_edit, :success)

        {:noreply,
         socket
         |> info_feedback(
           "Lançamento atualizado",
           "Confira os totais e categorias para validar o impacto"
         )
         |> assign(:editing_finance_id, nil)
         |> assign(:finance_edit_modal_entry, nil)
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

      {:error, {:validation, _details}} ->
        track_funnel(:finance_edit, :error, %{reason: "validation"})

        {:noreply,
         error_feedback(
           socket,
           "Verifique os campos do lançamento",
           "Corrija os campos destacados e salve novamente"
         )}

      {:error, :not_found} ->
        track_funnel(:finance_edit, :error, %{reason: "not_found"})

        {:noreply,
         socket
         |> error_feedback(
           "Lançamento não encontrado",
           "Atualize a lista para sincronizar os dados"
         )
         |> assign(:editing_finance_id, nil)
         |> assign(:finance_edit_modal_entry, nil)}

      _ ->
        track_funnel(:finance_edit, :error, %{reason: "unexpected"})

        {:noreply,
         error_feedback(
           socket,
           "Não foi possível atualizar o lançamento",
           "Tente novamente em instantes"
         )}
    end
  end

  @impl true
  def handle_event("prompt_delete_finance", %{"id" => id}, socket) do
    track_funnel(:finance_delete, :start)
    {:noreply, prepare_finance_delete_confirmation(socket, id)}
  end

  @impl true
  def handle_event("cancel_delete_finance", _params, socket) do
    track_funnel(:finance_delete, :cancel)
    {:noreply, assign(socket, :pending_finance_delete, nil)}
  end

  @impl true
  def handle_event("confirm_delete_finance", _params, socket) do
    case socket.assigns.pending_finance_delete do
      %{id: id} ->
        {:noreply, perform_finance_deletion(socket, id)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_finance", %{"id" => id}, socket) do
    {:noreply,
     prepare_finance_delete_confirmation(socket, id)
     |> info_feedback(
       "Confirmação necessária para excluir o lançamento",
       "Revise os dados no modal e confirme para continuar"
     )}
  end

  defp initialize_dashboard_state(socket, scope) do
    {:ok, account_links} = SharedFinance.list_account_links(scope)

    {:ok, user_preferences} = Accounts.get_or_create_user_preferences(scope.user)
    {:ok, onboarding_progress} = Accounts.get_or_create_onboarding_progress(scope.user)

    onboarding_active =
      !user_preferences.onboarding_completed and !onboarding_progress.dismissed and
        is_nil(onboarding_progress.completed_at)

    socket
    |> assign(:current_scope, scope)
    |> assign(:quick_finance_kind, "expense")
    |> assign(:quick_finance_preset, "expense_variable")
    |> assign(
      :quick_finance_form,
      to_form(quick_finance_defaults("expense", account_links), as: :quick_finance)
    )
    |> assign(:account_links, account_links)
    |> assign(:finance_filters, Filters.default_finance_filters())
    |> assign(:finance_metrics_filters, Filters.default_finance_metrics_filters())
    |> assign(:finance_category_suggestions, %{income: [], expense: [], all: []})
    |> assign(:editing_finance_id, nil)
    |> assign(:finance_edit_modal_entry, nil)
    |> assign(:pending_finance_delete, nil)
    |> assign(:fixed_cost_form, to_form(fixed_cost_defaults(), as: :fixed_cost))
    |> assign(:important_date_form, to_form(important_date_defaults(), as: :important_date))
    |> assign(:fixed_cost_edit_entry, nil)
    |> assign(:fixed_cost_edit_form, to_form(%{}, as: :fixed_cost_edit))
    |> assign(:important_date_edit_entry, nil)
    |> assign(:important_date_edit_form, to_form(%{}, as: :important_date_edit))
    |> assign(:pending_fixed_cost_delete, nil)
    |> assign(:pending_important_date_delete, nil)
    |> assign(:fixed_costs, [])
    |> assign(:important_dates, [])
    |> assign(:onboarding_active, onboarding_active)
    |> assign(:onboarding_step, onboarding_progress.current_step)
    |> assign(:finance_flow_chart, %{loading: true, chart_svg: nil})
    |> assign(:finance_category_chart, %{loading: true, chart_svg: nil})
    |> assign(:finance_composition_chart, %{loading: true, chart_svg: nil})
    |> assign(:finance_highlights, Insights.default_finance_highlights())
    |> load_operation_collections()
    |> load_planning_collections()
    |> refresh_dashboard_insights()
  end

  defp load_operation_collections(socket, opts \\ []) do
    reset? = Keyword.get(opts, :reset, true)
    keep_page? = Keyword.get(opts, :keep_page, false)

    finance_filters =
      socket.assigns.finance_filters
      |> maybe_reset_finance_page(reset?, keep_page?)
      |> Map.put(:page_size, @finance_page_size)
      |> Filters.sanitize_finance_filters()

    {:ok, {finances, finance_meta}} =
      Planning.list_finance_entries_with_meta(socket.assigns.current_scope, finance_filters)

    finance_filters_without_pagination =
      finance_filters
      |> Map.drop([:page, :page_size, :limit, :offset, :first, :last, :before, :after])

    {:ok, finances_for_stats} =
      Planning.list_finance_entries(
        socket.assigns.current_scope,
        finance_filters_without_pagination
      )

    finance_category_suggestions =
      case Planning.list_finance_category_suggestions(socket.assigns.current_scope) do
        {:ok, suggestions} -> suggestions
        _ -> %{income: [], expense: [], all: []}
      end

    finance_income = Enum.filter(finances_for_stats, &(&1.kind == :income))
    finance_expenses = Enum.filter(finances_for_stats, &(&1.kind == :expense))
    finance_total = finance_meta.total_count || length(finances_for_stats)
    shared_finances_total = Enum.count(finances_for_stats, &is_integer(&1.shared_with_link_id))
    shared_links_active = length(socket.assigns.account_links)

    current_page = Map.get(finance_meta, :current_page, Map.get(finance_filters, :page, 1))

    visible_count =
      if reset? do
        length(finances)
      else
        Map.get(socket.assigns, :finance_visible_count, 0) + length(finances)
      end

    socket
    |> assign(:finance_filters, Map.put(finance_filters, :page, current_page))
    |> assign(:finance_meta, finance_meta)
    |> assign(:finance_next_page, current_page + 1)
    |> stream(:finances, finances, reset: reset?)
    |> assign(:finance_category_suggestions, finance_category_suggestions)
    |> assign(:finance_visible_count, visible_count)
    |> assign(:finance_has_more?, Map.get(finance_meta, :has_next_page?, false))
    |> assign(:finance_loading_more?, false)
    |> assign(:ops_counts, %{
      finances_total: finance_total,
      finances_income_total: length(finance_income),
      finances_expense_total: length(finance_expenses),
      finances_shared_total: shared_finances_total,
      finances_income_cents: Enum.reduce(finance_income, 0, &(&1.amount_cents + &2)),
      finances_expense_cents: Enum.reduce(finance_expenses, 0, &(&1.amount_cents + &2)),
      shared_links_active: shared_links_active,
      shared_total: shared_finances_total
    })
  end

  defp maybe_reset_finance_page(filters, true, false), do: Map.put(filters, :page, 1)
  defp maybe_reset_finance_page(filters, _reset?, _keep_page?), do: filters

  defp load_planning_collections(socket) do
    scope = socket.assigns.current_scope

    fixed_costs =
      case Planning.list_fixed_costs_with_meta(scope, %{page: 1, page_size: 200}) do
        {:ok, {items, _meta}} -> items
        _ -> []
      end

    important_dates =
      case Planning.list_important_dates_with_meta(scope, %{days: 365, page: 1, page_size: 200}) do
        {:ok, {items, _meta}} -> items
        _ -> []
      end

    socket
    |> assign(:fixed_costs, fixed_costs)
    |> assign(:important_dates, important_dates)
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
      "occurred_on" => DateSupport.format_pt_br(Date.utc_today()),
      "expense_profile" => default_quick_expense_profile(kind),
      "payment_method" => default_quick_payment_method(kind),
      "installment_number" => default_quick_installment_number(kind),
      "installments_count" => default_quick_installments_count(kind),
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
      |> Map.update!(
        "occurred_on",
        &default_if_blank(&1, DateSupport.format_pt_br(Date.utc_today()))
      )
      |> normalize_quick_finance_share_fields(kind, account_links)
      |> maybe_parse_quick_finance_amount(parse_amount?)

    if kind == "income" do
      merged
      |> Map.update!(
        "expense_profile",
        &default_if_blank(&1, default_quick_expense_profile(kind))
      )
      |> Map.put("payment_method", "")
      |> Map.put("installment_number", "")
      |> Map.put("installments_count", "")
    else
      merged
      |> Map.update!(
        "expense_profile",
        &default_if_blank(&1, default_quick_expense_profile(kind))
      )
      |> Map.update!("payment_method", &default_if_blank(&1, default_quick_payment_method(kind)))
      |> normalize_quick_finance_installments_fields()
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

  defp normalize_quick_finance_installments_fields(attrs) do
    payment_method =
      attrs
      |> Map.get("payment_method", "debit")
      |> to_string()
      |> String.trim()

    if payment_method == "credit" do
      installment_number =
        attrs
        |> Map.get("installment_number", "1")
        |> to_string()
        |> String.trim()
        |> case do
          "" -> "1"
          value -> value
        end

      installments_count =
        attrs
        |> Map.get("installments_count", "1")
        |> to_string()
        |> String.trim()
        |> case do
          "" -> "1"
          value -> value
        end

      attrs
      |> Map.put("installment_number", installment_number)
      |> Map.put("installments_count", installments_count)
    else
      attrs
      |> Map.put("installment_number", "")
      |> Map.put("installments_count", "")
    end
  end

  defp normalize_finance_edit_attrs(attrs) when is_map(attrs) do
    attrs
    |> string_key_map()
    |> maybe_parse_finance_edit_amount()
  end

  defp normalize_finance_edit_attrs(attrs), do: attrs

  defp normalize_fixed_cost_attrs(attrs) when is_map(attrs) do
    attrs
    |> string_key_map()
    |> Map.update("amount_cents", "", &normalize_money_input/1)
    |> Map.update("billing_day", "", &normalize_integer_input/1)
    |> Map.update("starts_on", "", &normalize_date_input/1)
    |> Map.update("active", "true", fn value ->
      if value in [true, "true", "1", "on"], do: "true", else: "false"
    end)
  end

  defp normalize_fixed_cost_attrs(attrs), do: attrs

  defp normalize_important_date_attrs(attrs) when is_map(attrs) do
    attrs
    |> string_key_map()
    |> Map.update("date", "", &normalize_date_input/1)
  end

  defp normalize_important_date_attrs(attrs), do: attrs

  defp normalize_money_input(value) when is_binary(value) do
    case AmountParser.parse(String.trim(value)) do
      {:ok, cents} -> Integer.to_string(cents)
      _ -> value
    end
  end

  defp normalize_money_input(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_money_input(value), do: value

  defp normalize_integer_input(value) when is_binary(value) do
    value
    |> String.trim()
  end

  defp normalize_integer_input(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_integer_input(value), do: value

  defp normalize_date_input(value) when is_binary(value) do
    case DateSupport.parse_date(value) do
      {:ok, date} -> DateSupport.format_pt_br(date)
      :error -> String.trim(value)
    end
  end

  defp normalize_date_input(%Date{} = value), do: DateSupport.format_pt_br(value)
  defp normalize_date_input(value), do: value

  defp fixed_cost_defaults do
    %{
      "name" => "",
      "amount_cents" => "",
      "billing_day" => "",
      "starts_on" => "",
      "active" => "true"
    }
  end

  defp important_date_defaults do
    %{
      "title" => "",
      "category" => "personal",
      "date" => DateSupport.format_pt_br(Date.utc_today()),
      "notes" => ""
    }
  end

  defp fixed_cost_form_params(cost) do
    %{
      "name" => cost.name || "",
      "amount_cents" => format_amount_input(cost.amount_cents),
      "billing_day" =>
        if(is_integer(cost.billing_day), do: Integer.to_string(cost.billing_day), else: ""),
      "starts_on" => DateSupport.format_pt_br(cost.starts_on),
      "active" => if(cost.active, do: "true", else: "false")
    }
  end

  defp important_date_form_params(important_date) do
    %{
      "title" => important_date.title || "",
      "category" => to_string(important_date.category || :personal),
      "date" => DateSupport.format_pt_br(important_date.date),
      "notes" => important_date.notes || ""
    }
  end

  defp perform_fixed_cost_deletion(socket, id) do
    case Planning.delete_fixed_cost(socket.assigns.current_scope, id) do
      {:ok, _cost} ->
        track_funnel(:fixed_cost_delete, :success)

        socket
        |> assign(:pending_fixed_cost_delete, nil)
        |> load_planning_collections()
        |> info_feedback(
          "Custo fixo removido",
          "Revise o planejamento para ajustar possíveis impactos"
        )

      {:error, :not_found} ->
        track_funnel(:fixed_cost_delete, :error, %{reason: "not_found"})

        socket
        |> assign(:pending_fixed_cost_delete, nil)
        |> error_feedback(
          "Custo fixo não encontrado",
          "Atualize a lista para sincronizar os dados"
        )

      _ ->
        track_funnel(:fixed_cost_delete, :error, %{reason: "unexpected"})

        socket
        |> assign(:pending_fixed_cost_delete, nil)
        |> error_feedback("Não foi possível remover o custo fixo", "Tente novamente em instantes")
    end
  end

  defp perform_important_date_deletion(socket, id) do
    case Planning.delete_important_date(socket.assigns.current_scope, id) do
      {:ok, _important_date} ->
        track_funnel(:important_date_delete, :success)

        socket
        |> assign(:pending_important_date_delete, nil)
        |> load_planning_collections()
        |> info_feedback(
          "Data importante removida",
          "Confira a linha do tempo para validar os próximos marcos"
        )

      {:error, :not_found} ->
        track_funnel(:important_date_delete, :error, %{reason: "not_found"})

        socket
        |> assign(:pending_important_date_delete, nil)
        |> error_feedback(
          "Data importante não encontrada",
          "Atualize a lista para sincronizar os dados"
        )

      _ ->
        track_funnel(:important_date_delete, :error, %{reason: "unexpected"})

        socket
        |> assign(:pending_important_date_delete, nil)
        |> error_feedback(
          "Não foi possível remover a data importante",
          "Tente novamente em instantes"
        )
    end
  end

  defp maybe_parse_finance_edit_amount(attrs) do
    case parse_quick_finance_amount_cents(Map.get(attrs, "amount_cents")) do
      {:ok, cents} -> Map.put(attrs, "amount_cents", Integer.to_string(cents))
      :error -> attrs
    end
  end

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

  defp create_quick_finance_entry(scope, attrs) do
    if quick_finance_share_enabled?(attrs) do
      create_quick_finance_entry_with_share(scope, attrs)
    else
      case Planning.create_finance_entry(scope, attrs) do
        {:ok, entry} -> {:ok, entry, :not_shared}
        {:error, _reason} = error -> error
      end
    end
  end

  defp quick_finance_share_enabled?(%{"kind" => "expense"} = attrs),
    do: truthy_quick_finance_value?(Map.get(attrs, "share_with_link"))

  defp quick_finance_share_enabled?(_attrs), do: false

  defp create_quick_finance_entry_with_share(scope, attrs) do
    with {:ok, link_id} <- parse_quick_share_link_id(Map.get(attrs, "shared_with_link_id")) do
      Repo.transaction(fn ->
        with {:ok, entry} <- Planning.create_finance_entry(scope, attrs),
             share_attrs = build_quick_share_attrs(attrs, entry.amount_cents),
             {:ok, shared_entry} <-
               SharedFinance.share_finance_entry(scope, entry.id, link_id, share_attrs,
                 broadcast?: false
               ) do
          {entry, shared_entry}
        else
          {:error, _reason} = error ->
            Repo.rollback(error)
        end
      end)
      |> case do
        {:ok, {entry, shared_entry}} ->
          :ok = SharedFinance.broadcast_shared_entry_updated(shared_entry)
          {:ok, entry, :shared}

        {:error, _reason} = error ->
          error
      end
    else
      :error ->
        {:error, {:validation, %{shared_with_link_id: ["is invalid"]}}}
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

  defp quick_finance_creation_error_message(details) when is_map(details) do
    cond do
      Map.has_key?(details, :shared_manual_mine_cents) ->
        "No modo manual, informe um valor válido para você sem exceder o total."

      Map.has_key?(details, :shared_with_link_id) ->
        "Selecione um compartilhamento válido para registrar o lançamento."

      true ->
        "Verifique os campos para registrar o lançamento."
    end
  end

  defp quick_finance_creation_error_message(_details),
    do: "Não foi possível registrar o lançamento"

  defp quick_finance_creation_error_next_step(details) when is_map(details) do
    cond do
      Map.has_key?(details, :shared_manual_mine_cents) ->
        "Ajuste os valores manuais para manter a divisão dentro do total"

      Map.has_key?(details, :shared_with_link_id) ->
        "Escolha um vínculo válido antes de compartilhar"

      true ->
        "Corrija os campos destacados e tente novamente"
    end
  end

  defp quick_finance_creation_error_next_step(_details), do: "Tente novamente em instantes"

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

  defp parse_positive_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> :error
    end
  end

  defp parse_positive_id(_), do: :error

  defp prepare_finance_delete_confirmation(socket, id) do
    with {:ok, parsed_id} <- parse_positive_id(id),
         {:ok, entry} <- Planning.get_finance_entry(socket.assigns.current_scope, parsed_id) do
      assign(socket, :pending_finance_delete, %{
        id: entry.id,
        category: default_if_blank(entry.category, "Lançamento sem categoria")
      })
    else
      {:error, :not_found} ->
        error_feedback(
          socket,
          "Lançamento não encontrado",
          "Atualize a lista para sincronizar os dados"
        )

      :error ->
        error_feedback(
          socket,
          "Não foi possível preparar a exclusão do lançamento",
          "Tente novamente em instantes"
        )

      _ ->
        error_feedback(
          socket,
          "Não foi possível preparar a exclusão do lançamento",
          "Tente novamente em instantes"
        )
    end
  end

  defp prepare_fixed_cost_delete_confirmation(socket, id) do
    with {:ok, parsed_id} <- parse_positive_id(id),
         {:ok, cost} <- Planning.get_fixed_cost(socket.assigns.current_scope, parsed_id) do
      assign(socket, :pending_fixed_cost_delete, %{
        id: cost.id,
        name: default_if_blank(cost.name, "Custo fixo")
      })
    else
      {:error, :not_found} ->
        error_feedback(
          socket,
          "Custo fixo não encontrado",
          "Atualize a lista para sincronizar os dados"
        )

      :error ->
        error_feedback(
          socket,
          "Não foi possível preparar a exclusão do custo fixo",
          "Tente novamente em instantes"
        )

      _ ->
        error_feedback(
          socket,
          "Não foi possível preparar a exclusão do custo fixo",
          "Tente novamente em instantes"
        )
    end
  end

  defp prepare_important_date_delete_confirmation(socket, id) do
    with {:ok, parsed_id} <- parse_positive_id(id),
         {:ok, important_date} <-
           Planning.get_important_date(socket.assigns.current_scope, parsed_id) do
      assign(socket, :pending_important_date_delete, %{
        id: important_date.id,
        title: default_if_blank(important_date.title, "Data importante")
      })
    else
      {:error, :not_found} ->
        error_feedback(
          socket,
          "Data importante não encontrada",
          "Atualize a lista para sincronizar os dados"
        )

      :error ->
        error_feedback(
          socket,
          "Não foi possível preparar a exclusão da data importante",
          "Tente novamente em instantes"
        )

      _ ->
        error_feedback(
          socket,
          "Não foi possível preparar a exclusão da data importante",
          "Tente novamente em instantes"
        )
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

  defp default_quick_expense_profile("income"), do: "variable"
  defp default_quick_expense_profile(_kind), do: "variable"

  defp default_quick_payment_method("income"), do: ""
  defp default_quick_payment_method(_kind), do: "debit"

  defp default_quick_installment_number("income"), do: ""
  defp default_quick_installment_number(_kind), do: "1"

  defp default_quick_installments_count("income"), do: ""
  defp default_quick_installments_count(_kind), do: "1"

  defp default_quick_finance_preset("income"), do: "income_salary"
  defp default_quick_finance_preset(_kind), do: "expense_variable"

  defp page_title(:finances), do: "Finanças"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide={true}>
      <nav aria-label="Atalhos de navegação">
        <a
          href="#quick-finance-hero"
          class="sr-only rounded-lg border border-cyan-300/45 bg-slate-900 px-3 py-2 text-xs font-semibold text-cyan-100 focus:not-sr-only focus:absolute focus:left-3 focus:top-3 focus:z-[120]"
        >
          Ir para finanças
        </a>
        <a
          href="#finance-operations-panel"
          class="sr-only rounded-lg border border-cyan-300/45 bg-slate-900 px-3 py-2 text-xs font-semibold text-cyan-100 focus:not-sr-only focus:absolute focus:left-3 focus:top-14 focus:z-[120]"
        >
          Ir para operação financeira
        </a>
        <a
          href="#finance-metrics-panel"
          class="sr-only rounded-lg border border-cyan-300/45 bg-slate-900 px-3 py-2 text-xs font-semibold text-cyan-100 focus:not-sr-only focus:absolute focus:left-3 focus:top-24 focus:z-[120]"
        >
          Ir para métricas financeiras
        </a>
      </nav>

      <OrganizerWeb.Components.OnboardingOverlay.onboarding_overlay
        active={@onboarding_active}
        current_step={@onboarding_step}
        total_steps={6}
        can_skip={true}
      />

      <div
        id="module-keyboard-shortcuts"
        class="dashboard-shell mx-auto flex w-full max-w-[88rem] flex-col gap-5 px-3 pb-10 sm:px-5 lg:gap-7 lg:px-8"
        phx-window-keydown="global_shortcut"
      >
        <.module_hero
          id="finances-page-hero"
          eyebrow="Finanças pessoais"
          title="Controle entradas, saídas e decisões do mês."
          description="Registre lançamentos, revise o fluxo financeiro e acompanhe categorias antes de abrir o contexto compartilhado."
          icon="hero-banknotes"
        />

        <QuickFinanceHero.quick_finance_hero
          quick_finance_form={@quick_finance_form}
          quick_finance_kind={@quick_finance_kind}
          quick_finance_preset={@quick_finance_preset}
          account_links={@account_links}
          current_user_id={@current_scope.user.id}
          category_suggestions={@finance_category_suggestions}
        />

        <FinanceOperationsPanel.finance_operations_panel
          streams={@streams}
          finance_filters={@finance_filters}
          finance_meta={@finance_meta}
          category_suggestions={@finance_category_suggestions}
          editing_finance_id={@editing_finance_id}
          finance_edit_modal_entry={@finance_edit_modal_entry}
          pending_finance_delete={@pending_finance_delete}
          ops_counts={@ops_counts}
          finance_visible_count={@finance_visible_count}
          finance_has_more?={@finance_has_more?}
          finance_loading_more?={@finance_loading_more?}
          finance_next_page={@finance_next_page}
        />

        <FinanceMetricsPanel.finance_metrics_panel
          finance_metrics_filters={@finance_metrics_filters}
          finance_highlights={@finance_highlights}
          finance_flow_chart={@finance_flow_chart}
          finance_category_chart={@finance_category_chart}
          finance_composition_chart={@finance_composition_chart}
        />

        <PlanningOperationsPanel.planning_operations_panel
          fixed_cost_form={@fixed_cost_form}
          important_date_form={@important_date_form}
          fixed_costs={@fixed_costs}
          important_dates={@important_dates}
          fixed_cost_edit_entry={@fixed_cost_edit_entry}
          fixed_cost_edit_form={@fixed_cost_edit_form}
          important_date_edit_entry={@important_date_edit_entry}
          important_date_edit_form={@important_date_edit_form}
          pending_fixed_cost_delete={@pending_fixed_cost_delete}
          pending_important_date_delete={@pending_important_date_delete}
        />
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :icon, :string, required: true

  defp module_hero(assigns) do
    ~H"""
    <header
      id={@id}
      class="neon-surface rounded-3xl border border-cyan-400/20 bg-slate-950/72 p-6 shadow-[0_24px_70px_-38px_rgba(34,211,238,0.7)] backdrop-blur-sm sm:p-7"
    >
      <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div class="max-w-3xl">
          <p class="text-xs font-semibold uppercase tracking-[0.16em] text-cyan-100/80">
            {@eyebrow}
          </p>
          <h1 class="mt-2 text-2xl font-black text-slate-50 sm:text-3xl">
            {@title}
          </h1>
          <p class="mt-2 text-sm leading-6 text-slate-300">
            {@description}
          </p>
        </div>
        <div class="flex size-12 items-center justify-center rounded-2xl border border-cyan-300/55 bg-cyan-400/14 text-cyan-100">
          <.icon name={@icon} class="size-6" />
        </div>
      </div>
    </header>
    """
  end

  defp perform_finance_deletion(socket, id) do
    case Planning.delete_finance_entry(socket.assigns.current_scope, id) do
      {:ok, _entry} ->
        track_funnel(:finance_delete, :success)

        socket
        |> info_feedback(
          "Lançamento removido",
          "Confira os totais e registre um novo lançamento se necessário"
        )
        |> assign(:editing_finance_id, nil)
        |> assign(:finance_edit_modal_entry, nil)
        |> assign(:pending_finance_delete, nil)
        |> load_operation_collections()
        |> refresh_dashboard_insights()

      {:error, :not_found} ->
        track_funnel(:finance_delete, :error, %{reason: "not_found"})

        socket
        |> assign(:pending_finance_delete, nil)
        |> error_feedback(
          "Lançamento não encontrado",
          "Atualize a lista para sincronizar os dados"
        )

      _ ->
        track_funnel(:finance_delete, :error, %{reason: "unexpected"})

        socket
        |> assign(:pending_finance_delete, nil)
        |> error_feedback("Não foi possível remover o lançamento", "Tente novamente em instantes")
    end
  end

  defp info_feedback(socket, happened, next_step) do
    put_flash(socket, :info, FlashFeedback.compose(happened, next_step))
  end

  defp error_feedback(socket, happened, next_step) do
    put_flash(socket, :error, FlashFeedback.compose(happened, next_step))
  end

  defp track_funnel(action, outcome, metadata \\ %{}) do
    FunnelTelemetry.track_step(:finances, action, outcome, metadata)
  end
end
