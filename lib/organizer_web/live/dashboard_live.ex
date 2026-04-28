defmodule OrganizerWeb.DashboardLive do
  use OrganizerWeb, :live_view

  alias Organizer.Accounts
  alias Organizer.DateSupport
  alias Organizer.Planning
  alias Organizer.Planning.AmountParser
  alias Organizer.Repo
  alias Organizer.SharedFinance
  alias OrganizerWeb.DashboardLive.{Filters, Insights}

  alias OrganizerWeb.DashboardLive.Components.{
    FinanceMetricsPanel,
    FinanceOperationsPanel
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

    case create_quick_finance_entry(socket.assigns.current_scope, normalized) do
      {:ok, _entry, share_result} ->
        kind = normalized["kind"]
        reset_form = quick_finance_defaults(kind, socket.assigns.account_links)

        flash_message =
          case share_result do
            :shared -> "Lançamento registrado e compartilhado no compartilhamento."
            :not_shared -> "Lançamento registrado."
          end

        {:noreply,
         socket
         |> assign(:quick_finance_kind, kind)
         |> assign(:quick_finance_preset, default_quick_finance_preset(kind))
         |> assign(:quick_finance_form, to_form(reset_form, as: :quick_finance))
         |> put_flash(:info, flash_message)
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

      {:error, {:validation, details}} ->
        {:noreply,
         socket
         |> assign(:quick_finance_kind, normalized["kind"])
         |> assign(:quick_finance_form, to_form(normalized, as: :quick_finance))
         |> put_flash(:error, quick_finance_creation_error_message(details))}

      _ ->
        {:noreply,
         socket
         |> assign(:quick_finance_kind, normalized["kind"])
         |> assign(:quick_finance_form, to_form(normalized, as: :quick_finance))
         |> put_flash(:error, "Não foi possível registrar o lançamento.")}
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
             |> put_flash(:error, "Não foi possível salvar preferência.")}
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
         |> put_flash(:info, "Atalhos: Alt+B (lançamento rápido), ? (ajuda)")}

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
        {:noreply, put_flash(socket, :error, "Lançamento não encontrado.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível carregar o lançamento.")}
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

    case Planning.update_finance_entry(socket.assigns.current_scope, id, normalized) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Lançamento atualizado.")
         |> assign(:editing_finance_id, nil)
         |> assign(:finance_edit_modal_entry, nil)
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Verifique os campos do lançamento.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Lançamento não encontrado.")
         |> assign(:editing_finance_id, nil)
         |> assign(:finance_edit_modal_entry, nil)}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível atualizar o lançamento.")}
    end
  end

  @impl true
  def handle_event("prompt_delete_finance", %{"id" => id} = params, socket) do
    pending_delete = %{
      id: id,
      category: Map.get(params, "category", "Lançamento sem categoria")
    }

    {:noreply, assign(socket, :pending_finance_delete, pending_delete)}
  end

  @impl true
  def handle_event("cancel_delete_finance", _params, socket) do
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
    {:noreply, perform_finance_deletion(socket, id)}
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
    |> assign(:onboarding_active, onboarding_active)
    |> assign(:onboarding_step, onboarding_progress.current_step)
    |> assign(:finance_flow_chart, %{loading: true, chart_svg: nil})
    |> assign(:finance_category_chart, %{loading: true, chart_svg: nil})
    |> assign(:finance_composition_chart, %{loading: true, chart_svg: nil})
    |> assign(:finance_highlights, Insights.default_finance_highlights())
    |> load_operation_collections()
    |> refresh_dashboard_insights()
  end

  defp load_operation_collections(socket, opts \\ []) do
    reset? = Keyword.get(opts, :reset, true)

    finance_filters =
      socket.assigns.finance_filters
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
    do: "Não foi possível registrar o lançamento."

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
        <a href="#quick-finance-hero" class="skip-link">
          Ir para finanças
        </a>
        <a href="#finance-operations-panel" class="skip-link">
          Ir para operação financeira
        </a>
        <a href="#finance-metrics-panel" class="skip-link">
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
        class="dashboard-shell flex flex-col gap-4 lg:gap-6"
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
    <header id={@id} class="surface-card rounded-2xl p-5 sm:p-6">
      <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div class="max-w-3xl">
          <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/62">
            {@eyebrow}
          </p>
          <h1 class="mt-2 text-2xl font-black text-base-content sm:text-3xl">
            {@title}
          </h1>
          <p class="mt-2 text-sm leading-6 text-base-content/76">
            {@description}
          </p>
        </div>
        <div class="flex size-12 items-center justify-center rounded-2xl border border-primary/56 bg-primary/22 text-primary">
          <.icon name={@icon} class="size-6" />
        </div>
      </div>
    </header>
    """
  end

  defp perform_finance_deletion(socket, id) do
    case Planning.delete_finance_entry(socket.assigns.current_scope, id) do
      {:ok, _entry} ->
        socket
        |> put_flash(:info, "Lançamento removido.")
        |> assign(:editing_finance_id, nil)
        |> assign(:finance_edit_modal_entry, nil)
        |> assign(:pending_finance_delete, nil)
        |> load_operation_collections()
        |> refresh_dashboard_insights()

      {:error, :not_found} ->
        socket
        |> assign(:pending_finance_delete, nil)
        |> put_flash(:error, "Lançamento não encontrado.")

      _ ->
        socket
        |> assign(:pending_finance_delete, nil)
        |> put_flash(:error, "Não foi possível remover o lançamento.")
    end
  end
end
