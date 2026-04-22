defmodule OrganizerWeb.SettlementLive do
  use OrganizerWeb, :live_view

  alias Organizer.SharedFinance
  alias Organizer.SharedFinance.SettlementRecord

  @impl true
  def mount(%{"link_id" => link_id_param}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, link_id} <- parse_int(link_id_param),
         {:ok, link} <- SharedFinance.get_account_link(scope, link_id),
         {:ok, cycle} <-
           SharedFinance.get_or_create_settlement_cycle(scope, link_id, Date.utc_today()),
         {:ok, records} <- SharedFinance.list_settlement_records(scope, cycle.id) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Organizer.PubSub, "account_link:#{link_id}")
      end

      socket =
        socket
        |> assign(:link, link)
        |> assign(:link_id, link_id)
        |> assign(:cycle, cycle)
        |> assign(:settlement_records_count, length(records))
        |> assign(:record_form, record_form())
        |> assign(:page_title, "Acerto de Contas")
        |> stream(:settlement_records, records)

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
  def handle_event("create_record", %{"record" => attrs}, socket) do
    scope = socket.assigns.current_scope
    cycle = socket.assigns.cycle

    with {:ok, amount_cents} <- parse_amount_cents(Map.get(attrs, "amount_cents")),
         {:ok, method} <- parse_method(Map.get(attrs, "method")),
         {:ok, transferred_at} <- parse_transferred_at(Map.get(attrs, "transferred_at")),
         {:ok, _record} <-
           SharedFinance.create_settlement_record(scope, cycle.id, %{
             amount_cents: amount_cents,
             method: method,
             transferred_at: transferred_at
           }),
         {:ok, records} <- SharedFinance.list_settlement_records(scope, cycle.id) do
      {:noreply,
       socket
       |> assign(:settlement_records_count, length(records))
       |> stream(:settlement_records, records, reset: true)
       |> assign(:record_form, record_form())
       |> put_flash(:info, "Transferência registrada.")}
    else
      {:error, :invalid_amount} ->
        {:noreply,
         socket
         |> assign(:record_form, record_form(attrs))
         |> put_flash(:error, "Valor deve ser um inteiro maior que zero (centavos).")}

      {:error, :invalid_method} ->
        {:noreply,
         socket
         |> assign(:record_form, record_form(attrs))
         |> put_flash(:error, "Método inválido. Selecione uma opção da lista.")}

      {:error, :invalid_date} ->
        {:noreply,
         socket
         |> assign(:record_form, record_form(attrs))
         |> put_flash(:error, "Data inválida. Use um valor no formato AAAA-MM-DD.")}

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
        {:noreply, put_flash(socket, :info, "Aguardando confirmação da outra conta.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível confirmar o acerto.")}
    end
  end

  @impl true
  def handle_event("settle", _params, socket) do
    cycle = socket.assigns.cycle

    cond do
      cycle.status == :settled ->
        {:noreply, put_flash(socket, :info, "Este ciclo já está quitado.")}

      not (cycle.confirmed_by_a and cycle.confirmed_by_b) ->
        {:noreply,
         put_flash(socket, :info, "A quitação fica disponível após confirmação bilateral.")}

      true ->
        # A própria confirmação bilateral efetiva a quitação no domínio.
        {:noreply, put_flash(socket, :info, "Ciclo quitado e sincronizado com sucesso.")}
    end
  end

  @impl true
  def handle_info({:settlement_record_created, _record}, socket) do
    scope = socket.assigns.current_scope
    cycle = socket.assigns.cycle

    {:ok, records} = SharedFinance.list_settlement_records(scope, cycle.id)

    {:noreply,
     socket
     |> assign(:settlement_records_count, length(records))
     |> stream(:settlement_records, records, reset: true)}
  end

  @impl true
  def handle_info({:settlement_cycle_settled, cycle}, socket) do
    {:noreply, assign(socket, :cycle, cycle)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide={true}>
      <section class="collab-shell responsive-shell mx-auto max-w-6xl space-y-6">
        <header class="surface-card collab-hero rounded-3xl p-6 sm:p-8">
          <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div class="space-y-2">
              <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/62">
                Acerto colaborativo
              </p>
              <h1 class="text-2xl font-black tracking-[-0.02em] text-base-content sm:text-3xl">
                Acerto de contas do vínculo
              </h1>
              <p class="max-w-2xl text-sm leading-6 text-base-content/78">
                Registre transferências, valide saldo bilateral e finalize o ciclo com transparência.
              </p>
            </div>
            <.link navigate={~p"/account-links/#{@link_id}"} class="btn btn-outline btn-sm sm:btn-md">
              <.icon name="hero-arrow-left" class="size-4" /> Voltar para finanças
            </.link>
          </div>
        </header>

        <section id="settlement-balance" class="surface-card rounded-3xl p-5 sm:p-6">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <%= cond do %>
                <% @cycle.balance_cents > 0 and not is_nil(@cycle.debtor_id) -> %>
                  <p class="text-sm text-base-content/82">
                    {debtor_label(@cycle, @link)} deve
                    <span class="break-words font-mono font-semibold text-warning">
                      {format_cents(@cycle.balance_cents)}
                    </span>
                    a {creditor_label(@cycle, @link)}
                  </p>
                <% @cycle.balance_cents == 0 -> %>
                  <p class="text-sm font-semibold text-success">Saldo zerado</p>
                <% true -> %>
                  <p class="text-sm text-base-content/72">
                    Saldo: {format_cents(@cycle.balance_cents)}
                  </p>
              <% end %>
            </div>

            <span class={[
              "settlement-status-pill inline-flex w-fit rounded-full border px-3 py-1 text-xs font-semibold uppercase tracking-[0.12em]",
              if(@cycle.status == :settled,
                do: "border-success/40 bg-success/14 text-success-content",
                else: "border-warning/35 bg-warning/14 text-warning-content"
              )
            ]}>
              {if @cycle.status == :settled, do: "Quitado", else: "Aberto"}
            </span>
          </div>
        </section>

        <section class="surface-card rounded-3xl p-5 sm:p-6">
          <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
            Transferências registradas
          </h2>
          <div id="settlement-records-list" phx-update="stream" class="mt-4 space-y-2">
            <div
              :if={@settlement_records_count == 0}
              id="settlement-empty-state"
              class="ds-empty-state rounded-2xl border border-dashed px-4 py-6 text-sm text-base-content/72"
            >
              Nenhuma transferência registrada neste ciclo.
            </div>

            <div
              :for={{id, record} <- @streams.settlement_records}
              id={id}
              class="shared-entry-row micro-surface flex items-center justify-between rounded-2xl p-4"
            >
              <div>
                <p class="break-words text-sm font-medium font-mono text-base-content/92">
                  {format_cents(record.amount_cents)}
                </p>
                <p class="text-xs text-base-content/62">
                  {format_method(record.method)} • {format_date(record.transferred_at)}
                </p>
              </div>
            </div>
          </div>
        </section>

        <section class="surface-card rounded-3xl p-5 sm:p-6">
          <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
            Registrar transferência
          </h2>
          <.form
            for={@record_form}
            id="new-record-form"
            phx-submit="create_record"
            class="mt-4 space-y-4"
          >
            <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <.input
                field={@record_form[:amount_cents]}
                type="number"
                label="Valor (centavos)"
                placeholder="Ex: 5000"
                min="1"
              />

              <.input
                field={@record_form[:method]}
                type="select"
                label="Método"
                prompt="Selecione"
                options={settlement_method_options()}
              />

              <.input
                field={@record_form[:transferred_at]}
                type="date"
                label="Data da transferência"
              />
            </div>

            <.button type="submit" variant="primary" class="w-full sm:w-auto">
              Registrar transferência
            </.button>
          </.form>
        </section>

        <section class="surface-card rounded-3xl p-5 sm:p-6">
          <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
            Confirmação e quitação
          </h2>

          <div class="mt-4 flex flex-col gap-3 sm:flex-row">
            <button
              id="confirm-settlement-btn"
              type="button"
              phx-click="confirm_settlement"
              class="btn btn-outline btn-primary"
            >
              Confirmar ciência do saldo
            </button>

            <button
              id="settle-btn"
              type="button"
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
        </section>
      </section>
    </Layouts.app>
    """
  end

  defp record_form(params \\ %{}) do
    to_form(params, as: :record)
  end

  defp parse_int(value) when is_integer(value), do: {:ok, value}

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_int(_), do: :error

  defp parse_amount_cents(nil), do: {:error, :invalid_amount}
  defp parse_amount_cents(""), do: {:error, :invalid_amount}

  defp parse_amount_cents(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> {:ok, int}
      _ -> {:error, :invalid_amount}
    end
  end

  defp parse_amount_cents(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp parse_amount_cents(_), do: {:error, :invalid_amount}

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

  defp parse_method(_), do: {:error, :invalid_method}

  defp parse_transferred_at(nil), do: {:ok, DateTime.utc_now() |> DateTime.truncate(:second)}
  defp parse_transferred_at(""), do: {:ok, DateTime.utc_now() |> DateTime.truncate(:second)}

  defp parse_transferred_at(value) when is_binary(value) do
    with {:ok, date} <- Date.from_iso8601(value),
         {:ok, datetime} <- DateTime.new(date, ~T[00:00:00], "Etc/UTC") do
      {:ok, datetime}
    else
      _ -> {:error, :invalid_date}
    end
  end

  defp parse_transferred_at(%DateTime{} = value), do: {:ok, value}
  defp parse_transferred_at(_), do: {:error, :invalid_date}

  defp format_cents(cents) when is_integer(cents) do
    abs_cents = abs(cents)
    integer_part = abs_cents |> div(100) |> Integer.to_string() |> add_thousands_separator()
    decimal_part = abs_cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    sign = if cents < 0, do: "-", else: ""

    "R$ #{sign}#{integer_part},#{decimal_part}"
  end

  defp format_cents(_), do: "R$ 0,00"

  defp format_date(%DateTime{} = dt) do
    "#{dt.day}/#{dt.month}/#{dt.year}"
  end

  defp format_date(_), do: "—"

  defp settlement_method_options do
    SettlementRecord.method_options()
  end

  defp format_method(method) when is_atom(method), do: SettlementRecord.method_label(method)
  defp format_method(_), do: "—"

  defp debtor_label(cycle, link) do
    if cycle.debtor_id == link.user_a_id, do: link.user_a.email, else: link.user_b.email
  end

  defp creditor_label(cycle, link) do
    if cycle.debtor_id == link.user_a_id, do: link.user_b.email, else: link.user_a.email
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
end
