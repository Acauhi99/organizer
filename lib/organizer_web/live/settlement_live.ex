defmodule OrganizerWeb.SettlementLive do
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
        {:ok, cycle} =
          SharedFinance.get_or_create_settlement_cycle(scope, link_id, Date.utc_today())

        {:ok, records} = SharedFinance.list_settlement_records(scope, cycle.id)

        if connected?(socket) do
          Phoenix.PubSub.subscribe(Organizer.PubSub, "account_link:#{link_id}")
        end

        socket =
          socket
          |> assign(:link, link)
          |> assign(:link_id, link_id)
          |> assign(:cycle, cycle)
          |> assign(:record_form, to_form(%{}, as: :record))
          |> assign(:page_title, "Acerto de Contas")
          |> stream(:settlement_records, records)

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"link_id" => link_id_str}, _uri, socket) do
    {:noreply, assign(socket, :link_id, String.to_integer(link_id_str))}
  end

  @impl true
  def handle_event("create_record", %{"record" => attrs}, socket) do
    scope = socket.assigns.current_scope
    cycle = socket.assigns.cycle

    amount_cents =
      case Map.get(attrs, "amount_cents") do
        nil -> 0
        "" -> 0
        val -> String.to_integer(val)
      end

    method =
      case Map.get(attrs, "method") do
        nil -> :pix
        "" -> :pix
        val -> String.to_existing_atom(val)
      end

    transferred_at =
      case Map.get(attrs, "transferred_at") do
        nil -> DateTime.utc_now() |> DateTime.truncate(:second)
        "" -> DateTime.utc_now() |> DateTime.truncate(:second)
        date_str -> Date.from_iso8601!(date_str) |> DateTime.new!(~T[00:00:00], "Etc/UTC")
      end

    record_attrs = %{
      amount_cents: amount_cents,
      method: method,
      transferred_at: transferred_at
    }

    case SharedFinance.create_settlement_record(scope, cycle.id, record_attrs) do
      {:ok, _record} ->
        {:ok, records} = SharedFinance.list_settlement_records(scope, cycle.id)

        {:noreply,
         socket
         |> stream(:settlement_records, records, reset: true)
         |> assign(:record_form, to_form(%{}, as: :record))}

      {:error, {:validation, _}} ->
        {:noreply, put_flash(socket, :error, "Valor deve ser maior que zero.")}

      {:error, _err} ->
        {:noreply, put_flash(socket, :error, "Não foi possível registrar a transferência.")}
    end
  end

  @impl true
  def handle_event("confirm_settlement", _params, socket) do
    scope = socket.assigns.current_scope
    cycle = socket.assigns.cycle

    case SharedFinance.confirm_settlement(scope, cycle.id) do
      {:ok, updated_cycle} ->
        {:noreply,
         socket
         |> assign(:cycle, updated_cycle)
         |> put_flash(:info, "Confirmação registrada.")}

      {:error, :awaiting_counterpart_confirmation} ->
        {:noreply, put_flash(socket, :info, "Aguardando confirmação do parceiro.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível confirmar o acerto.")}
    end
  end

  @impl true
  def handle_info({:settlement_record_created, _record}, socket) do
    scope = socket.assigns.current_scope
    cycle = socket.assigns.cycle

    {:ok, records} = SharedFinance.list_settlement_records(scope, cycle.id)
    {:noreply, stream(socket, :settlement_records, records, reset: true)}
  end

  @impl true
  def handle_info({:settlement_cycle_settled, cycle}, socket) do
    {:noreply, assign(socket, :cycle, cycle)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-3xl mx-auto p-6 space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-semibold text-base-content">Acerto de Contas</h1>
          <.link navigate={~p"/account-links/#{@link_id}"} class="btn btn-outline btn-sm">
            ← Finanças
          </.link>
        </div>

        <%!-- Balance display --%>
        <div id="settlement-balance" class="surface-card p-5 space-y-3">
          <div class="flex items-center justify-between">
            <div>
              <%= cond do %>
                <% @cycle.balance_cents > 0 and not is_nil(@cycle.debtor_id) -> %>
                  <p class="text-base-content font-medium">
                    {debtor_label(@cycle, @link)} deve
                    <span class="font-mono font-semibold text-warning">
                      {format_cents(@cycle.balance_cents)}
                    </span>
                    a {creditor_label(@cycle, @link)}
                  </p>
                <% @cycle.balance_cents == 0 -> %>
                  <p class="text-emerald-400 font-medium">Saldo zerado</p>
                <% true -> %>
                  <p class="text-base-content/70 font-medium">
                    Saldo: {format_cents(@cycle.balance_cents)}
                  </p>
              <% end %>
            </div>
            <span class={[
              "badge badge-sm font-mono",
              if(@cycle.status == :settled, do: "badge-success", else: "badge-warning")
            ]}>
              {if @cycle.status == :settled, do: "Quitado", else: "Aberto"}
            </span>
          </div>
        </div>

        <%!-- Settlement records list --%>
        <div class="surface-card p-5">
          <h2 class="text-lg font-semibold text-base-content mb-4">Transferências registradas</h2>
          <div id="settlement-records-list" phx-update="stream" class="space-y-2">
            <div
              :for={{id, record} <- @streams.settlement_records}
              id={id}
              class="micro-surface flex items-center justify-between p-3 rounded-lg"
            >
              <div>
                <p class="text-sm font-medium text-base-content font-mono">
                  {format_cents(record.amount_cents)}
                </p>
                <p class="text-xs text-base-content/60">
                  {String.upcase(to_string(record.method))} · {format_date(record.transferred_at)}
                </p>
              </div>
            </div>
          </div>
        </div>

        <%!-- New record form --%>
        <div class="surface-card p-5">
          <h2 class="text-lg font-semibold text-base-content mb-4">Registrar transferência</h2>
          <.form
            for={@record_form}
            id="new-record-form"
            phx-submit="create_record"
            class="space-y-4"
          >
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <div>
                <label class="block text-xs font-medium text-base-content/70 uppercase tracking-wide mb-1">
                  Valor (centavos)
                </label>
                <.input
                  field={@record_form[:amount_cents]}
                  type="number"
                  placeholder="Ex: 5000"
                  min="1"
                />
              </div>
              <div>
                <label class="block text-xs font-medium text-base-content/70 uppercase tracking-wide mb-1">
                  Método
                </label>
                <.input
                  field={@record_form[:method]}
                  type="select"
                  options={[{"PIX", "pix"}, {"TED", "ted"}]}
                />
              </div>
              <div>
                <label class="block text-xs font-medium text-base-content/70 uppercase tracking-wide mb-1">
                  Data da transferência
                </label>
                <.input field={@record_form[:transferred_at]} type="date" />
              </div>
            </div>
            <button type="submit" class="btn btn-primary w-full sm:w-auto">
              Registrar transferência
            </button>
          </.form>
        </div>

        <%!-- Confirmation and settlement actions --%>
        <div class="surface-card p-5 space-y-3">
          <h2 class="text-lg font-semibold text-base-content">Confirmação</h2>
          <div class="flex flex-col sm:flex-row gap-3">
            <button
              id="confirm-settlement-btn"
              phx-click="confirm_settlement"
              class="btn btn-outline btn-primary"
            >
              Confirmar ciência do saldo
            </button>

            <button
              id="settle-btn"
              phx-click="settle"
              class={[
                "btn btn-success",
                not (@cycle.confirmed_by_a and @cycle.confirmed_by_b) &&
                  "btn-disabled opacity-50 cursor-not-allowed"
              ]}
              {if not (@cycle.confirmed_by_a and @cycle.confirmed_by_b),
                do: [disabled: true],
                else: []}
            >
              Quitar ciclo
              <%= if not (@cycle.confirmed_by_a and @cycle.confirmed_by_b) do %>
                <span class="text-xs opacity-70">(aguardando confirmação bilateral)</span>
              <% end %>
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_cents(cents) when is_integer(cents) do
    "R$ #{:erlang.float_to_binary(cents / 100, decimals: 2)}"
  end

  defp format_cents(_), do: "R$ 0,00"

  defp format_date(%DateTime{} = dt) do
    "#{dt.day}/#{dt.month}/#{dt.year}"
  end

  defp format_date(_), do: "—"

  defp debtor_label(cycle, link) do
    if cycle.debtor_id == link.user_a_id, do: link.user_a.email, else: link.user_b.email
  end

  defp creditor_label(cycle, link) do
    if cycle.debtor_id == link.user_a_id, do: link.user_b.email, else: link.user_a.email
  end
end
