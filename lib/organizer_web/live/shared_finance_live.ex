defmodule OrganizerWeb.SharedFinanceLive do
  use OrganizerWeb, :live_view

  alias Contex.{Dataset, Plot}
  alias Organizer.DateSupport
  alias Organizer.Planning.AmountParser
  alias Organizer.SharedFinance
  alias Organizer.SharedFinance.{SettlementRecord, SplitCalculator}
  alias OrganizerWeb.{FlashFeedback, FunnelTelemetry}

  @global_filter_presets %{
    "default_window" => {-3, 3},
    "current_month" => {0, 0},
    "last_3_months" => {-2, 0},
    "last_6_months" => {-5, 0}
  }
  @global_filter_max_months 12
  @shared_entries_page_size 10
  @shared_entry_debts_page_size 10
  @settlement_records_page_size 10
  @impl true
  def mount(%{"link_id" => link_id_param} = params, _session, socket) do
    scope = socket.assigns.current_scope
    shared_entries_page = 1
    shared_entry_debts_page = 1
    settlement_records_page = 1
    shared_entries_filter_q = normalize_list_filter_q(Map.get(params, "shared_entries_q", ""))

    shared_entry_debts_filter_q =
      normalize_list_filter_q(Map.get(params, "shared_entry_debts_q", ""))

    settlement_records_filter_q =
      normalize_list_filter_q(Map.get(params, "settlement_records_q", ""))

    with {:ok, link_id} <- parse_int(link_id_param),
         {:ok, link} <- SharedFinance.get_account_link(scope, link_id) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Organizer.PubSub, "account_link:#{link_id}")
      end

      temporal_state = resolve_temporal_state(scope, link_id, params)
      range_params = shared_period_params(temporal_state)

      {:ok, {views, shared_entries_meta}} =
        SharedFinance.list_shared_entries_with_meta(scope, link_id, %{
          from: temporal_state.from_month,
          to: temporal_state.to_month,
          reference_date: temporal_state.to_month,
          page: shared_entries_page,
          page_size: @shared_entries_page_size,
          q: shared_entries_filter_q
        })

      {:ok, metrics} =
        SharedFinance.get_link_metrics(scope, link_id, temporal_state.to_month, range_params)

      {:ok, trend} = SharedFinance.get_recurring_variable_trend(scope, link_id, range_params)

      {:ok, cycle} =
        SharedFinance.get_or_create_settlement_cycle(
          scope,
          link_id,
          temporal_state.settlement_focus_month
        )

      {:ok, {debts, shared_entry_debts_meta}} =
        SharedFinance.list_shared_entry_debts_with_meta(scope, link_id, %{
          from: temporal_state.from_month,
          to: temporal_state.to_month,
          reference_date: temporal_state.to_month,
          page: shared_entry_debts_page,
          page_size: @shared_entry_debts_page_size,
          q: shared_entry_debts_filter_q
        })

      {:ok, {records, settlement_records_meta}} =
        SharedFinance.list_settlement_records_for_link_with_meta(scope, link_id, %{
          from: temporal_state.from_month,
          to: temporal_state.to_month,
          reference_date: temporal_state.to_month,
          page: settlement_records_page,
          page_size: @settlement_records_page_size,
          q: settlement_records_filter_q
        })

      {:ok, monthly_debt_summaries} =
        SharedFinance.monthly_debt_summaries(scope, link_id, %{
          from: temporal_state.from_month,
          to: temporal_state.to_month,
          reference_date: temporal_state.to_month
        })

      socket =
        socket
        |> assign(:link, link)
        |> assign(:link_id, link_id)
        |> assign(:global_filter_from_month, temporal_state.from_month)
        |> assign(:global_filter_to_month, temporal_state.to_month)
        |> assign(:settlement_focus_month, temporal_state.settlement_focus_month)
        |> assign(
          :settlement_focus_form,
          settlement_focus_form(temporal_state.settlement_focus_month)
        )
        |> assign(
          :global_filter_form,
          global_filter_form(temporal_state.from_month, temporal_state.to_month)
        )
        |> assign(:metrics, metrics)
        |> assign(:trend, trend)
        |> assign(:shared_balance_chart, shared_balance_chart_svg(metrics))
        |> assign(:shared_entries_count, shared_entries_meta.total_count || length(views))
        |> assign(:shared_entries_meta, shared_entries_meta)
        |> assign(:shared_entries_has_more?, Map.get(shared_entries_meta, :has_next_page?, false))
        |> assign(:shared_entries_loading_more?, false)
        |> assign(:shared_entries_next_page, shared_entries_page + 1)
        |> assign(:shared_entries_filter_q, shared_entries_filter_q)
        |> assign(
          :shared_entries_page,
          Map.get(shared_entries_meta, :current_page, shared_entries_page)
        )
        |> assign(:shared_entry_debts, debts)
        |> assign(:shared_entry_debts_count, shared_entry_debts_meta.total_count || length(debts))
        |> assign(:shared_entry_debts_meta, shared_entry_debts_meta)
        |> assign(
          :shared_entry_debts_has_more?,
          Map.get(shared_entry_debts_meta, :has_next_page?, false)
        )
        |> assign(:shared_entry_debts_loading_more?, false)
        |> assign(:shared_entry_debts_next_page, shared_entry_debts_page + 1)
        |> assign(:shared_entry_debts_filter_q, shared_entry_debts_filter_q)
        |> assign(
          :shared_entry_debts_page,
          Map.get(shared_entry_debts_meta, :current_page, shared_entry_debts_page)
        )
        |> assign(:settlement_cycle, cycle)
        |> assign(
          :settlement_records_count,
          settlement_records_meta.total_count || length(records)
        )
        |> assign(:settlement_records_meta, settlement_records_meta)
        |> assign(
          :settlement_records_has_more?,
          Map.get(settlement_records_meta, :has_next_page?, false)
        )
        |> assign(:settlement_records_loading_more?, false)
        |> assign(:settlement_records_next_page, settlement_records_page + 1)
        |> assign(:settlement_records_filter_q, settlement_records_filter_q)
        |> assign(
          :settlement_records_page,
          Map.get(settlement_records_meta, :current_page, settlement_records_page)
        )
        |> assign(:monthly_debt_summaries, monthly_debt_summaries)
        |> assign(:payment_form, payment_form())
        |> assign(:shared_entry_edit_entry, nil)
        |> assign(:shared_entry_edit_form, to_form(%{}, as: :shared_entry_edit))
        |> assign(:shared_entry_edit_preview, nil)
        |> assign(:pending_unshare_entry, nil)
        |> assign(:pending_settlement_record_reversal, nil)
        |> assign(:settlement_reversal_form, settlement_reversal_form())
        |> assign(:page_title, "Finanças Compartilhadas")
        |> stream_configure(:shared_entries, dom_id: &"shared-entry-view-#{&1.entry.id}")
        |> stream_configure(:settlement_records, dom_id: &"shared-settlement-record-#{&1.id}")
        |> stream(:shared_entries, views)
        |> stream(:settlement_records, records)

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> error_feedback(
           "Compartilhamento não encontrado",
           "Volte para a lista e selecione um vínculo ativo"
         )
         |> push_navigate(to: ~p"/account-links")}
    end
  end

  @impl true
  def handle_params(%{"link_id" => link_id_param} = params, _uri, socket) do
    case parse_int(link_id_param) do
      {:ok, link_id} ->
        scope = socket.assigns.current_scope
        temporal_state = resolve_temporal_state(scope, link_id, params)

        if temporal_state.patch_required? do
          patch_params =
            socket
            |> current_shared_finance_params()
            |> Map.merge(temporal_state.patch_params)

          {:noreply, push_patch(socket, to: ~p"/account-links/#{link_id}?#{patch_params}")}
        else
          _ =
            SharedFinance.upsert_view_preference(scope, link_id, %{
              from_year: temporal_state.from_month.year,
              from_month: temporal_state.from_month.month,
              to_year: temporal_state.to_month.year,
              to_month: temporal_state.to_month.month,
              settlement_focus_year: temporal_state.settlement_focus_month.year,
              settlement_focus_month: temporal_state.settlement_focus_month.month
            })

          clamp_flash? = temporal_state.clamped_settlement_focus?

          socket =
            socket
            |> maybe_info_feedback(
              clamp_flash?,
              "Competência ajustada ao período ativo",
              "O fechamento mensal foi alinhado ao mês final do filtro"
            )
            |> assign(:link_id, link_id)
            |> assign(:global_filter_from_month, temporal_state.from_month)
            |> assign(:global_filter_to_month, temporal_state.to_month)
            |> assign(:settlement_focus_month, temporal_state.settlement_focus_month)
            |> assign(
              :settlement_focus_form,
              settlement_focus_form(temporal_state.settlement_focus_month)
            )
            |> assign(
              :global_filter_form,
              global_filter_form(temporal_state.from_month, temporal_state.to_month)
            )
            |> assign(:shared_entries_page, 1)
            |> assign(:shared_entry_debts_page, 1)
            |> assign(:settlement_records_page, 1)
            |> assign(:shared_entries_loading_more?, false)
            |> assign(:shared_entry_debts_loading_more?, false)
            |> assign(:settlement_records_loading_more?, false)
            |> reload_shared_data()

          {:noreply, socket}
        end

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("prompt_unshare_entry", %{"entry_id" => entry_id}, socket) do
    track_funnel(:shared_entry_unshare, :start)
    {:noreply, prepare_unshare_entry_confirmation(socket, entry_id)}
  end

  @impl true
  def handle_event("cancel_unshare_entry", _params, socket) do
    track_funnel(:shared_entry_unshare, :cancel)
    {:noreply, assign(socket, :pending_unshare_entry, nil)}
  end

  @impl true
  def handle_event("confirm_unshare_entry", _params, socket) do
    case socket.assigns.pending_unshare_entry do
      %{id: entry_id} -> {:noreply, perform_unshare_entry(socket, entry_id)}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("unshare_entry", %{"entry_id" => entry_id}, socket) do
    track_funnel(:shared_entry_unshare, :start)

    {:noreply,
     prepare_unshare_entry_confirmation(socket, entry_id)
     |> info_feedback(
       "A remoção do compartilhamento precisa de confirmação",
       "Revise o lançamento e confirme para continuar"
     )}
  end

  @impl true
  def handle_event("open_shared_entry_edit", %{"entry_id" => entry_id}, socket) do
    scope = socket.assigns.current_scope
    link_id = socket.assigns.link_id
    from_month = socket.assigns.global_filter_from_month
    to_month = socket.assigns.global_filter_to_month

    with {:ok, parsed_entry_id} <- parse_int(entry_id),
         {:ok, view} <-
           shared_entry_view_for_edit(scope, link_id, from_month, to_month, parsed_entry_id),
         true <- view.entry.user_id == scope.user.id do
      form_params = shared_entry_edit_form_params(view)
      preview = shared_entry_preview_from_view(view)

      {:noreply,
       socket
       |> assign(:shared_entry_edit_entry, view.entry)
       |> assign(:shared_entry_edit_form, to_form(form_params, as: :shared_entry_edit))
       |> assign(:shared_entry_edit_preview, preview)}
    else
      false ->
        {:noreply,
         error_feedback(
           socket,
           "Você só pode editar lançamentos compartilhados da sua conta",
           "Selecione um lançamento criado por você"
         )}

      _ ->
        {:noreply,
         error_feedback(
           socket,
           "Não foi possível abrir a edição do lançamento",
           "Atualize a página e tente novamente"
         )}
    end
  end

  @impl true
  def handle_event("change_shared_entry_edit", %{"shared_entry_edit" => params}, socket) do
    normalized_params =
      normalize_shared_entry_edit_params(
        params,
        socket.assigns.shared_entry_edit_entry,
        socket.assigns.shared_entry_edit_preview
      )

    preview =
      build_shared_entry_preview(
        normalized_params,
        socket.assigns.shared_entry_edit_entry,
        socket.assigns.link,
        socket.assigns.current_scope.user.id,
        socket.assigns.shared_entry_edit_preview
      )

    enriched_params = enrich_shared_entry_form_params(normalized_params, preview)

    {:noreply,
     socket
     |> assign(:shared_entry_edit_form, to_form(enriched_params, as: :shared_entry_edit))
     |> assign(:shared_entry_edit_preview, preview)}
  end

  @impl true
  def handle_event("save_shared_entry_edit", %{"shared_entry_edit" => params}, socket) do
    scope = socket.assigns.current_scope
    entry = socket.assigns.shared_entry_edit_entry
    link_id = socket.assigns.link_id

    case entry do
      %{} ->
        case SharedFinance.update_shared_finance_entry(scope, link_id, entry.id, params) do
          {:ok, _updated_entry} ->
            {:noreply,
             socket
             |> info_feedback(
               "Lançamento compartilhado atualizado",
               "Confira o resumo para validar a nova divisão"
             )
             |> close_shared_entry_edit_modal()
             |> reload_shared_data()}

          {:error, {:validation, details}} ->
            normalized_params =
              normalize_shared_entry_edit_params(
                params,
                entry,
                socket.assigns.shared_entry_edit_preview
              )

            preview =
              build_shared_entry_preview(
                normalized_params,
                entry,
                socket.assigns.link,
                scope.user.id,
                socket.assigns.shared_entry_edit_preview
              )

            {:noreply,
             socket
             |> assign(
               :shared_entry_edit_form,
               to_form(enrich_shared_entry_form_params(normalized_params, preview),
                 as: :shared_entry_edit
               )
             )
             |> assign(:shared_entry_edit_preview, preview)
             |> error_feedback(
               shared_entry_edit_validation_message(details),
               "Ajuste os campos e tente salvar novamente"
             )}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> close_shared_entry_edit_modal()
             |> reload_shared_data()
             |> error_feedback(
               "Lançamento compartilhado não encontrado para edição",
               "Atualize a lista e escolha outro lançamento"
             )}

          _ ->
            {:noreply,
             error_feedback(
               socket,
               "Não foi possível atualizar o lançamento",
               "Tente novamente em alguns instantes"
             )}
        end

      _ ->
        {:noreply,
         error_feedback(
           socket,
           "Nenhum lançamento foi selecionado para edição",
           "Abra um lançamento e tente novamente"
         )}
    end
  end

  @impl true
  def handle_event("cancel_shared_entry_edit", _params, socket) do
    {:noreply, close_shared_entry_edit_modal(socket)}
  end

  @impl true
  def handle_event("apply_global_period_preset", %{"preset" => preset}, socket) do
    case preset_to_month_range(preset) do
      {:ok, from_month, to_month} ->
        apply_global_period_filter(socket, from_month, to_month)

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_global_period_filter", %{"period_filter" => period_filter}, socket) do
    from_value = Map.get(period_filter, "from_month", "")
    to_value = Map.get(period_filter, "to_month", "")

    case parse_global_filter_range(from_value, to_value) do
      {:ok, from_month, to_month} ->
        apply_global_period_filter(socket, from_month, to_month)

      {:error, :incomplete_range} ->
        {:noreply,
         assign(socket, :global_filter_form, to_form(period_filter, as: :period_filter))}

      {:error, :missing} ->
        {:noreply, socket}

      {:error, :invalid_month_range} ->
        {:noreply,
         error_feedback(
           socket,
           "Intervalo inválido para filtro temporal",
           "Selecione de 1 a #{@global_filter_max_months} meses com início menor ou igual ao fim"
         )}
    end
  end

  @impl true
  def handle_event(
        "change_settlement_focus_month",
        %{"settlement_filter" => %{"month" => month}},
        socket
      ) do
    case parse_month_param(month) do
      {:ok, focus_month} ->
        clamped_month =
          clamp_month_to_range(
            focus_month,
            socket.assigns.global_filter_from_month,
            socket.assigns.global_filter_to_month
          )

        _ =
          SharedFinance.upsert_view_preference(
            socket.assigns.current_scope,
            socket.assigns.link_id,
            %{
              settlement_focus_year: clamped_month.year,
              settlement_focus_month: clamped_month.month,
              from_year: socket.assigns.global_filter_from_month.year,
              from_month: socket.assigns.global_filter_from_month.month,
              to_year: socket.assigns.global_filter_to_month.year,
              to_month: socket.assigns.global_filter_to_month.month
            }
          )

        {:noreply,
         push_patch(socket,
           to:
             shared_finance_path(socket, %{
               "settlement_month" => format_month_param(clamped_month)
             })
         )}

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter_shared_entries", %{"filters" => filters}, socket) do
    filter_q =
      filters
      |> Map.get("q", "")
      |> normalize_list_filter_q()

    {:noreply,
     socket
     |> assign(:shared_entries_filter_q, filter_q)
     |> assign(:shared_entries_page, 1)
     |> assign(:shared_entries_loading_more?, false)
     |> reload_shared_data()}
  end

  @impl true
  def handle_event("load_more_shared_entries", params, socket) do
    cond do
      socket.assigns.shared_entries_loading_more? ->
        {:noreply, socket}

      not socket.assigns.shared_entries_has_more? ->
        {:noreply, socket}

      true ->
        next_page =
          params
          |> Map.get("page", socket.assigns.shared_entries_next_page)
          |> parse_positive_page()

        {:noreply,
         socket
         |> assign(:shared_entries_loading_more?, true)
         |> load_shared_entries(next_page, reset: false)}
    end
  end

  @impl true
  def handle_event("filter_shared_entry_debts", %{"filters" => filters}, socket) do
    filter_q =
      filters
      |> Map.get("q", "")
      |> normalize_list_filter_q()

    {:noreply,
     socket
     |> assign(:shared_entry_debts_filter_q, filter_q)
     |> assign(:shared_entry_debts_page, 1)
     |> assign(:shared_entry_debts_loading_more?, false)
     |> reload_shared_data()}
  end

  @impl true
  def handle_event("load_more_shared_entry_debts", params, socket) do
    cond do
      socket.assigns.shared_entry_debts_loading_more? ->
        {:noreply, socket}

      not socket.assigns.shared_entry_debts_has_more? ->
        {:noreply, socket}

      true ->
        next_page =
          params
          |> Map.get("page", socket.assigns.shared_entry_debts_next_page)
          |> parse_positive_page()

        {:noreply,
         socket
         |> assign(:shared_entry_debts_loading_more?, true)
         |> load_shared_entry_debts(next_page, reset: false)}
    end
  end

  @impl true
  def handle_event("filter_settlement_records", %{"filters" => filters}, socket) do
    filter_q =
      filters
      |> Map.get("q", "")
      |> normalize_list_filter_q()

    {:noreply,
     socket
     |> assign(:settlement_records_filter_q, filter_q)
     |> assign(:settlement_records_page, 1)
     |> assign(:settlement_records_loading_more?, false)
     |> reload_shared_data()}
  end

  @impl true
  def handle_event("load_more_settlement_records", params, socket) do
    cond do
      socket.assigns.settlement_records_loading_more? ->
        {:noreply, socket}

      not socket.assigns.settlement_records_has_more? ->
        {:noreply, socket}

      true ->
        next_page =
          params
          |> Map.get("page", socket.assigns.settlement_records_next_page)
          |> parse_positive_page()

        {:noreply,
         socket
         |> assign(:settlement_records_loading_more?, true)
         |> load_settlement_records(next_page, reset: false)}
    end
  end

  @impl true
  def handle_event("create_record", %{"payment" => attrs}, socket) do
    scope = socket.assigns.current_scope
    cycle = socket.assigns.settlement_cycle

    track_funnel(:settlement_record_create, :start)

    with {:ok, amount_cents} <- parse_amount_cents(Map.get(attrs, "amount_cents")),
         {:ok, method} <- parse_method(Map.get(attrs, "method")),
         {:ok, transferred_at} <- parse_transferred_at(Map.get(attrs, "transferred_at")),
         {:ok, targeted_debt_id} <-
           parse_optional_debt_id(Map.get(attrs, "shared_entry_debt_id")),
         {:ok, _record} <-
           create_settlement_record_for_target(scope, cycle.id, targeted_debt_id, %{
             amount_cents: amount_cents,
             method: method,
             transferred_at: transferred_at
           }) do
      success_message =
        if is_integer(targeted_debt_id) do
          "Pagamento direcionado registrado para o lançamento selecionado."
        else
          "Pagamento registrado e alocado nas dívidas em aberto."
        end

      track_funnel(:settlement_record_create, :success, %{targeted: is_integer(targeted_debt_id)})

      {:noreply,
       socket
       |> info_feedback(success_message, "Confira o saldo atualizado do vínculo")
       |> assign(:payment_form, payment_form())
       |> reload_shared_data()}
    else
      {:error, :invalid_amount} ->
        track_funnel(:settlement_record_create, :error, %{reason: "invalid_amount"})

        {:noreply,
         socket
         |> assign(:payment_form, payment_form(attrs))
         |> error_feedback(
           "Informe um valor válido maior que zero",
           "Preencha o valor e tente novamente"
         )}

      {:error, :invalid_method} ->
        track_funnel(:settlement_record_create, :error, %{reason: "invalid_method"})

        {:noreply,
         socket
         |> assign(:payment_form, payment_form(attrs))
         |> error_feedback(
           "Selecione um método de pagamento válido",
           "Escolha PIX, dinheiro ou transferência"
         )}

      {:error, :invalid_date} ->
        track_funnel(:settlement_record_create, :error, %{reason: "invalid_date"})

        {:noreply,
         socket
         |> assign(:payment_form, payment_form(attrs))
         |> error_feedback(
           "Informe uma data válida no formato dd/mm/aaaa",
           "Ajuste a data e tente novamente"
         )}

      {:error, :invalid_debt} ->
        track_funnel(:settlement_record_create, :error, %{reason: "invalid_debt"})

        {:noreply,
         socket
         |> assign(:payment_form, payment_form(attrs))
         |> error_feedback(
           "Selecione uma dívida válida para direcionar o pagamento",
           "Escolha uma dívida da lista e tente novamente"
         )}

      {:error, :not_found} ->
        track_funnel(:settlement_record_create, :error, %{reason: "not_found"})

        {:noreply,
         socket
         |> assign(:payment_form, payment_form(attrs))
         |> error_feedback(
           "A dívida selecionada não está disponível para pagamento",
           "Atualize a lista de dívidas e selecione outra opção"
         )}

      {:error, {:validation, %{amount_cents: _}}} ->
        track_funnel(:settlement_record_create, :error, %{reason: "amount_exceeds_outstanding"})

        {:noreply,
         socket
         |> assign(:payment_form, payment_form(attrs))
         |> error_feedback(
           "O valor informado excede o saldo permitido para pagamento",
           "Informe um valor menor ou igual ao saldo em aberto"
         )}

      {:error, _reason} ->
        track_funnel(:settlement_record_create, :error, %{reason: "unexpected"})

        {:noreply,
         error_feedback(
           socket,
           "Não foi possível registrar o pagamento",
           "Tente novamente em alguns instantes"
         )}
    end
  end

  @impl true
  def handle_event("prefill_payment_for_debt", %{"debt_id" => debt_id}, socket) do
    with {:ok, parsed_debt_id} <- parse_int(debt_id),
         {:ok, debt} <- debt_by_id(socket.assigns.shared_entry_debts, parsed_debt_id),
         true <- can_target_debt_payment?(debt, socket.assigns.current_scope.user.id) do
      params = %{
        "amount_cents" => format_amount_input(debt.outstanding_amount_cents),
        "method" => "pix",
        "transferred_at" => DateSupport.format_pt_br(Date.utc_today()),
        "shared_entry_debt_id" => Integer.to_string(debt.id)
      }

      {:noreply, assign(socket, :payment_form, payment_form(params))}
    else
      false ->
        {:noreply,
         error_feedback(
           socket,
           "Você só pode direcionar pagamentos para suas dívidas em aberto",
           "Selecione uma dívida na qual você seja o devedor"
         )}

      _ ->
        {:noreply,
         error_feedback(
           socket,
           "Não foi possível selecionar a dívida para pagamento",
           "Atualize a página e tente novamente"
         )}
    end
  end

  @impl true
  def handle_event("clear_payment_debt_target", _params, socket) do
    {:noreply, assign(socket, :payment_form, payment_form())}
  end

  @impl true
  def handle_event("prompt_reverse_settlement_record", %{"id" => id}, socket) do
    track_funnel(:settlement_record_reverse, :start)

    case parse_int(id) do
      {:ok, parsed_id} ->
        {:noreply,
         socket
         |> assign(:pending_settlement_record_reversal, %{id: parsed_id})
         |> assign(:settlement_reversal_form, settlement_reversal_form(%{"reason" => ""}))}

      :error ->
        track_funnel(:settlement_record_reverse, :error, %{reason: "invalid_id"})

        {:noreply,
         error_feedback(
           socket,
           "Não foi possível preparar o estorno",
           "Selecione um pagamento válido e tente novamente"
         )}
    end
  end

  @impl true
  def handle_event("cancel_reverse_settlement_record", _params, socket) do
    track_funnel(:settlement_record_reverse, :cancel)

    {:noreply,
     socket
     |> assign(:pending_settlement_record_reversal, nil)
     |> assign(:settlement_reversal_form, settlement_reversal_form())}
  end

  @impl true
  def handle_event(
        "confirm_reverse_settlement_record",
        %{"settlement_reversal" => params},
        socket
      ) do
    scope = socket.assigns.current_scope

    with {:ok, record_id} <- parse_int(Map.get(params, "id", "")) do
      case SharedFinance.reverse_settlement_record(scope, record_id, %{
             reason: Map.get(params, "reason", "")
           }) do
        {:ok, :reversed} ->
          track_funnel(:settlement_record_reverse, :success)

          {:noreply,
           socket
           |> assign(:pending_settlement_record_reversal, nil)
           |> assign(:settlement_reversal_form, settlement_reversal_form())
           |> info_feedback("Pagamento estornado com sucesso", "Confira o saldo do vínculo")
           |> reload_shared_data()}

        {:error, :already_reversed} ->
          track_funnel(:settlement_record_reverse, :error, %{reason: "already_reversed"})

          {:noreply,
           socket
           |> assign(:pending_settlement_record_reversal, nil)
           |> assign(:settlement_reversal_form, settlement_reversal_form())
           |> error_feedback(
             "Este pagamento já foi estornado",
             "Atualize a lista de pagamentos para conferir o status"
           )
           |> reload_shared_data()}

        {:error, :not_found} ->
          track_funnel(:settlement_record_reverse, :error, %{reason: "not_found"})

          {:noreply,
           socket
           |> assign(:pending_settlement_record_reversal, nil)
           |> assign(:settlement_reversal_form, settlement_reversal_form())
           |> error_feedback(
             "Pagamento não encontrado para estorno",
             "Atualize a lista e tente novamente"
           )
           |> reload_shared_data()}

        _ ->
          track_funnel(:settlement_record_reverse, :error, %{reason: "unexpected"})

          {:noreply,
           socket
           |> assign(:settlement_reversal_form, settlement_reversal_form(params))
           |> error_feedback("Não foi possível estornar o pagamento", "Tente novamente")}
      end
    else
      :error ->
        track_funnel(:settlement_record_reverse, :error, %{reason: "invalid_payload"})

        {:noreply,
         socket
         |> assign(:settlement_reversal_form, settlement_reversal_form(params))
         |> error_feedback(
           "Não foi possível identificar o pagamento para estorno",
           "Selecione um pagamento válido"
         )}
    end
  end

  @impl true
  def handle_event("confirm_settlement", _params, socket) do
    scope = socket.assigns.current_scope
    cycle = socket.assigns.settlement_cycle

    track_funnel(:settlement_confirm, :start)

    case SharedFinance.confirm_settlement(scope, cycle.id) do
      {:ok, _updated_cycle} ->
        track_funnel(:settlement_confirm, :success)

        {:noreply,
         socket
         |> info_feedback(
           "Confirmação bilateral concluída para o mês",
           "Acompanhe o próximo ciclo de pagamentos"
         )
         |> reload_shared_data()}

      {:error, :awaiting_counterpart_confirmation} ->
        track_funnel(:settlement_confirm, :success, %{status: "awaiting_counterpart_confirmation"})

        {:noreply,
         socket
         |> info_feedback(
           "Sua confirmação foi registrada",
           "Aguarde a confirmação da outra conta"
         )
         |> reload_shared_data()}

      {:error, :cycle_has_pending_debts} ->
        track_funnel(:settlement_confirm, :error, %{reason: "cycle_has_pending_debts"})

        {:noreply,
         error_feedback(
           socket,
           "Ainda há dívidas em aberto neste mês",
           "Quite as pendências antes de confirmar"
         )}

      {:error, _reason} ->
        track_funnel(:settlement_confirm, :error, %{reason: "unexpected"})

        {:noreply,
         error_feedback(
           socket,
           "Não foi possível confirmar o fechamento mensal",
           "Tente novamente em alguns instantes"
         )}
    end
  end

  @impl true
  def handle_info({:shared_entry_updated, _entry}, socket) do
    {:noreply, reload_shared_data(socket)}
  end

  @impl true
  def handle_info({:shared_entry_removed, _entry}, socket) do
    {:noreply, reload_shared_data(socket)}
  end

  @impl true
  def handle_info({:settlement_record_created, _record}, socket) do
    {:noreply, reload_shared_data(socket)}
  end

  @impl true
  def handle_info({:settlement_cycle_settled, _cycle}, socket) do
    {:noreply, reload_shared_data(socket)}
  end

  @impl true
  def handle_info({:settlement_record_reversed, _record_id}, socket) do
    {:noreply,
     socket
     |> assign(:pending_settlement_record_reversal, nil)
     |> assign(:settlement_reversal_form, settlement_reversal_form())
     |> reload_shared_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide={true}>
      <section class="collab-shell responsive-shell mx-auto flex max-w-6xl flex-col gap-6">
        <header class={collab_header_class("p-4 sm:p-5")}>
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div class="space-y-2">
              <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/62">
                Finanças compartilhadas
              </p>
              <h1 class="text-xl font-black tracking-[-0.02em] text-base-content sm:text-2xl">
                Visão conjunta do compartilhamento
              </h1>
            </div>
            <.link navigate={~p"/account-links"} class="inline-flex items-center gap-2 rounded-xl border border-cyan-300/35 bg-slate-900/85 px-3 py-1.5 text-xs font-semibold text-cyan-100 transition hover:border-cyan-200/70 hover:bg-cyan-400/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/35">
              <.icon name="hero-arrow-left" class="size-4" /> Voltar para compartilhamentos
            </.link>
          </div>
        </header>

        <section
          id="global-shared-period-filter"
          class="neon-surface sticky top-3 z-20 rounded-3xl border border-cyan-400/25 bg-slate-950/88 p-4 shadow-[0_24px_70px_-38px_rgba(34,211,238,0.7)] backdrop-blur"
        >
          <div class="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/72">
                Filtro temporal global
              </h2>
              <p class="mt-1 text-xs text-base-content/62">
                {format_reference_period_range(@global_filter_from_month, @global_filter_to_month)}
              </p>
            </div>
            <div class="flex flex-wrap gap-2">
              <button
                id="global-period-preset-default-window"
                type="button"
                phx-click="apply_global_period_preset"
                phx-value-preset="default_window"
                class={
                  period_preset_button_class(
                    @global_filter_from_month,
                    @global_filter_to_month,
                    "default_window"
                  )
                }
              >
                -3/+3 (padrão)
              </button>
              <button
                id="global-period-preset-current-month"
                type="button"
                phx-click="apply_global_period_preset"
                phx-value-preset="current_month"
                class={
                  period_preset_button_class(
                    @global_filter_from_month,
                    @global_filter_to_month,
                    "current_month"
                  )
                }
              >
                Mês atual
              </button>
              <button
                id="global-period-preset-last-3-months"
                type="button"
                phx-click="apply_global_period_preset"
                phx-value-preset="last_3_months"
                class={
                  period_preset_button_class(
                    @global_filter_from_month,
                    @global_filter_to_month,
                    "last_3_months"
                  )
                }
              >
                Últimos 3
              </button>
              <button
                id="global-period-preset-last-6-months"
                type="button"
                phx-click="apply_global_period_preset"
                phx-value-preset="last_6_months"
                class={
                  period_preset_button_class(
                    @global_filter_from_month,
                    @global_filter_to_month,
                    "last_6_months"
                  )
                }
              >
                Últimos 6
              </button>
            </div>
          </div>

          <.form
            for={@global_filter_form}
            id="global-period-custom-form"
            phx-change="change_global_period_filter"
            class="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2"
          >
            <.input
              field={@global_filter_form[:from_month]}
              type="month"
              label="De"
              phx-debounce="350"
            />
            <.input
              field={@global_filter_form[:to_month]}
              type="month"
              label="Até"
              phx-debounce="350"
            />
          </.form>
        </section>

        <section id="link-metrics-panel" class={neon_surface_class("order-60 p-5 sm:p-6")}>
          <div class="flex items-center justify-between gap-3">
            <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
              Resumo do período
            </h2>
            <span class="text-xs text-base-content/62">
              {format_reference_period_range(@global_filter_from_month, @global_filter_to_month)}
            </span>
          </div>

          <div class="collab-stats-grid mt-4 grid gap-3 sm:grid-cols-3">
            <article class={collab_stat_card_class()}>
              <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">
                Total compartilhado
              </p>
              <p class="mt-1 break-words text-xl font-mono font-semibold text-base-content">
                {format_cents(@metrics.total_cents)}
              </p>
            </article>

            <article class={collab_stat_card_class()}>
              <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">Você arcou</p>
              <p class="mt-1 break-words text-xl font-mono font-semibold text-info">
                {format_cents(@metrics.paid_a_cents)}
              </p>
            </article>

            <article class={collab_stat_card_class()}>
              <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">
                Outra conta arcou
              </p>
              <p class="mt-1 break-words text-xl font-mono font-semibold text-success">
                {format_cents(@metrics.paid_b_cents)}
              </p>
            </article>
          </div>

          <div class="mt-4 grid gap-3">
            <article id="shared-balance-chart" class={neon_card_class("min-h-[15rem] overflow-x-auto p-4")}>
              <div class="flex items-center justify-between gap-2">
                <h3 class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/70">
                  Esperado vs realizado
                </h3>
                <span class="text-[0.68rem] text-base-content/60">percentual</span>
              </div>
              <div class="contex-plot mt-2">
                {@shared_balance_chart}
              </div>
            </article>
          </div>
        </section>

        <section id="shared-entries-panel" class={neon_surface_class("order-30 p-5 sm:p-6")}>
          <div class="flex items-center justify-between gap-3">
            <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
              Lançamentos compartilhados
            </h2>
            <span class="text-xs text-base-content/62">{@shared_entries_count} item(ns)</span>
          </div>

          <form id="shared-entries-filters" phx-change="filter_shared_entries" class="mt-4">
            <.input
              type="text"
              name="filters[q]"
              value={@shared_entries_filter_q}
              placeholder="Filtrar lançamentos por descrição ou categoria..."
              maxlength="120"
            />
          </form>

          <div
            id="shared-entries-scroll-area"
            phx-hook="InfiniteScroll"
            data-event="load_more_shared_entries"
            data-has-more={to_string(@shared_entries_has_more?)}
            data-loading={to_string(@shared_entries_loading_more?)}
            data-next-page={@shared_entries_next_page}
            class="operations-scroll-area operations-scroll-area--list mt-4 rounded-2xl border border-cyan-300/20 bg-slate-900/65 p-3 shadow-[inset_0_0_0_1px_rgba(34,211,238,0.04)]"
          >
            <div id="shared-entries-list" phx-update="stream" class="space-y-2">
              <div
                :if={@shared_entries_count == 0}
                id="shared-entries-empty-state"
                class="rounded-2xl border border-dashed border-cyan-300/30 bg-slate-900/55 px-4 py-6 text-sm text-slate-300"
              >
                Ainda não há lançamentos compartilhados neste compartilhamento.
              </div>

              <div :for={{id, view} <- @streams.shared_entries} id={id} class={shared_entry_row_class("gap-3")}>
                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm font-medium text-base-content/92">
                    {view.entry.description || view.entry.category}
                  </p>
                  <p class="mt-1 break-words text-[0.72rem] font-mono text-base-content/62 sm:text-xs">
                    {format_cents(view.entry.amount_cents)} • Você: {format_pct(view.split_ratio_mine)} ({format_cents(
                      view.amount_mine_cents
                    )}) • Outra conta: {format_pct(view.split_ratio_theirs)} ({format_cents(
                      view.amount_theirs_cents
                    )})
                  </p>
                </div>

                <div class="flex items-center gap-1.5">
                  <button
                    :if={view.entry.user_id == @current_scope.user.id}
                    id={"edit-shared-entry-#{view.entry.id}"}
                    type="button"
                    phx-click="open_shared_entry_edit"
                    phx-value-entry_id={view.entry.id}
                    class="inline-flex shrink-0 items-center rounded-lg border border-cyan-300/35 bg-slate-900/85 px-2.5 py-1 text-xs font-medium text-cyan-100 transition hover:border-cyan-200/70 hover:bg-cyan-400/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/35"
                  >
                    Editar
                  </button>
                  <button
                    :if={view.entry.user_id == @current_scope.user.id}
                    id={"unshare-entry-#{view.entry.id}"}
                    type="button"
                    phx-click="prompt_unshare_entry"
                    phx-value-entry_id={view.entry.id}
                    class="inline-flex shrink-0 items-center rounded-lg border border-rose-300/45 bg-rose-500/10 px-2.5 py-1 text-xs font-medium text-rose-100 transition hover:border-rose-200/70 hover:bg-rose-500/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-300/35"
                  >
                    Remover
                  </button>
                </div>
              </div>
            </div>

            <div :if={@shared_entries_loading_more?} class="px-1 py-2">
              <p class="text-center text-xs text-base-content/62">Carregando mais lançamentos...</p>
            </div>
          </div>
        </section>

        <section id="shared-debt-summary" class={neon_surface_class("order-10 p-5 sm:p-6")}>
          <div class="flex items-center justify-between gap-3">
            <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
              Dívidas por competência
            </h2>
            <span class="text-xs text-base-content/62">
              {format_reference_period_range(@global_filter_from_month, @global_filter_to_month)}
            </span>
          </div>

          <div class="mt-4 overflow-x-auto">
            <div class="grid min-w-[44rem] gap-3 sm:grid-cols-2 xl:grid-cols-4">
              <article :for={summary <- @monthly_debt_summaries} class={neon_card_class("p-4")}>
                <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">
                  {String.pad_leading(to_string(summary.reference_month), 2, "0")}/{summary.reference_year}
                </p>
                <p class="mt-2 text-xs text-base-content/70">
                  Total: {format_cents(summary.original_amount_cents)}
                </p>
                <p class="mt-1 text-sm font-semibold text-warning">
                  Em aberto: {format_cents(summary.outstanding_amount_cents)}
                </p>
                <p class="mt-2 text-[0.7rem] text-base-content/62">
                  Status: {monthly_status_label(summary.status)}
                </p>
              </article>
            </div>
          </div>
        </section>

        <section id="shared-entry-debts-list" class={neon_surface_class("order-40 p-5 sm:p-6")}>
          <div class="flex items-center justify-between gap-3">
            <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
              Dívidas por lançamento
            </h2>
            <span class="text-xs text-base-content/62">{@shared_entry_debts_count} item(ns)</span>
          </div>

          <form id="shared-entry-debts-filters" phx-change="filter_shared_entry_debts" class="mt-4">
            <.input
              type="text"
              name="filters[q]"
              value={@shared_entry_debts_filter_q}
              placeholder="Filtrar dívidas por descrição ou categoria..."
              maxlength="120"
            />
          </form>

          <div
            id="shared-entry-debts-scroll-area"
            phx-hook="InfiniteScroll"
            data-event="load_more_shared_entry_debts"
            data-has-more={to_string(@shared_entry_debts_has_more?)}
            data-loading={to_string(@shared_entry_debts_loading_more?)}
            data-next-page={@shared_entry_debts_next_page}
            class="operations-scroll-area operations-scroll-area--list mt-4 rounded-2xl border border-cyan-300/20 bg-slate-900/65 p-3 shadow-[inset_0_0_0_1px_rgba(34,211,238,0.04)]"
          >
            <div class="space-y-2">
              <div
                :if={@shared_entry_debts_count == 0}
                class="rounded-2xl border border-dashed border-cyan-300/30 bg-slate-900/55 px-4 py-6 text-sm text-slate-300"
              >
                Nenhuma dívida em aberto ou quitada para este vínculo.
              </div>

              <article :for={debt <- @shared_entry_debts} id={"shared-entry-debt-#{debt.id}"} class={shared_entry_row_class("gap-2")}>
                <div class="min-w-0 flex-1">
                  <p class="truncate text-sm font-semibold text-base-content/92">
                    {debt.finance_entry.description || debt.finance_entry.category}
                  </p>
                  <p class="mt-1 text-xs text-base-content/62">
                    Competência: {String.pad_leading(to_string(debt.reference_month), 2, "0")}/{debt.reference_year} • Total: {format_cents(
                      debt.original_amount_cents
                    )} • Em aberto: {format_cents(debt.outstanding_amount_cents)}
                  </p>
                </div>
                <div class="flex items-center gap-2 self-end sm:self-center">
                  <span class={debt_status_badge_class(debt.status)}>
                    {debt_status_label(debt.status)}
                  </span>
                  <button
                    :if={can_target_debt_payment?(debt, @current_scope.user.id)}
                    id={"pay-shared-entry-debt-#{debt.id}"}
                    type="button"
                    phx-click="prefill_payment_for_debt"
                    phx-value-debt_id={debt.id}
                    class="inline-flex items-center rounded-lg border border-cyan-300/35 bg-slate-900/85 px-2.5 py-1 text-xs font-medium text-cyan-100 transition hover:border-cyan-200/70 hover:bg-cyan-400/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/35"
                  >
                    Pagar este lançamento
                  </button>
                </div>
              </article>
            </div>

            <div :if={@shared_entry_debts_loading_more?} class="px-1 py-2">
              <p class="text-center text-xs text-base-content/62">Carregando mais dívidas...</p>
            </div>
          </div>
        </section>

        <section id="shared-payment-form-panel" class={neon_surface_class("order-20 p-5 sm:p-6")}>
          <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
            Registrar pagamento
          </h2>
          <p class="mt-2 text-sm text-base-content/70">
            Registre um pagamento e o sistema distribui automaticamente por ordem FIFO nas dívidas abertas.
          </p>

          <%= if selected_debt = selected_payment_debt(@payment_form, @shared_entry_debts) do %>
            <div
              id="shared-payment-targeted-debt"
              class="mt-4 rounded-xl border border-info/35 bg-info/12 p-3"
            >
              <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                <div class="min-w-0">
                  <p class="text-xs font-semibold uppercase tracking-[0.12em] text-info">
                    Pagamento direcionado
                  </p>
                  <p class="mt-1 truncate text-sm font-medium text-base-content/92">
                    {selected_debt.finance_entry.description || selected_debt.finance_entry.category}
                  </p>
                  <p class="mt-1 text-xs text-base-content/72">
                    Saldo em aberto: {format_cents(selected_debt.outstanding_amount_cents)}
                  </p>
                </div>
                <button
                  id="clear-payment-debt-target"
                  type="button"
                  phx-click="clear_payment_debt_target"
                  class="inline-flex items-center rounded-lg border border-slate-400/30 bg-slate-900/70 px-2.5 py-1 text-xs font-medium text-slate-200 transition hover:border-cyan-300/45 hover:text-cyan-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/35"
                >
                  Limpar seleção
                </button>
              </div>
            </div>
          <% end %>

          <.form
            for={@payment_form}
            id="shared-payment-form"
            phx-submit="create_record"
            class="mt-4 space-y-4"
          >
            <input
              type="hidden"
              id="payment-shared-entry-debt-id"
              name="payment[shared_entry_debt_id]"
              value={@payment_form[:shared_entry_debt_id].value || ""}
            />

            <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <.input
                field={@payment_form[:amount_cents]}
                type="text"
                label="Valor pago"
                placeholder="Ex: 150,00"
                inputmode="numeric"
              />

              <.input
                field={@payment_form[:method]}
                type="select"
                label="Método"
                options={settlement_method_options()}
              />

              <.input
                field={@payment_form[:transferred_at]}
                type="text"
                label="Data do pagamento"
                placeholder="dd/mm/aaaa"
                inputmode="numeric"
                maxlength="10"
                pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
              />
            </div>

            <.button type="submit" variant="primary" class="w-full sm:w-auto">
              Registrar pagamento
            </.button>
          </.form>
        </section>

        <section id="shared-payment-history" class={neon_surface_class("order-70 p-5 sm:p-6")}>
          <div class="flex items-center justify-between gap-3">
            <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
              Histórico de pagamentos e alocações
            </h2>
            <span class="text-xs text-base-content/62">{@settlement_records_count} pagamento(s)</span>
          </div>

          <form id="settlement-records-filters" phx-change="filter_settlement_records" class="mt-4">
            <.input
              type="text"
              name="filters[q]"
              value={@settlement_records_filter_q}
              placeholder="Filtrar por método, valor ou data..."
              maxlength="120"
            />
          </form>

          <div
            id="settlement-records-scroll-area"
            phx-hook="InfiniteScroll"
            data-event="load_more_settlement_records"
            data-has-more={to_string(@settlement_records_has_more?)}
            data-loading={to_string(@settlement_records_loading_more?)}
            data-next-page={@settlement_records_next_page}
            class="operations-scroll-area operations-scroll-area--list mt-4 rounded-2xl border border-cyan-300/20 bg-slate-900/65 p-3 shadow-[inset_0_0_0_1px_rgba(34,211,238,0.04)]"
          >
            <div id="shared-settlement-records" phx-update="stream" class="space-y-2">
              <div
                :if={@settlement_records_count == 0}
                id="shared-settlement-records-empty"
                class="rounded-2xl border border-dashed border-cyan-300/30 bg-slate-900/55 px-4 py-6 text-sm text-slate-300"
              >
                Nenhum pagamento registrado neste vínculo.
              </div>

              <article :for={{id, record} <- @streams.settlement_records} id={id} class={neon_card_class("p-4")}>
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <p class={[
                    "text-sm font-semibold font-mono",
                    settlement_record_amount_class(record.status)
                  ]}>
                    {format_cents(record.amount_cents)}
                  </p>
                  <p class="text-xs text-base-content/62">
                    {format_method(record.method)} • {format_date(record.transferred_at)}
                  </p>
                </div>

                <div
                  :if={record.status == :reversed}
                  class="mt-2 rounded-lg border border-warning/35 bg-warning/12 p-2"
                >
                  <p class="text-xs font-semibold uppercase tracking-[0.1em] text-warning-content">
                    Pagamento estornado
                  </p>
                  <p class="mt-1 text-xs text-base-content/70">
                    {format_reversed_metadata(record)}
                  </p>
                </div>

                <ul class="mt-2 space-y-1">
                  <li
                    :for={allocation <- record.allocations}
                    class="text-xs text-base-content/70"
                  >
                    {format_cents(allocation.amount_cents)} abatido em {allocation.shared_entry_debt.finance_entry.description ||
                      allocation.shared_entry_debt.finance_entry.category}
                  </li>
                </ul>

                <div class="mt-3 flex justify-end">
                  <button
                    :if={record.status == :active}
                    id={"reverse-settlement-record-#{record.id}"}
                    type="button"
                    phx-click="prompt_reverse_settlement_record"
                    phx-value-id={record.id}
                    class="inline-flex items-center rounded-lg border border-amber-300/45 bg-amber-400/12 px-2.5 py-1 text-xs font-medium text-amber-100 transition hover:border-amber-200/70 hover:bg-amber-400/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-300/35"
                  >
                    Estornar pagamento
                  </button>
                </div>
              </article>
            </div>

            <div :if={@settlement_records_loading_more?} class="px-1 py-2">
              <p class="text-center text-xs text-base-content/62">Carregando mais pagamentos...</p>
            </div>
          </div>
        </section>

        <section id="shared-month-confirmation" class={neon_surface_class("order-50 p-5 sm:p-6")}>
          <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
            Fechamento mensal com confirmação bilateral
          </h2>
          <p class="mt-2 text-sm text-base-content/70">
            O mês só é fechado quando não há pendência e as duas contas confirmam o saldo final.
          </p>

          <.form
            for={@settlement_focus_form}
            id="settlement-focus-form"
            phx-change="change_settlement_focus_month"
            class="mt-4 max-w-xs"
          >
            <.input
              field={@settlement_focus_form[:month]}
              type="select"
              label="Competência para fechamento"
              options={settlement_focus_options(@global_filter_from_month, @global_filter_to_month)}
            />
          </.form>

          <div class="mt-4 flex flex-col gap-2 sm:flex-row sm:items-center">
            <button
              id="shared-confirm-settlement-btn"
              type="button"
              phx-click="confirm_settlement"
              class="inline-flex items-center justify-center rounded-xl border border-cyan-300/70 bg-cyan-400/90 px-4 py-2 text-sm font-semibold text-slate-950 shadow-[0_16px_36px_-20px_rgba(34,211,238,0.8)] transition hover:bg-cyan-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-200/60"
            >
              Confirmar fechamento mensal
            </button>
            <span class="text-xs text-base-content/62">
              Status atual: {if @settlement_cycle.status == :settled, do: "fechado", else: "aberto"}
            </span>
          </div>
        </section>

        <.destructive_confirm_modal
          id="shared-entry-unshare-confirmation-modal"
          show={is_map(@pending_unshare_entry)}
          title="Remover compartilhamento deste lançamento?"
          message="O lançamento continuará na conta de origem, mas sairá deste fluxo colaborativo."
          severity="danger"
          impact_label="Impacto: o item deixa de compor dívidas e acertos do vínculo"
          confirm_event="confirm_unshare_entry"
          cancel_event="cancel_unshare_entry"
          confirm_button_id="confirm-unshare-entry-btn"
          cancel_button_id="cancel-unshare-entry-btn"
          confirm_label="Sim, remover compartilhamento"
        >
          <p :if={is_map(@pending_unshare_entry)} class="font-medium text-base-content">
            {Map.get(@pending_unshare_entry, :label, "Lançamento compartilhado")}
          </p>
        </.destructive_confirm_modal>

        <.app_modal
          id="settlement-record-reversal-modal"
          show={is_map(@pending_settlement_record_reversal)}
          cancel_event="cancel_reverse_settlement_record"
          aria_labelledby="settlement-record-reversal-title"
          dialog_class="max-w-xl rounded-2xl p-5 sm:p-6"
        >
          <section id="settlement-record-reversal-dialog">
            <h3 id="settlement-record-reversal-title" class="text-lg font-semibold text-base-content">
              Estornar pagamento
            </h3>
            <p class="mt-2 text-sm text-base-content/72">
              O valor será devolvido às dívidas em aberto, permitindo correção do acerto.
            </p>

            <.form
              for={@settlement_reversal_form}
              id="settlement-record-reversal-form"
              phx-submit="confirm_reverse_settlement_record"
              class="mt-4 space-y-3"
            >
              <input
                type="hidden"
                name="settlement_reversal[id]"
                value={
                  if is_map(@pending_settlement_record_reversal),
                    do: Map.get(@pending_settlement_record_reversal, :id),
                    else: ""
                }
              />

              <.input
                field={@settlement_reversal_form[:reason]}
                type="text"
                label="Motivo (opcional)"
                placeholder="Ex: valor informado incorretamente"
                maxlength="300"
              />

              <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                <button
                  type="button"
                  class="inline-flex items-center justify-center rounded-xl border border-slate-400/30 bg-slate-900/70 px-3 py-1.5 text-xs font-semibold text-slate-200 transition hover:border-cyan-300/45 hover:text-cyan-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/35"
                  phx-click="cancel_reverse_settlement_record"
                >
                  Cancelar
                </button>
                <button type="submit" class="inline-flex items-center justify-center rounded-xl border border-amber-300/60 bg-amber-400/85 px-3 py-1.5 text-xs font-semibold text-slate-950 shadow-[0_12px_24px_-14px_rgba(251,191,36,0.8)] transition hover:bg-amber-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-200/60">Confirmar estorno</button>
              </div>
            </.form>
          </section>
        </.app_modal>

        <section id="recurring-variable-trend" class={neon_surface_class("order-80 p-5 sm:p-6")}>
          <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
            Tendência de recorrentes variáveis (6 meses)
          </h2>

          <%= if @trend == [] do %>
            <p class="mt-3 text-sm text-base-content/58">Nenhum dado disponível neste período.</p>
          <% else %>
            <ul class="mt-3 space-y-2">
              <%= for mt <- @trend do %>
                <li class={trend_list_item_class()}>
                  <span class="text-sm font-mono text-base-content/72">{mt.month}/{mt.year}</span>
                  <span class="text-sm font-semibold font-mono text-base-content/92">
                    {format_cents(mt.total_cents)}
                  </span>
                </li>
              <% end %>
            </ul>
          <% end %>
        </section>

        <.shared_entry_edit_modal
          form={@shared_entry_edit_form}
          preview={@shared_entry_edit_preview}
          entry={@shared_entry_edit_entry}
          split_type_options={shared_split_type_options()}
        />
      </section>
    </Layouts.app>
    """
  end

  attr :form, :any, required: true
  attr :preview, :map, default: nil
  attr :entry, :any, default: nil
  attr :split_type_options, :list, default: []

  defp shared_entry_edit_modal(assigns) do
    split_type = assigns.form[:split_type].value || "income_ratio"

    preview =
      assigns.preview ||
        %{
          split_ratio_mine: 0.0,
          split_ratio_theirs: 0.0,
          amount_mine_cents: 0,
          amount_theirs_cents: 0
        }

    assigns =
      assigns
      |> assign(:split_type, split_type)
      |> assign(:preview, preview)

    ~H"""
    <.app_modal
      id="shared-entry-edit-modal"
      show={is_map(@entry)}
      cancel_event="cancel_shared_entry_edit"
      aria_labelledby={if is_map(@entry), do: "shared-entry-edit-title-#{@entry.id}", else: nil}
      z_index_class="z-[120]"
      dialog_class="max-w-4xl max-h-[88vh] overflow-y-auto p-5 sm:p-6"
    >
      <section id="shared-entry-edit-dialog">
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/70">
              Lançamento compartilhado
            </p>
            <h2
              id={"shared-entry-edit-title-#{@entry.id}"}
              class="mt-1 text-2xl font-black tracking-[-0.01em] text-base-content"
            >
              Ajustar divisão e transação
            </h2>
          </div>

          <button
            id="shared-entry-edit-close-btn"
            type="button"
            phx-click="cancel_shared_entry_edit"
            class="inline-flex items-center justify-center rounded-xl border border-slate-400/30 bg-slate-900/70 px-3 py-1.5 text-xs font-semibold text-slate-200 transition hover:border-cyan-300/45 hover:text-cyan-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/35"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <.form
          for={@form}
          id="shared-entry-edit-form"
          phx-change="change_shared_entry_edit"
          phx-submit="save_shared_entry_edit"
          class="mt-5 space-y-4"
        >
          <div class="grid gap-3 rounded-2xl border border-cyan-300/20 bg-slate-900/78 p-3 sm:grid-cols-2 sm:p-4">
            <.input
              field={@form[:description]}
              type="text"
              label="Descrição"
              class="w-full rounded-xl border border-cyan-300/25 bg-slate-900/90 px-3 py-2 text-sm text-slate-100 shadow-[inset_0_0_0_1px_rgba(34,211,238,0.05)] transition focus:border-cyan-300/70 focus:outline-none focus:ring-2 focus:ring-cyan-300/25"
              placeholder="Ex: Aluguel, mercado, conta de luz..."
            />
            <.input
              field={@form[:category]}
              type="text"
              label="Categoria"
              required
              class="w-full rounded-xl border border-cyan-300/25 bg-slate-900/90 px-3 py-2 text-sm text-slate-100 shadow-[inset_0_0_0_1px_rgba(34,211,238,0.05)] transition focus:border-cyan-300/70 focus:outline-none focus:ring-2 focus:ring-cyan-300/25"
            />
            <.input
              field={@form[:amount_cents]}
              type="text"
              label="Valor total"
              inputmode="decimal"
              required
              class="w-full rounded-xl border border-cyan-300/25 bg-slate-900/90 px-3 py-2 text-sm text-slate-100 shadow-[inset_0_0_0_1px_rgba(34,211,238,0.05)] transition focus:border-cyan-300/70 focus:outline-none focus:ring-2 focus:ring-cyan-300/25"
              placeholder="Ex: 350,55"
            />
            <.input
              field={@form[:occurred_on]}
              type="text"
              label="Data"
              inputmode="numeric"
              maxlength="10"
              pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
              placeholder="dd/mm/aaaa"
              required
              class="w-full rounded-xl border border-cyan-300/25 bg-slate-900/90 px-3 py-2 text-sm text-slate-100 shadow-[inset_0_0_0_1px_rgba(34,211,238,0.05)] transition focus:border-cyan-300/70 focus:outline-none focus:ring-2 focus:ring-cyan-300/25"
            />
          </div>

          <section class="rounded-2xl border border-cyan-300/20 bg-slate-900/78 p-4 shadow-[0_12px_32px_-22px_rgba(34,211,238,0.55)]">
            <h3 class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/64">
              Tipo de divisão
            </h3>
            <.input
              field={@form[:split_type]}
              type="select"
              options={@split_type_options}
              label="Como dividir entre as contas?"
              class="w-full rounded-xl border border-cyan-300/25 bg-slate-900/90 px-3 py-2 text-sm text-slate-100 shadow-[inset_0_0_0_1px_rgba(34,211,238,0.05)] transition focus:border-cyan-300/70 focus:outline-none focus:ring-2 focus:ring-cyan-300/25"
            />

            <div :if={@split_type == "percentage"} class="grid gap-3 sm:grid-cols-2">
              <.input
                field={@form[:split_mine_percentage]}
                type="text"
                label="Sua porcentagem (%)"
                inputmode="decimal"
                placeholder="Ex: 56,7"
                class="w-full rounded-xl border border-cyan-300/25 bg-slate-900/90 px-3 py-2 text-sm text-slate-100 shadow-[inset_0_0_0_1px_rgba(34,211,238,0.05)] transition focus:border-cyan-300/70 focus:outline-none focus:ring-2 focus:ring-cyan-300/25"
              />
              <.input
                field={@form[:split_mine_amount]}
                type="text"
                label="Seu valor (R$)"
                inputmode="decimal"
                placeholder="Calculado automaticamente"
                readonly
                class="w-full rounded-xl border border-cyan-300/15 bg-slate-900/70 px-3 py-2 text-sm text-slate-300/90"
              />
            </div>

            <div :if={@split_type == "fixed_amount"} class="grid gap-3 sm:grid-cols-2">
              <.input
                field={@form[:split_mine_amount]}
                type="text"
                label="Seu valor fixo (R$)"
                inputmode="decimal"
                placeholder="Ex: 120,00"
                class="w-full rounded-xl border border-cyan-300/25 bg-slate-900/90 px-3 py-2 text-sm text-slate-100 shadow-[inset_0_0_0_1px_rgba(34,211,238,0.05)] transition focus:border-cyan-300/70 focus:outline-none focus:ring-2 focus:ring-cyan-300/25"
              />
              <.input
                field={@form[:split_mine_percentage]}
                type="text"
                label="Sua porcentagem (%)"
                inputmode="decimal"
                placeholder="Calculada automaticamente"
                readonly
                class="w-full rounded-xl border border-cyan-300/15 bg-slate-900/70 px-3 py-2 text-sm text-slate-300/90"
              />
            </div>

            <div
              :if={@split_type == "income_ratio"}
              class="rounded-xl border border-info/45 bg-info/16 px-3 py-2 text-[0.78rem] font-semibold leading-5 text-base-content/88"
            >
              <div class="flex items-start gap-2">
                <.icon name="hero-information-circle" class="mt-0.5 size-4 shrink-0 text-info" />
                <span>
                  A divisão automática usa a proporção de renda de referência do mês da transação.
                </span>
              </div>
            </div>
          </section>

          <section
            id="shared-entry-edit-preview"
            class="rounded-2xl border border-cyan-300/20 bg-slate-900/78 p-4 shadow-[0_12px_32px_-22px_rgba(34,211,238,0.55)]"
          >
            <h3 class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/64">
              Prévia da divisão entre as duas contas
            </h3>
            <div class="mt-3 grid gap-3 sm:grid-cols-2">
              <article
                id="shared-entry-edit-preview-mine"
                class="rounded-xl border border-info/45 bg-info/14 p-3 shadow-sm"
              >
                <p class="text-xs font-bold uppercase tracking-[0.12em] text-info">Você</p>
                <p class="mt-1 text-base font-semibold font-mono text-base-content">
                  {format_pct(@preview.split_ratio_mine)} ({format_cents(@preview.amount_mine_cents)})
                </p>
              </article>
              <article
                id="shared-entry-edit-preview-theirs"
                class="rounded-xl border border-success/45 bg-success/14 p-3 shadow-sm"
              >
                <p class="text-xs font-bold uppercase tracking-[0.12em] text-success">
                  Outra conta
                </p>
                <p class="mt-1 text-base font-semibold font-mono text-base-content">
                  {format_pct(@preview.split_ratio_theirs)} ({format_cents(
                    @preview.amount_theirs_cents
                  )})
                </p>
              </article>
            </div>
          </section>

          <div class="flex flex-col-reverse gap-2 border-t border-cyan-300/20 pt-3 sm:flex-row sm:justify-end">
            <button
              type="button"
              phx-click="cancel_shared_entry_edit"
              class="inline-flex items-center justify-center rounded-xl border border-slate-400/30 bg-slate-900/70 px-3 py-1.5 text-xs font-semibold text-slate-200 transition hover:border-cyan-300/45 hover:text-cyan-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/35"
            >
              Cancelar
            </button>
            <button type="submit" class="inline-flex items-center justify-center rounded-xl border border-cyan-300/70 bg-cyan-400/90 px-3 py-1.5 text-xs font-semibold text-slate-950 shadow-[0_16px_36px_-20px_rgba(34,211,238,0.8)] transition hover:bg-cyan-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-200/60">
              Salvar alterações
            </button>
          </div>
        </.form>
      </section>
    </.app_modal>
    """
  end

  defp collab_header_class(extra) do
    join_classes([
      "neon-surface collab-hero rounded-3xl border border-cyan-400/20 bg-slate-950/72 shadow-[0_24px_70px_-38px_rgba(34,211,238,0.7)] backdrop-blur-sm",
      extra
    ])
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

  defp collab_stat_card_class do
    join_classes(["collab-stat text-center", neon_card_class("p-4")])
  end

  defp shared_entry_row_class(extra) do
    join_classes([
      "shared-entry-row flex flex-col rounded-2xl p-4 sm:flex-row sm:items-center sm:justify-between",
      neon_card_class(nil),
      extra
    ])
  end

  defp trend_list_item_class do
    join_classes(["trend-list-item flex items-center justify-between rounded-xl p-3", neon_card_class(nil)])
  end

  defp join_classes(classes) do
    classes
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp reload_shared_data(socket) do
    scope = socket.assigns.current_scope
    link_id = socket.assigns.link_id
    from_month = socket.assigns.global_filter_from_month
    to_month = socket.assigns.global_filter_to_month
    settlement_focus_month = socket.assigns.settlement_focus_month

    shared_entries_page =
      Map.get(socket.assigns, :shared_entries_page, 1) |> parse_positive_page()

    shared_entry_debts_page =
      Map.get(socket.assigns, :shared_entry_debts_page, 1) |> parse_positive_page()

    settlement_records_page =
      Map.get(socket.assigns, :settlement_records_page, 1) |> parse_positive_page()

    shared_entries_filter_q = Map.get(socket.assigns, :shared_entries_filter_q, "")
    shared_entry_debts_filter_q = Map.get(socket.assigns, :shared_entry_debts_filter_q, "")
    settlement_records_filter_q = Map.get(socket.assigns, :settlement_records_filter_q, "")
    range_params = %{from: from_month, to: to_month, reference_date: to_month}

    {:ok, {views, shared_entries_meta}} =
      SharedFinance.list_shared_entries_with_meta(scope, link_id, %{
        from: from_month,
        to: to_month,
        reference_date: to_month,
        page: shared_entries_page,
        page_size: @shared_entries_page_size,
        q: shared_entries_filter_q
      })

    {:ok, metrics} = SharedFinance.get_link_metrics(scope, link_id, to_month, range_params)

    {:ok, trend} = SharedFinance.get_recurring_variable_trend(scope, link_id, range_params)

    {:ok, cycle} =
      SharedFinance.get_or_create_settlement_cycle(scope, link_id, settlement_focus_month)

    {:ok, {debts, shared_entry_debts_meta}} =
      SharedFinance.list_shared_entry_debts_with_meta(scope, link_id, %{
        from: from_month,
        to: to_month,
        reference_date: to_month,
        page: shared_entry_debts_page,
        page_size: @shared_entry_debts_page_size,
        q: shared_entry_debts_filter_q
      })

    {:ok, {records, settlement_records_meta}} =
      SharedFinance.list_settlement_records_for_link_with_meta(scope, link_id, %{
        from: from_month,
        to: to_month,
        reference_date: to_month,
        page: settlement_records_page,
        page_size: @settlement_records_page_size,
        q: settlement_records_filter_q
      })

    {:ok, monthly_debt_summaries} =
      SharedFinance.monthly_debt_summaries(scope, link_id, range_params)

    socket
    |> assign(:metrics, metrics)
    |> assign(:trend, trend)
    |> assign(:shared_balance_chart, shared_balance_chart_svg(metrics))
    |> assign(:shared_entries_count, shared_entries_meta.total_count || length(views))
    |> assign(:shared_entries_meta, shared_entries_meta)
    |> assign(:shared_entries_has_more?, Map.get(shared_entries_meta, :has_next_page?, false))
    |> assign(:shared_entries_loading_more?, false)
    |> assign(
      :shared_entries_page,
      Map.get(shared_entries_meta, :current_page, shared_entries_page)
    )
    |> assign(
      :shared_entries_next_page,
      Map.get(shared_entries_meta, :current_page, shared_entries_page) + 1
    )
    |> assign(:shared_entry_debts, debts)
    |> assign(:shared_entry_debts_count, shared_entry_debts_meta.total_count || length(debts))
    |> assign(:shared_entry_debts_meta, shared_entry_debts_meta)
    |> assign(
      :shared_entry_debts_has_more?,
      Map.get(shared_entry_debts_meta, :has_next_page?, false)
    )
    |> assign(:shared_entry_debts_loading_more?, false)
    |> assign(
      :shared_entry_debts_page,
      Map.get(shared_entry_debts_meta, :current_page, shared_entry_debts_page)
    )
    |> assign(
      :shared_entry_debts_next_page,
      Map.get(shared_entry_debts_meta, :current_page, shared_entry_debts_page) + 1
    )
    |> assign(:settlement_cycle, cycle)
    |> assign(:settlement_focus_form, settlement_focus_form(settlement_focus_month))
    |> assign(:settlement_records_count, settlement_records_meta.total_count || length(records))
    |> assign(:settlement_records_meta, settlement_records_meta)
    |> assign(
      :settlement_records_has_more?,
      Map.get(settlement_records_meta, :has_next_page?, false)
    )
    |> assign(:settlement_records_loading_more?, false)
    |> assign(
      :settlement_records_page,
      Map.get(settlement_records_meta, :current_page, settlement_records_page)
    )
    |> assign(
      :settlement_records_next_page,
      Map.get(settlement_records_meta, :current_page, settlement_records_page) + 1
    )
    |> assign(:monthly_debt_summaries, monthly_debt_summaries)
    |> stream(:shared_entries, views, reset: true)
    |> stream(:settlement_records, records, reset: true)
  end

  defp load_shared_entries(socket, page, opts) do
    reset? = Keyword.get(opts, :reset, true)
    scope = socket.assigns.current_scope
    link_id = socket.assigns.link_id
    from_month = socket.assigns.global_filter_from_month
    to_month = socket.assigns.global_filter_to_month
    filter_q = Map.get(socket.assigns, :shared_entries_filter_q, "")

    case SharedFinance.list_shared_entries_with_meta(scope, link_id, %{
           from: from_month,
           to: to_month,
           reference_date: to_month,
           page: page,
           page_size: @shared_entries_page_size,
           q: filter_q
         }) do
      {:ok, {views, meta}} ->
        current_page = Map.get(meta, :current_page, page)
        has_more? = Map.get(meta, :has_next_page?, false)

        visible_count =
          if reset? do
            length(views)
          else
            Map.get(socket.assigns, :shared_entries_count, 0) + length(views)
          end

        socket
        |> assign(:shared_entries_meta, meta)
        |> assign(:shared_entries_page, current_page)
        |> assign(:shared_entries_next_page, current_page + 1)
        |> assign(:shared_entries_has_more?, has_more?)
        |> assign(:shared_entries_loading_more?, false)
        |> assign(:shared_entries_count, meta.total_count || visible_count)
        |> stream(:shared_entries, views, reset: reset?)

      _ ->
        socket
        |> assign(:shared_entries_loading_more?, false)
        |> error_feedback(
          "Não foi possível carregar lançamentos compartilhados",
          "Atualize a página e tente novamente"
        )
    end
  end

  defp load_shared_entry_debts(socket, page, opts) do
    reset? = Keyword.get(opts, :reset, true)
    scope = socket.assigns.current_scope
    link_id = socket.assigns.link_id
    from_month = socket.assigns.global_filter_from_month
    to_month = socket.assigns.global_filter_to_month
    filter_q = Map.get(socket.assigns, :shared_entry_debts_filter_q, "")

    case SharedFinance.list_shared_entry_debts_with_meta(scope, link_id, %{
           from: from_month,
           to: to_month,
           reference_date: to_month,
           page: page,
           page_size: @shared_entry_debts_page_size,
           q: filter_q
         }) do
      {:ok, {debts, meta}} ->
        current_page = Map.get(meta, :current_page, page)
        has_more? = Map.get(meta, :has_next_page?, false)

        merged_debts =
          if reset? do
            debts
          else
            Map.get(socket.assigns, :shared_entry_debts, []) ++ debts
          end

        socket
        |> assign(:shared_entry_debts, merged_debts)
        |> assign(:shared_entry_debts_meta, meta)
        |> assign(:shared_entry_debts_page, current_page)
        |> assign(:shared_entry_debts_next_page, current_page + 1)
        |> assign(:shared_entry_debts_has_more?, has_more?)
        |> assign(:shared_entry_debts_loading_more?, false)
        |> assign(:shared_entry_debts_count, meta.total_count || length(merged_debts))

      _ ->
        socket
        |> assign(:shared_entry_debts_loading_more?, false)
        |> error_feedback(
          "Não foi possível carregar dívidas por lançamento",
          "Atualize a página e tente novamente"
        )
    end
  end

  defp load_settlement_records(socket, page, opts) do
    reset? = Keyword.get(opts, :reset, true)
    scope = socket.assigns.current_scope
    link_id = socket.assigns.link_id
    from_month = socket.assigns.global_filter_from_month
    to_month = socket.assigns.global_filter_to_month
    filter_q = Map.get(socket.assigns, :settlement_records_filter_q, "")

    case SharedFinance.list_settlement_records_for_link_with_meta(scope, link_id, %{
           from: from_month,
           to: to_month,
           reference_date: to_month,
           page: page,
           page_size: @settlement_records_page_size,
           q: filter_q
         }) do
      {:ok, {records, meta}} ->
        current_page = Map.get(meta, :current_page, page)
        has_more? = Map.get(meta, :has_next_page?, false)

        visible_count =
          if reset? do
            length(records)
          else
            Map.get(socket.assigns, :settlement_records_count, 0) + length(records)
          end

        socket
        |> assign(:settlement_records_meta, meta)
        |> assign(:settlement_records_page, current_page)
        |> assign(:settlement_records_next_page, current_page + 1)
        |> assign(:settlement_records_has_more?, has_more?)
        |> assign(:settlement_records_loading_more?, false)
        |> assign(:settlement_records_count, meta.total_count || visible_count)
        |> stream(:settlement_records, records, reset: reset?)

      _ ->
        socket
        |> assign(:settlement_records_loading_more?, false)
        |> error_feedback(
          "Não foi possível carregar pagamentos",
          "Atualize a página e tente novamente"
        )
    end
  end

  defp close_shared_entry_edit_modal(socket) do
    socket
    |> assign(:shared_entry_edit_entry, nil)
    |> assign(:shared_entry_edit_form, to_form(%{}, as: :shared_entry_edit))
    |> assign(:shared_entry_edit_preview, nil)
  end

  defp perform_unshare_entry(socket, entry_id) do
    scope = socket.assigns.current_scope

    with {:ok, _entry} <- SharedFinance.unshare_finance_entry(scope, entry_id) do
      track_funnel(:shared_entry_unshare, :success)

      socket
      |> assign(:pending_unshare_entry, nil)
      |> reload_shared_data()
    else
      {:error, {:validation, _}} ->
        track_funnel(:shared_entry_unshare, :error, %{reason: "validation"})

        socket
        |> assign(:pending_unshare_entry, nil)
        |> error_feedback(
          "Este lançamento já possui pagamentos alocados e não pode ser removido",
          "Remova ou ajuste os pagamentos antes de tentar novamente"
        )

      _ ->
        track_funnel(:shared_entry_unshare, :error, %{reason: "unexpected"})

        socket
        |> assign(:pending_unshare_entry, nil)
        |> error_feedback(
          "Não foi possível remover o compartilhamento",
          "Tente novamente em alguns instantes"
        )
    end
  end

  defp prepare_unshare_entry_confirmation(socket, entry_id) do
    scope = socket.assigns.current_scope
    link_id = socket.assigns.link_id

    with {:ok, parsed_entry_id} <- parse_int(entry_id),
         {:ok, entry} <-
           SharedFinance.get_shared_entry_owned_by_user(scope, link_id, parsed_entry_id) do
      label =
        entry.description
        |> default_if_blank(entry.category)
        |> default_if_blank("Lançamento compartilhado")

      assign(socket, :pending_unshare_entry, %{id: entry.id, label: label})
    else
      {:error, :not_found} ->
        error_feedback(
          socket,
          "Lançamento compartilhado não encontrado",
          "Atualize a lista e selecione outro lançamento"
        )

      _ ->
        error_feedback(
          socket,
          "Não foi possível abrir a confirmação",
          "Tente novamente"
        )
    end
  end

  defp shared_entry_view_for_edit(scope, link_id, from_month, to_month, entry_id) do
    with {:ok, views} <-
           SharedFinance.list_shared_entries(scope, link_id, %{
             from: from_month,
             to: to_month,
             reference_date: to_month
           }),
         %{} = view <- Enum.find(views, &(&1.entry.id == entry_id)) do
      {:ok, view}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  defp shared_entry_edit_form_params(view) do
    %{
      "description" => view.entry.description || "",
      "category" => view.entry.category || "",
      "amount_cents" => format_amount_input(view.entry.amount_cents),
      "occurred_on" => DateSupport.format_pt_br(view.entry.occurred_on),
      "split_type" => split_type_for_entry(view.entry),
      "split_mine_percentage" => format_decimal_ptbr(view.split_ratio_mine * 100, 1),
      "split_mine_amount" => format_amount_input(view.amount_mine_cents)
    }
  end

  defp split_type_for_entry(entry) do
    if entry.shared_split_mode == :income_ratio, do: "income_ratio", else: "fixed_amount"
  end

  defp shared_entry_preview_from_view(view) do
    %{
      split_ratio_mine: view.split_ratio_mine,
      split_ratio_theirs: view.split_ratio_theirs,
      amount_mine_cents: view.amount_mine_cents,
      amount_theirs_cents: view.amount_theirs_cents
    }
  end

  defp build_shared_entry_preview(_params, nil, _link, _user_id, fallback_preview) do
    fallback_preview ||
      %{
        split_ratio_mine: 0.0,
        split_ratio_theirs: 0.0,
        amount_mine_cents: 0,
        amount_theirs_cents: 0
      }
  end

  defp build_shared_entry_preview(params, entry, link, current_user_id, fallback_preview) do
    split_type = normalize_shared_split_type(Map.get(params, "split_type"))
    total_cents = parse_amount_or_default(Map.get(params, "amount_cents"), entry.amount_cents)

    case split_type do
      "income_ratio" ->
        reference_date = parse_date_or_default(Map.get(params, "occurred_on"), entry.occurred_on)

        {ratio_mine, ratio_theirs} =
          scoped_income_ratios_for_preview(entry, link, current_user_id, reference_date)

        {mine_cents, theirs_cents} = SplitCalculator.split_amount(total_cents, ratio_mine)

        %{
          split_ratio_mine: ratio_mine,
          split_ratio_theirs: ratio_theirs,
          amount_mine_cents: mine_cents,
          amount_theirs_cents: theirs_cents
        }

      "percentage" ->
        default_pct = fallback_percentage(fallback_preview)

        pct_value =
          params
          |> Map.get("split_mine_percentage")
          |> parse_percentage_or_default(default_pct)

        ratio_mine = clamp_ratio(pct_value / 100.0)
        ratio_theirs = 1.0 - ratio_mine
        {mine_cents, theirs_cents} = SplitCalculator.split_amount(total_cents, ratio_mine)

        %{
          split_ratio_mine: ratio_mine,
          split_ratio_theirs: ratio_theirs,
          amount_mine_cents: mine_cents,
          amount_theirs_cents: theirs_cents
        }

      "fixed_amount" ->
        default_mine_cents = fallback_mine_cents(fallback_preview)

        mine_cents =
          params
          |> Map.get("split_mine_amount")
          |> parse_amount_or_default(default_mine_cents)
          |> clamp_cents(total_cents)

        theirs_cents = max(total_cents - mine_cents, 0)
        ratio_mine = if total_cents > 0, do: mine_cents / total_cents, else: 0.0
        ratio_theirs = if total_cents > 0, do: theirs_cents / total_cents, else: 0.0

        %{
          split_ratio_mine: ratio_mine,
          split_ratio_theirs: ratio_theirs,
          amount_mine_cents: mine_cents,
          amount_theirs_cents: theirs_cents
        }
    end
  end

  defp normalize_shared_entry_edit_params(params, entry, preview) when is_map(params) do
    safe_preview =
      preview ||
        %{
          split_ratio_mine: 0.0,
          amount_mine_cents: 0
        }

    defaults =
      entry
      |> shared_entry_edit_form_params_from_entry()
      |> Map.merge(%{
        "split_mine_percentage" => format_decimal_ptbr(safe_preview.split_ratio_mine * 100, 1),
        "split_mine_amount" => format_amount_input(safe_preview.amount_mine_cents)
      })

    Map.merge(defaults, params)
  end

  defp normalize_shared_entry_edit_params(params, _entry, _preview), do: params

  defp shared_entry_edit_form_params_from_entry(nil) do
    %{
      "description" => "",
      "category" => "",
      "amount_cents" => "",
      "occurred_on" => "",
      "split_type" => "income_ratio",
      "split_mine_percentage" => "0,0",
      "split_mine_amount" => "0,00"
    }
  end

  defp shared_entry_edit_form_params_from_entry(entry) do
    %{
      "description" => entry.description || "",
      "category" => entry.category || "",
      "amount_cents" => format_amount_input(entry.amount_cents),
      "occurred_on" => DateSupport.format_pt_br(entry.occurred_on),
      "split_type" => split_type_for_entry(entry),
      "split_mine_percentage" => "0,0",
      "split_mine_amount" => "0,00"
    }
  end

  defp enrich_shared_entry_form_params(params, preview) when is_map(params) and is_map(preview) do
    split_type = normalize_shared_split_type(Map.get(params, "split_type"))

    case split_type do
      "income_ratio" ->
        params
        |> Map.put(
          "split_mine_percentage",
          format_decimal_ptbr(preview.split_ratio_mine * 100, 1)
        )
        |> Map.put("split_mine_amount", format_amount_input(preview.amount_mine_cents))

      "percentage" ->
        Map.put(params, "split_mine_amount", format_amount_input(preview.amount_mine_cents))

      "fixed_amount" ->
        Map.put(
          params,
          "split_mine_percentage",
          format_decimal_ptbr(preview.split_ratio_mine * 100, 1)
        )
    end
  end

  defp enrich_shared_entry_form_params(params, _preview), do: params

  defp normalize_shared_split_type(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "percentage" -> "percentage"
      "fixed_amount" -> "fixed_amount"
      _ -> "income_ratio"
    end
  end

  defp scoped_income_ratios_for_preview(entry, link, current_user_id, reference_date) do
    income_a =
      SplitCalculator.calculate_reference_income_with_carryover(
        link.user_a_id,
        reference_date.month,
        reference_date.year
      )

    income_b =
      SplitCalculator.calculate_reference_income_with_carryover(
        link.user_b_id,
        reference_date.month,
        reference_date.year
      )

    {ratio_a, ratio_b} =
      if income_a == 0 and income_b == 0 do
        if entry.user_id == link.user_b_id, do: {0.0, 1.0}, else: {1.0, 0.0}
      else
        SplitCalculator.calculate_split_ratio(income_a, income_b)
      end

    if current_user_id == link.user_a_id, do: {ratio_a, ratio_b}, else: {ratio_b, ratio_a}
  end

  defp parse_amount_or_default(value, default) do
    cond do
      is_integer(value) ->
        case AmountParser.parse(value) do
          {:ok, cents} when cents >= 0 -> cents
          _ -> default
        end

      is_binary(value) ->
        case AmountParser.parse(String.trim(value)) do
          {:ok, cents} when cents >= 0 -> cents
          _ -> default
        end

      true ->
        default
    end
  end

  defp parse_date_or_default(value, default) do
    case DateSupport.parse_date(value) do
      {:ok, %Date{} = date} -> date
      :error -> default
    end
  end

  defp parse_percentage_or_default(value, default) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace("%", "")
    |> String.replace(",", ".")
    |> case do
      "" ->
        default

      normalized ->
        case Float.parse(normalized) do
          {parsed, ""} -> parsed
          _ -> default
        end
    end
  end

  defp parse_percentage_or_default(value, _default) when is_float(value), do: value
  defp parse_percentage_or_default(value, _default) when is_integer(value), do: value * 1.0
  defp parse_percentage_or_default(_value, default), do: default

  defp fallback_percentage(%{split_ratio_mine: ratio}) when is_number(ratio), do: ratio * 100
  defp fallback_percentage(_preview), do: 0.0

  defp fallback_mine_cents(%{amount_mine_cents: cents}) when is_integer(cents), do: cents
  defp fallback_mine_cents(_preview), do: 0

  defp clamp_ratio(value) when value < 0.0, do: 0.0
  defp clamp_ratio(value) when value > 1.0, do: 1.0
  defp clamp_ratio(value), do: value

  defp clamp_cents(value, _total_cents) when value < 0, do: 0
  defp clamp_cents(value, total_cents) when value > total_cents, do: total_cents
  defp clamp_cents(value, _total_cents), do: value

  defp shared_entry_edit_validation_message(details) when is_map(details) do
    cond do
      Map.has_key?(details, :split_mine_percentage) ->
        "Informe uma porcentagem válida entre 0% e 100%."

      Map.has_key?(details, :split_mine_amount) ->
        "No valor fixo, informe um valor entre R$ 0,00 e o total da transação."

      Map.has_key?(details, :amount_cents) ->
        "Informe um valor total válido para a transação."

      Map.has_key?(details, :occurred_on) ->
        "Informe uma data válida para atualizar o lançamento."

      Map.has_key?(details, :shared_entry) ->
        "Este lançamento já possui pagamento alocado e não pode ser editado."

      true ->
        "Verifique os campos da edição antes de salvar."
    end
  end

  defp shared_entry_edit_validation_message(_details),
    do: "Não foi possível atualizar o lançamento compartilhado."

  defp format_amount_input(cents) when is_integer(cents) and cents >= 0 do
    integer_part = cents |> div(100) |> Integer.to_string()
    decimal_part = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    integer_part <> "," <> decimal_part
  end

  defp format_amount_input(_cents), do: ""

  defp payment_form(params \\ %{}) do
    defaults = %{
      "amount_cents" => "",
      "method" => "pix",
      "transferred_at" => DateSupport.format_pt_br(Date.utc_today()),
      "shared_entry_debt_id" => ""
    }

    to_form(Map.merge(defaults, params), as: :payment)
  end

  defp settlement_reversal_form(params \\ %{}) do
    defaults = %{
      "id" => "",
      "reason" => ""
    }

    to_form(Map.merge(defaults, params), as: :settlement_reversal)
  end

  defp create_settlement_record_for_target(scope, cycle_id, nil, attrs) do
    SharedFinance.create_settlement_record(scope, cycle_id, attrs)
  end

  defp create_settlement_record_for_target(scope, cycle_id, shared_entry_debt_id, attrs)
       when is_integer(shared_entry_debt_id) do
    SharedFinance.create_settlement_record_for_debt(scope, cycle_id, shared_entry_debt_id, attrs)
  end

  defp parse_int(value) when is_integer(value), do: {:ok, value}

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_int(_), do: :error

  defp parse_positive_page(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_page(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_positive_page(_value), do: 1

  defp parse_optional_debt_id(nil), do: {:ok, nil}
  defp parse_optional_debt_id(""), do: {:ok, nil}

  defp parse_optional_debt_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_optional_debt_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {debt_id, ""} when debt_id > 0 -> {:ok, debt_id}
      _ -> {:error, :invalid_debt}
    end
  end

  defp parse_optional_debt_id(_value), do: {:error, :invalid_debt}

  defp parse_amount_cents(nil), do: {:error, :invalid_amount}
  defp parse_amount_cents(""), do: {:error, :invalid_amount}

  defp parse_amount_cents(value) when is_binary(value) do
    case AmountParser.parse(String.trim(value)) do
      {:ok, cents} when cents > 0 -> {:ok, cents}
      _ -> {:error, :invalid_amount}
    end
  end

  defp parse_amount_cents(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp parse_amount_cents(_value), do: {:error, :invalid_amount}

  defp parse_method(nil), do: {:ok, :pix}
  defp parse_method(""), do: {:ok, :pix}

  defp parse_method(value) when is_binary(value) do
    case Enum.find(SettlementRecord.methods(), &(to_string(&1) == value)) do
      nil -> {:error, :invalid_method}
      method -> {:ok, method}
    end
  end

  defp parse_method(value) when is_atom(value) do
    if value in SettlementRecord.methods() do
      {:ok, value}
    else
      {:error, :invalid_method}
    end
  end

  defp parse_method(_value), do: {:error, :invalid_method}

  defp parse_transferred_at(nil), do: {:ok, DateTime.utc_now() |> DateTime.truncate(:second)}
  defp parse_transferred_at(""), do: {:ok, DateTime.utc_now() |> DateTime.truncate(:second)}

  defp parse_transferred_at(value) when is_binary(value) do
    with {:ok, date} <- DateSupport.parse_date(value),
         {:ok, datetime} <- DateTime.new(date, ~T[00:00:00], "Etc/UTC") do
      {:ok, datetime}
    else
      _ -> {:error, :invalid_date}
    end
  end

  defp parse_transferred_at(%DateTime{} = value), do: {:ok, value}
  defp parse_transferred_at(_value), do: {:error, :invalid_date}

  defp debt_by_id(debts, debt_id) when is_list(debts) and is_integer(debt_id) do
    case Enum.find(debts, &(&1.id == debt_id)) do
      nil -> {:error, :not_found}
      debt -> {:ok, debt}
    end
  end

  defp debt_by_id(_debts, _debt_id), do: {:error, :not_found}

  defp can_target_debt_payment?(debt, current_user_id)
       when is_map(debt) and is_integer(current_user_id) do
    debt.status in [:open, :partial] and debt.debtor_id == current_user_id and
      debt.outstanding_amount_cents > 0
  end

  defp can_target_debt_payment?(_debt, _current_user_id), do: false

  defp selected_payment_debt(payment_form, debts) do
    with debt_id <- payment_form[:shared_entry_debt_id].value,
         {:ok, parsed_debt_id} <- parse_optional_debt_id(debt_id),
         {:ok, debt} <- debt_by_id(debts, parsed_debt_id) do
      debt
    else
      _ -> nil
    end
  end

  defp format_cents(cents) when is_integer(cents) do
    abs_cents = abs(cents)
    integer_part = abs_cents |> div(100) |> Integer.to_string() |> add_thousands_separator()
    decimal_part = abs_cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    sign = if cents < 0, do: "-", else: ""

    "R$ #{sign}#{integer_part},#{decimal_part}"
  end

  defp format_cents(_), do: "R$ 0,00"

  defp settlement_method_options do
    SettlementRecord.method_options()
  end

  defp format_method(method) when is_atom(method), do: SettlementRecord.method_label(method)
  defp format_method(_), do: "—"

  defp settlement_record_amount_class(:active), do: "text-cyan-100"
  defp settlement_record_amount_class(:reversed), do: "text-amber-200 line-through"
  defp settlement_record_amount_class(_status), do: "text-slate-100"

  defp format_reversed_metadata(record) do
    reversed_at = format_date(record.reversed_at)

    reversed_by =
      case record.reversed_by do
        %{email: email} when is_binary(email) and email != "" -> email
        _ -> "conta vinculada"
      end

    reason =
      case record.reversal_reason do
        reason when is_binary(reason) ->
          cleaned = String.trim(reason)
          if cleaned == "", do: "", else: " • Motivo: #{cleaned}"

        _ ->
          ""
      end

    "Estornado em #{reversed_at} por #{reversed_by}#{reason}"
  end

  defp format_date(%DateTime{} = dt) do
    day = dt.day |> Integer.to_string() |> String.pad_leading(2, "0")
    month = dt.month |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{day}/#{month}/#{dt.year}"
  end

  defp format_date(_), do: "—"

  defp monthly_status_label(:open), do: "em aberto"
  defp monthly_status_label(:partial), do: "parcial"
  defp monthly_status_label(:settled), do: "quitado"
  defp monthly_status_label(_), do: "indefinido"

  defp debt_status_label(:open), do: "Em aberto"
  defp debt_status_label(:partial), do: "Parcial"
  defp debt_status_label(:settled), do: "Quitado"
  defp debt_status_label(_), do: "Indefinido"

  defp debt_status_badge_class(:open),
    do: "inline-flex items-center rounded-full border border-amber-300/50 bg-amber-300/14 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-amber-100"

  defp debt_status_badge_class(:partial),
    do: "inline-flex items-center rounded-full border border-cyan-300/45 bg-cyan-400/14 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-cyan-100"

  defp debt_status_badge_class(:settled),
    do: "inline-flex items-center rounded-full border border-emerald-300/50 bg-emerald-500/15 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-emerald-100"

  defp debt_status_badge_class(_),
    do: "inline-flex items-center rounded-full border border-slate-300/35 bg-slate-800/80 px-2 py-0.5 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-slate-100"

  defp format_pct(ratio) when is_number(ratio) do
    "#{format_decimal_ptbr(ratio * 100, 1)}%"
  end

  defp format_pct(_), do: "0,0%"

  defp format_decimal_ptbr(value, decimals) when is_number(value) and decimals >= 0 do
    rounded_value = Float.round(value * 1.0, decimals)
    sign = if rounded_value < 0, do: "-", else: ""

    normalized =
      rounded_value
      |> abs()
      |> :erlang.float_to_binary(decimals: decimals)

    case String.split(normalized, ".") do
      [integer_part, decimal_part] ->
        formatted_integer = add_thousands_separator(integer_part)
        sign <> formatted_integer <> "," <> decimal_part

      [integer_part] ->
        sign <> add_thousands_separator(integer_part)
    end
  end

  defp add_thousands_separator(value) when is_binary(value) do
    value
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(".")
    |> String.reverse()
  end

  defp format_reference_period_range(%Date{} = from_month, %Date{} = to_month) do
    "#{format_month_param(from_month)} até #{format_month_param(to_month)}"
  end

  defp shared_balance_chart_svg(metrics) do
    data = [
      {"Você", metrics.expected_pct_a, metrics.effective_pct_a},
      {"Outra conta", metrics.expected_pct_b, metrics.effective_pct_b}
    ]

    dataset = Dataset.new(data, ["conta", "esperado", "realizado"])

    Plot.new(dataset, Contex.BarChart, 560, 260,
      mapping: %{category_col: "conta", value_cols: ["esperado", "realizado"]},
      type: :grouped,
      data_labels: false,
      title: "Divisão esperada x realizada"
    )
    |> Plot.plot_options(%{legend_setting: :legend_bottom})
    |> Plot.to_svg()
  end

  defp shared_finance_path(socket, overrides) do
    params =
      socket
      |> current_shared_finance_params()
      |> Map.merge(overrides)

    ~p"/account-links/#{socket.assigns.link_id}?#{params}"
  end

  defp current_shared_finance_params(socket) do
    %{
      "from" => format_month_param(socket.assigns.global_filter_from_month),
      "to" => format_month_param(socket.assigns.global_filter_to_month),
      "settlement_month" => format_month_param(socket.assigns.settlement_focus_month)
    }
    |> maybe_put_non_blank_param("shared_entries_q", socket.assigns.shared_entries_filter_q)
    |> maybe_put_non_blank_param(
      "shared_entry_debts_q",
      socket.assigns.shared_entry_debts_filter_q
    )
    |> maybe_put_non_blank_param(
      "settlement_records_q",
      socket.assigns.settlement_records_filter_q
    )
  end

  defp shared_period_params(temporal_state) do
    %{
      from: temporal_state.from_month,
      to: temporal_state.to_month,
      reference_date: temporal_state.to_month
    }
  end

  defp resolve_temporal_state(scope, link_id, params) do
    {:ok, preference} = SharedFinance.get_view_preference(scope, link_id)

    {from_month, to_month, patch_required?} =
      case parse_global_filter_range(Map.get(params, "from"), Map.get(params, "to")) do
        {:ok, from_month, to_month} ->
          {from_month, to_month, false}

        _ ->
          case Map.get(params, "period") do
            "current_month" ->
              {:ok, from_month, to_month} = preset_to_month_range("current_month")
              {from_month, to_month, true}

            "last_3_months" ->
              {:ok, from_month, to_month} = preset_to_month_range("last_3_months")
              {from_month, to_month, true}

            _ ->
              case preference_month_range(preference) do
                {:ok, from_month, to_month} ->
                  {from_month, to_month, true}

                :error ->
                  {:ok, from_month, to_month} = preset_to_month_range("default_window")
                  {from_month, to_month, true}
              end
          end
      end

    settlement_candidate =
      case parse_month_param(Map.get(params, "settlement_month")) do
        {:ok, month} ->
          month

        :error ->
          preference_settlement_focus(preference) || to_month
      end

    settlement_focus_month = clamp_month_to_range(settlement_candidate, from_month, to_month)

    patch_params = %{
      "from" => format_month_param(from_month),
      "to" => format_month_param(to_month),
      "settlement_month" => format_month_param(settlement_focus_month)
    }

    clamped_settlement_focus? =
      Date.compare(settlement_candidate, settlement_focus_month) != :eq

    %{
      from_month: from_month,
      to_month: to_month,
      settlement_focus_month: settlement_focus_month,
      patch_required?:
        patch_required? or Map.get(params, "period") in ["current_month", "last_3_months", "all"] or
          Map.get(params, "from") != patch_params["from"] or
          Map.get(params, "to") != patch_params["to"] or
          Map.get(params, "settlement_month") != patch_params["settlement_month"],
      patch_params: patch_params,
      clamped_settlement_focus?: clamped_settlement_focus?
    }
  end

  defp apply_global_period_filter(socket, from_month, to_month) do
    settlement_focus_month =
      clamp_month_to_range(socket.assigns.settlement_focus_month, from_month, to_month)

    _ =
      SharedFinance.upsert_view_preference(
        socket.assigns.current_scope,
        socket.assigns.link_id,
        %{
          from_year: from_month.year,
          from_month: from_month.month,
          to_year: to_month.year,
          to_month: to_month.month,
          settlement_focus_year: settlement_focus_month.year,
          settlement_focus_month: settlement_focus_month.month
        }
      )

    clamp_flash? =
      Date.compare(settlement_focus_month, socket.assigns.settlement_focus_month) != :eq

    {:noreply,
     socket
     |> maybe_info_feedback(
       clamp_flash?,
       "Competência ajustada ao período ativo",
       "O fechamento mensal foi alinhado ao mês final do filtro"
     )
     |> assign(:global_filter_form, global_filter_form(from_month, to_month))
     |> push_patch(
       to:
         shared_finance_path(socket, %{
           "from" => format_month_param(from_month),
           "to" => format_month_param(to_month),
           "settlement_month" => format_month_param(settlement_focus_month)
         })
     )}
  end

  defp parse_global_filter_range(from_value, to_value) do
    from_result = parse_month_param(from_value)
    to_result = parse_month_param(to_value)

    case {from_result, to_result} do
      {{:ok, from_month}, {:ok, to_month}} ->
        months_total = months_between_inclusive(from_month, to_month)

        cond do
          months_total < 1 -> {:error, :invalid_month_range}
          months_total > @global_filter_max_months -> {:error, :invalid_month_range}
          true -> {:ok, from_month, to_month}
        end

      {:error, :error} ->
        {:error, :missing}

      _ ->
        {:error, :incomplete_range}
    end
  end

  defp parse_month_param(value) when is_binary(value) do
    cleaned = String.trim(value)

    case String.split(cleaned, "-", parts: 2) do
      [year_text, month_text] ->
        with {year, ""} <- Integer.parse(year_text),
             {month, ""} <- Integer.parse(month_text),
             true <- month >= 1 and month <= 12,
             {:ok, date} <- Date.new(year, month, 1) do
          {:ok, date}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_month_param(_), do: :error

  defp format_month_param(%Date{} = month) do
    "#{month.year}-#{month.month |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp global_filter_form(from_month, to_month) do
    to_form(
      %{
        "from_month" => format_month_param(from_month),
        "to_month" => format_month_param(to_month)
      },
      as: :period_filter
    )
  end

  defp settlement_focus_form(month) do
    to_form(%{"month" => format_month_param(month)}, as: :settlement_filter)
  end

  defp settlement_focus_options(from_month, to_month) do
    from_month
    |> enumerate_months(to_month)
    |> Enum.map(fn month ->
      month_label =
        month.month
        |> Integer.to_string()
        |> String.pad_leading(2, "0")
        |> Kernel.<>("/#{month.year}")

      {month_label, format_month_param(month)}
    end)
  end

  defp preference_month_range(nil), do: :error

  defp preference_month_range(preference) do
    with {:ok, from_month} <- build_month_date(preference.from_year, preference.from_month),
         {:ok, to_month} <- build_month_date(preference.to_year, preference.to_month),
         months_total <- months_between_inclusive(from_month, to_month),
         true <- months_total >= 1 and months_total <= @global_filter_max_months do
      {:ok, from_month, to_month}
    else
      _ -> :error
    end
  end

  defp preference_settlement_focus(nil), do: nil

  defp preference_settlement_focus(preference) do
    case build_month_date(preference.settlement_focus_year, preference.settlement_focus_month) do
      {:ok, month} -> month
      _ -> nil
    end
  end

  defp build_month_date(year, month) when is_integer(year) and is_integer(month) do
    Date.new(year, month, 1)
  end

  defp build_month_date(_, _), do: :error

  defp preset_to_month_range(preset) do
    case Map.get(@global_filter_presets, preset) do
      {from_offset, to_offset} ->
        current_month = Date.beginning_of_month(Date.utc_today())
        {:ok, shift_months(current_month, from_offset), shift_months(current_month, to_offset)}

      nil ->
        :error
    end
  end

  defp period_preset_button_class(from_month, to_month, preset) do
    class_active =
      "inline-flex items-center rounded-xl border border-cyan-300/75 bg-cyan-400/90 px-3 py-1.5 text-xs font-semibold text-slate-950 shadow-[0_14px_30px_-16px_rgba(34,211,238,0.75)] transition hover:bg-cyan-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-200/60"

    class_inactive =
      "inline-flex items-center rounded-xl border border-cyan-300/35 bg-slate-900/85 px-3 py-1.5 text-xs font-semibold text-cyan-100 transition hover:border-cyan-200/70 hover:bg-cyan-400/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/35"

    case preset_to_month_range(preset) do
      {:ok, preset_from, preset_to} ->
        if Date.compare(from_month, preset_from) == :eq and
             Date.compare(to_month, preset_to) == :eq do
          class_active
        else
          class_inactive
        end

      :error ->
        class_inactive
    end
  end

  defp clamp_month_to_range(%Date{} = month, %Date{} = from_month, %Date{} = to_month) do
    cond do
      Date.compare(month, from_month) == :lt -> to_month
      Date.compare(month, to_month) == :gt -> to_month
      true -> month
    end
  end

  defp months_between_inclusive(%Date{} = from_month, %Date{} = to_month) do
    from_index = from_month.year * 12 + from_month.month
    to_index = to_month.year * 12 + to_month.month
    to_index - from_index + 1
  end

  defp enumerate_months(%Date{} = from_month, %Date{} = to_month) do
    total = months_between_inclusive(from_month, to_month)

    Enum.map(0..(total - 1), fn offset ->
      shift_months(from_month, offset)
    end)
  end

  defp shift_months(%Date{} = date, delta_months) when is_integer(delta_months) do
    month_index = date.year * 12 + (date.month - 1) + delta_months
    new_year = div(month_index, 12)
    new_month = rem(month_index, 12) + 1

    Date.new!(new_year, new_month, 1)
  end

  defp normalize_list_filter_q(value) when is_binary(value), do: String.trim(value)
  defp normalize_list_filter_q(_value), do: ""

  defp default_if_blank(value, fallback) when is_binary(value) do
    if String.trim(value) == "", do: fallback, else: value
  end

  defp default_if_blank(nil, fallback), do: fallback
  defp default_if_blank(value, _fallback), do: value

  defp maybe_put_non_blank_param(params, _key, value) when value in [nil, ""], do: params
  defp maybe_put_non_blank_param(params, key, value), do: Map.put(params, key, value)

  defp shared_split_type_options do
    [
      {"Automática por renda", "income_ratio"},
      {"Percentual fixo", "percentage"},
      {"Valor fixo para você", "fixed_amount"}
    ]
  end

  defp info_feedback(socket, happened, next_step) do
    put_flash(socket, :info, FlashFeedback.compose(happened, next_step))
  end

  defp maybe_info_feedback(socket, true, happened, next_step) do
    info_feedback(socket, happened, next_step)
  end

  defp maybe_info_feedback(socket, false, _happened, _next_step), do: socket

  defp error_feedback(socket, happened, next_step) do
    put_flash(socket, :error, FlashFeedback.compose(happened, next_step))
  end

  defp track_funnel(action, outcome, metadata \\ %{}) do
    FunnelTelemetry.track_step(:shared_finance, action, outcome, metadata)
  end
end
