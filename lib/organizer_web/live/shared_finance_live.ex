defmodule OrganizerWeb.SharedFinanceLive do
  use OrganizerWeb, :live_view

  alias Organizer.SharedFinance

  @impl true
  def mount(%{"link_id" => link_id_str} = _params, _session, socket) do
    scope = socket.assigns.current_scope
    link_id = String.to_integer(link_id_str)

    case SharedFinance.get_account_link(scope, link_id) do
      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Vínculo não encontrado.")
         |> push_navigate(to: ~p"/account-links")}

      {:ok, link} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Organizer.PubSub, "account_link:#{link_id}")
        end

        {:ok, views} = SharedFinance.list_shared_entries(scope, link_id)
        {:ok, metrics} = SharedFinance.get_link_metrics(scope, link_id, Date.utc_today())
        {:ok, trend} = SharedFinance.get_recurring_variable_trend(scope, link_id)

        socket =
          socket
          |> assign(:link, link)
          |> assign(:link_id, link_id)
          |> assign(:metrics, metrics)
          |> assign(:trend, trend)
          |> assign(:page_title, "Finanças Compartilhadas")
          |> stream_configure(:shared_entries, dom_id: &"shared-entry-view-#{&1.entry.id}")
          |> stream(:shared_entries, views)

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"link_id" => link_id_str}, _uri, socket) do
    {:noreply, assign(socket, :link_id, String.to_integer(link_id_str))}
  end

  @impl true
  def handle_event("share_entry", %{"entry_id" => entry_id}, socket) do
    scope = socket.assigns.current_scope
    link_id = socket.assigns.link_id

    case SharedFinance.share_finance_entry(scope, String.to_integer(entry_id), link_id) do
      {:ok, _entry} ->
        {:ok, views} = SharedFinance.list_shared_entries(scope, link_id)
        {:ok, metrics} = SharedFinance.get_link_metrics(scope, link_id, Date.utc_today())

        {:noreply,
         socket
         |> assign(:metrics, metrics)
         |> stream(:shared_entries, views, reset: true)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível compartilhar o lançamento.")}
    end
  end

  @impl true
  def handle_event("unshare_entry", %{"entry_id" => entry_id}, socket) do
    scope = socket.assigns.current_scope
    link_id = socket.assigns.link_id

    case SharedFinance.unshare_finance_entry(scope, String.to_integer(entry_id)) do
      {:ok, _entry} ->
        {:ok, views} = SharedFinance.list_shared_entries(scope, link_id)
        {:ok, metrics} = SharedFinance.get_link_metrics(scope, link_id, Date.utc_today())

        {:noreply,
         socket
         |> assign(:metrics, metrics)
         |> stream(:shared_entries, views, reset: true)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível remover o compartilhamento.")}
    end
  end

  @impl true
  def handle_info({:shared_entry_updated, _entry}, socket) do
    scope = socket.assigns.current_scope
    link_id = socket.assigns.link_id

    {:ok, views} = SharedFinance.list_shared_entries(scope, link_id)
    {:ok, metrics} = SharedFinance.get_link_metrics(scope, link_id, Date.utc_today())

    {:noreply,
     socket
     |> assign(:metrics, metrics)
     |> stream(:shared_entries, views, reset: true)}
  end

  @impl true
  def handle_info({:shared_entry_removed, _entry}, socket) do
    scope = socket.assigns.current_scope
    link_id = socket.assigns.link_id

    {:ok, views} = SharedFinance.list_shared_entries(scope, link_id)
    {:ok, metrics} = SharedFinance.get_link_metrics(scope, link_id, Date.utc_today())

    {:noreply,
     socket
     |> assign(:metrics, metrics)
     |> stream(:shared_entries, views, reset: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-4xl mx-auto p-6 space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-semibold text-base-content">Finanças Compartilhadas</h1>
          <.link navigate={~p"/account-links"} class="btn btn-outline btn-sm">
            ← Vínculos
          </.link>
        </div>

        <%!-- Metrics panel --%>
        <div id="link-metrics-panel" class="surface-card p-5 space-y-3">
          <h2 class="text-lg font-semibold text-base-content">Resumo do mês</h2>

          <div class="grid grid-cols-3 gap-4">
            <div class="micro-surface p-3 rounded-lg text-center">
              <p class="text-xs text-base-content/60 uppercase tracking-wide mb-1">
                Total compartilhado
              </p>
              <p class="text-xl font-mono font-semibold text-base-content">
                {format_cents(@metrics.total_cents)}
              </p>
            </div>
            <div class="micro-surface p-3 rounded-lg text-center">
              <p class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Você arcou</p>
              <p class="text-xl font-mono font-semibold text-cyan-400">
                {format_cents(@metrics.paid_a_cents)}
              </p>
            </div>
            <div class="micro-surface p-3 rounded-lg text-center">
              <p class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Parceiro arcou</p>
              <p class="text-xl font-mono font-semibold text-emerald-400">
                {format_cents(@metrics.paid_b_cents)}
              </p>
            </div>
          </div>

          <%= if @metrics.imbalance_detected do %>
            <div
              id="imbalance-indicator"
              class="flex items-center gap-2 p-3 rounded-lg bg-warning/10 border border-warning/30"
            >
              <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-warning" />
              <span class="text-sm text-warning font-medium">
                Desequilíbrio detectado — a divisão atual difere mais de 5% do esperado.
              </span>
            </div>
          <% end %>
        </div>

        <%!-- Shared entries list --%>
        <div class="surface-card p-5">
          <h2 class="text-lg font-semibold text-base-content mb-4">Lançamentos compartilhados</h2>

          <div id="shared-entries-list" phx-update="stream" class="space-y-2">
            <div
              :for={{id, view} <- @streams.shared_entries}
              id={id}
              class="micro-surface flex items-center justify-between p-3 rounded-lg"
            >
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-base-content truncate">
                  {view.entry.description || view.entry.category}
                </p>
                <p class="text-xs text-base-content/60 font-mono">
                  {format_cents(view.entry.amount_cents)} · Você: {format_pct(view.split_ratio_mine)} ({format_cents(
                    view.amount_mine_cents
                  )}) / Parceiro: {format_pct(view.split_ratio_theirs)} ({format_cents(
                    view.amount_theirs_cents
                  )})
                </p>
              </div>
              <button
                id={"unshare-entry-#{view.entry.id}"}
                phx-click="unshare_entry"
                phx-value-entry_id={view.entry.id}
                class="btn btn-outline btn-xs btn-error ml-3 shrink-0"
              >
                Remover
              </button>
            </div>
          </div>
        </div>

        <%!-- Recurring variable trend --%>
        <div id="recurring-variable-trend" class="surface-card p-5">
          <h2 class="text-lg font-semibold text-base-content mb-4">
            Tendência — recorrentes variáveis (6 meses)
          </h2>

          <%= if @trend == [] do %>
            <p class="text-sm text-base-content/50">Nenhum dado disponível.</p>
          <% else %>
            <ul class="space-y-2">
              <%= for mt <- @trend do %>
                <li class="flex items-center justify-between micro-surface p-2 rounded-lg">
                  <span class="text-sm text-base-content/70 font-mono">{mt.month}/{mt.year}</span>
                  <span class="text-sm font-semibold text-base-content font-mono">
                    {format_cents(mt.total_cents)}
                  </span>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_cents(cents) when is_integer(cents) do
    "R$ #{:erlang.float_to_binary(cents / 100, decimals: 2)}"
  end

  defp format_cents(_), do: "R$ 0,00"

  defp format_pct(ratio) when is_float(ratio) do
    "#{:erlang.float_to_binary(ratio * 100, decimals: 1)}%"
  end

  defp format_pct(_), do: "0.0%"
end
