defmodule OrganizerWeb.SharedFinanceLive do
  use OrganizerWeb, :live_view

  alias Organizer.SharedFinance

  @shared_period_filters ["current_month", "last_3_months", "all"]

  @impl true
  def mount(%{"link_id" => link_id_param} = params, _session, socket) do
    scope = socket.assigns.current_scope
    selected_period = normalize_shared_period_filter(params)

    with {:ok, link_id} <- parse_int(link_id_param),
         {:ok, link} <- SharedFinance.get_account_link(scope, link_id) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Organizer.PubSub, "account_link:#{link_id}")
      end

      {:ok, views} = SharedFinance.list_shared_entries(scope, link_id, %{period: selected_period})

      {:ok, metrics} =
        SharedFinance.get_link_metrics(scope, link_id, Date.utc_today(), %{
          period: selected_period
        })

      {:ok, trend} = SharedFinance.get_recurring_variable_trend(scope, link_id)

      socket =
        socket
        |> assign(:link, link)
        |> assign(:link_id, link_id)
        |> assign(:selected_shared_period, selected_period)
        |> assign(:metrics, metrics)
        |> assign(:trend, trend)
        |> assign(:shared_entries_count, length(views))
        |> assign(:page_title, "Finanças Compartilhadas")
        |> stream_configure(:shared_entries, dom_id: &"shared-entry-view-#{&1.entry.id}")
        |> stream(:shared_entries, views)

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Vínculo não encontrado.")
         |> push_navigate(to: ~p"/account-links")}
    end
  end

  @impl true
  def handle_params(%{"link_id" => link_id_param}, _uri, socket) do
    case parse_int(link_id_param) do
      {:ok, link_id} -> {:noreply, assign(socket, :link_id, link_id)}
      :error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("share_entry", %{"entry_id" => entry_id}, socket) do
    scope = socket.assigns.current_scope
    link_id = socket.assigns.link_id

    with {:ok, parsed_entry_id} <- parse_int(entry_id),
         {:ok, _entry} <- SharedFinance.share_finance_entry(scope, parsed_entry_id, link_id) do
      {:noreply, reload_shared_data(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Não foi possível compartilhar o lançamento.")}
    end
  end

  @impl true
  def handle_event("unshare_entry", %{"entry_id" => entry_id}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, parsed_entry_id} <- parse_int(entry_id),
         {:ok, _entry} <- SharedFinance.unshare_finance_entry(scope, parsed_entry_id) do
      {:noreply, reload_shared_data(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Não foi possível remover o compartilhamento.")}
    end
  end

  @impl true
  def handle_event("set_shared_period", %{"period" => period}, socket)
      when period in @shared_period_filters do
    {:noreply,
     socket
     |> assign(:selected_shared_period, period)
     |> reload_shared_data()}
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
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide={true}>
      <section class="collab-shell mx-auto max-w-6xl space-y-6">
        <header class="surface-card collab-hero rounded-3xl p-6 sm:p-8">
          <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div class="space-y-2">
              <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/62">
                Finanças compartilhadas
              </p>
              <h1 class="text-3xl font-black tracking-[-0.02em] text-base-content">
                Visão conjunta do vínculo
              </h1>
              <p class="max-w-2xl text-sm leading-6 text-base-content/78">
                Monitore total compartilhado, proporção entre contas e tendência recorrente sem sair do fluxo colaborativo.
              </p>
            </div>
            <.link navigate={~p"/account-links"} class="btn btn-outline btn-sm sm:btn-md">
              <.icon name="hero-arrow-left" class="size-4" /> Voltar para vínculos
            </.link>
          </div>
        </header>

        <section id="link-metrics-panel" class="surface-card rounded-3xl p-5 sm:p-6">
          <div class="flex items-center justify-between gap-3">
            <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
              Resumo do período
            </h2>
            <span class="text-xs text-base-content/62">
              {format_reference_period(@metrics, @selected_shared_period)}
            </span>
          </div>

          <div class="mt-4 flex flex-wrap gap-2">
            <button
              id="shared-period-filter-current-month"
              type="button"
              phx-click="set_shared_period"
              phx-value-period="current_month"
              class={[
                "btn btn-xs",
                @selected_shared_period == "current_month" && "btn-primary",
                @selected_shared_period != "current_month" && "btn-soft"
              ]}
            >
              Mês atual
            </button>
            <button
              id="shared-period-filter-last-3-months"
              type="button"
              phx-click="set_shared_period"
              phx-value-period="last_3_months"
              class={[
                "btn btn-xs",
                @selected_shared_period == "last_3_months" && "btn-primary",
                @selected_shared_period != "last_3_months" && "btn-soft"
              ]}
            >
              Últimos 3 meses
            </button>
            <button
              id="shared-period-filter-all"
              type="button"
              phx-click="set_shared_period"
              phx-value-period="all"
              class={[
                "btn btn-xs",
                @selected_shared_period == "all" && "btn-primary",
                @selected_shared_period != "all" && "btn-soft"
              ]}
            >
              Tudo
            </button>
          </div>

          <div class="collab-stats-grid mt-4 grid gap-3 sm:grid-cols-3">
            <article class="collab-stat micro-surface rounded-2xl p-4 text-center">
              <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">
                Total compartilhado
              </p>
              <p class="mt-1 text-xl font-mono font-semibold text-base-content">
                {format_cents(@metrics.total_cents)}
              </p>
            </article>

            <article class="collab-stat micro-surface rounded-2xl p-4 text-center">
              <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">Você arcou</p>
              <p class="mt-1 text-xl font-mono font-semibold text-info">
                {format_cents(@metrics.paid_a_cents)}
              </p>
            </article>

            <article class="collab-stat micro-surface rounded-2xl p-4 text-center">
              <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">
                Outra conta arcou
              </p>
              <p class="mt-1 text-xl font-mono font-semibold text-success">
                {format_cents(@metrics.paid_b_cents)}
              </p>
            </article>
          </div>

          <div
            :if={@metrics.imbalance_detected}
            id="imbalance-indicator"
            class="mt-4 flex items-center gap-2 rounded-xl border border-warning/35 bg-warning/14 px-3 py-2"
          >
            <.icon name="hero-exclamation-triangle" class="size-4 text-warning" />
            <span class="text-sm text-warning-content">
              Desequilíbrio detectado. A divisão atual difere mais de 5% do esperado.
            </span>
          </div>
        </section>

        <section class="surface-card rounded-3xl p-5 sm:p-6">
          <div class="flex items-center justify-between gap-3">
            <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
              Lançamentos compartilhados
            </h2>
            <span class="text-xs text-base-content/62">{@shared_entries_count} item(ns)</span>
          </div>

          <div id="shared-entries-list" phx-update="stream" class="mt-4 space-y-2">
            <div
              :if={@shared_entries_count == 0}
              id="shared-entries-empty-state"
              class="ds-empty-state rounded-2xl border border-dashed px-4 py-6 text-sm text-base-content/72"
            >
              Ainda não há lançamentos compartilhados neste vínculo.
            </div>

            <div
              :for={{id, view} <- @streams.shared_entries}
              id={id}
              class="shared-entry-row micro-surface flex flex-col gap-3 rounded-2xl p-4 sm:flex-row sm:items-center sm:justify-between"
            >
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-medium text-base-content/92">
                  {view.entry.description || view.entry.category}
                </p>
                <p class="mt-1 text-xs font-mono text-base-content/62">
                  {format_cents(view.entry.amount_cents)} • Você: {format_pct(view.split_ratio_mine)} ({format_cents(
                    view.amount_mine_cents
                  )}) • Outra conta: {format_pct(view.split_ratio_theirs)} ({format_cents(
                    view.amount_theirs_cents
                  )})
                </p>
              </div>

              <button
                id={"unshare-entry-#{view.entry.id}"}
                type="button"
                phx-click="unshare_entry"
                phx-value-entry_id={view.entry.id}
                class="btn btn-outline btn-xs btn-error shrink-0"
              >
                Remover
              </button>
            </div>
          </div>
        </section>

        <section id="recurring-variable-trend" class="surface-card rounded-3xl p-5 sm:p-6">
          <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
            Tendência de recorrentes variáveis (6 meses)
          </h2>

          <%= if @trend == [] do %>
            <p class="mt-3 text-sm text-base-content/58">Nenhum dado disponível neste período.</p>
          <% else %>
            <ul class="mt-3 space-y-2">
              <%= for mt <- @trend do %>
                <li class="trend-list-item micro-surface flex items-center justify-between rounded-xl p-3">
                  <span class="text-sm font-mono text-base-content/72">{mt.month}/{mt.year}</span>
                  <span class="text-sm font-semibold font-mono text-base-content/92">
                    {format_cents(mt.total_cents)}
                  </span>
                </li>
              <% end %>
            </ul>
          <% end %>
        </section>
      </section>
    </Layouts.app>
    """
  end

  defp reload_shared_data(socket) do
    scope = socket.assigns.current_scope
    link_id = socket.assigns.link_id
    selected_period = socket.assigns.selected_shared_period

    {:ok, views} = SharedFinance.list_shared_entries(scope, link_id, %{period: selected_period})

    {:ok, metrics} =
      SharedFinance.get_link_metrics(scope, link_id, Date.utc_today(), %{period: selected_period})

    {:ok, trend} = SharedFinance.get_recurring_variable_trend(scope, link_id)

    socket
    |> assign(:metrics, metrics)
    |> assign(:trend, trend)
    |> assign(:shared_entries_count, length(views))
    |> stream(:shared_entries, views, reset: true)
  end

  defp parse_int(value) when is_integer(value), do: {:ok, value}

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_int(_), do: :error

  defp format_cents(cents) when is_integer(cents) do
    abs_cents = abs(cents)
    integer_part = abs_cents |> div(100) |> Integer.to_string() |> add_thousands_separator()
    decimal_part = abs_cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    sign = if cents < 0, do: "-", else: ""

    "R$ #{sign}#{integer_part},#{decimal_part}"
  end

  defp format_cents(_), do: "R$ 0,00"

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

  defp format_reference_period(metrics, period) do
    month = metrics.reference_month |> to_string() |> String.pad_leading(2, "0")
    "#{shared_period_label(period)} • até #{month}/#{metrics.reference_year}"
  end

  defp shared_period_label("current_month"), do: "Mês atual"
  defp shared_period_label("last_3_months"), do: "Últimos 3 meses"
  defp shared_period_label(_), do: "Tudo"

  @spec normalize_shared_period_filter(map()) :: String.t()
  defp normalize_shared_period_filter(params) do
    case Map.get(params, "period") do
      "current_month" -> "current_month"
      "last_3_months" -> "last_3_months"
      _ -> "all"
    end
  end
end
