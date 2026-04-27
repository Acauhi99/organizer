defmodule OrganizerWeb.SharedFinanceLive do
  use OrganizerWeb, :live_view

  alias Contex.{Dataset, Plot}
  alias Organizer.DateSupport
  alias Organizer.Planning.AmountParser
  alias Organizer.SharedFinance
  alias Organizer.SharedFinance.SplitCalculator

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
        |> assign(:shared_balance_chart, shared_balance_chart_svg(metrics))
        |> assign(:shared_trend_chart, shared_trend_chart_svg(trend))
        |> assign(:shared_entries_count, length(views))
        |> assign(:shared_entry_edit_entry, nil)
        |> assign(:shared_entry_edit_form, to_form(%{}, as: :shared_entry_edit))
        |> assign(:shared_entry_edit_preview, nil)
        |> assign(:page_title, "Finanças Compartilhadas")
        |> stream_configure(:shared_entries, dom_id: &"shared-entry-view-#{&1.entry.id}")
        |> stream(:shared_entries, views)

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Compartilhamento não encontrado.")
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
  def handle_event("open_shared_entry_edit", %{"entry_id" => entry_id}, socket) do
    scope = socket.assigns.current_scope
    link_id = socket.assigns.link_id
    selected_period = socket.assigns.selected_shared_period

    with {:ok, parsed_entry_id} <- parse_int(entry_id),
         {:ok, view} <-
           shared_entry_view_for_edit(scope, link_id, selected_period, parsed_entry_id),
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
         put_flash(socket, :error, "Você só pode editar lançamentos compartilhados da sua conta.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível abrir a edição do lançamento.")}
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
             |> put_flash(:info, "Lançamento compartilhado atualizado.")
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
             |> put_flash(:error, shared_entry_edit_validation_message(details))}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> close_shared_entry_edit_modal()
             |> reload_shared_data()
             |> put_flash(:error, "Lançamento compartilhado não encontrado para edição.")}

          _ ->
            {:noreply, put_flash(socket, :error, "Não foi possível atualizar o lançamento.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Nenhum lançamento foi selecionado para edição.")}
    end
  end

  @impl true
  def handle_event("cancel_shared_entry_edit", _params, socket) do
    {:noreply, close_shared_entry_edit_modal(socket)}
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
      <section class="collab-shell responsive-shell mx-auto max-w-6xl space-y-6">
        <header class="surface-card collab-hero rounded-3xl p-6 sm:p-8">
          <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div class="space-y-2">
              <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/62">
                Finanças compartilhadas
              </p>
              <h1 class="text-2xl font-black tracking-[-0.02em] text-base-content sm:text-3xl">
                Visão conjunta do compartilhamento
              </h1>
              <p class="max-w-2xl text-sm leading-6 text-base-content/78">
                Monitore total compartilhado, proporção entre contas e tendência recorrente sem sair do fluxo colaborativo.
              </p>
            </div>
            <.link navigate={~p"/account-links"} class="btn btn-outline btn-sm sm:btn-md">
              <.icon name="hero-arrow-left" class="size-4" /> Voltar para compartilhamentos
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
              <p class="mt-1 break-words text-xl font-mono font-semibold text-base-content">
                {format_cents(@metrics.total_cents)}
              </p>
            </article>

            <article class="collab-stat micro-surface rounded-2xl p-4 text-center">
              <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">Você arcou</p>
              <p class="mt-1 break-words text-xl font-mono font-semibold text-info">
                {format_cents(@metrics.paid_a_cents)}
              </p>
            </article>

            <article class="collab-stat micro-surface rounded-2xl p-4 text-center">
              <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">
                Outra conta arcou
              </p>
              <p class="mt-1 break-words text-xl font-mono font-semibold text-success">
                {format_cents(@metrics.paid_b_cents)}
              </p>
            </article>
          </div>

          <div class="mt-4 grid gap-3 xl:grid-cols-2">
            <article
              id="shared-balance-chart"
              class="micro-surface min-h-[15rem] overflow-x-auto rounded-2xl p-4"
            >
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

            <article
              id="shared-trend-chart"
              class="micro-surface min-h-[15rem] overflow-x-auto rounded-2xl p-4"
            >
              <div class="flex items-center justify-between gap-2">
                <h3 class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/70">
                  Tendência compartilhada
                </h3>
                <span class="text-[0.68rem] text-base-content/60">6 meses</span>
              </div>
              <div :if={@trend != []} class="contex-plot mt-2">
                {@shared_trend_chart}
              </div>
              <p :if={@trend == []} class="mt-8 text-sm text-base-content/62">
                Sem recorrentes variáveis compartilhados para gerar tendência.
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
              Ainda não há lançamentos compartilhados neste compartilhamento.
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
                  class="btn btn-outline btn-xs shrink-0"
                >
                  Editar
                </button>
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
    <div
      :if={is_map(@entry)}
      id="shared-entry-edit-modal"
      class="fixed inset-0 z-[120] flex items-end justify-center px-3 py-4 sm:items-center sm:p-6"
      phx-window-keydown="cancel_shared_entry_edit"
      phx-key="escape"
      aria-hidden="false"
    >
      <div
        id="shared-entry-edit-modal-backdrop"
        aria-hidden="true"
        phx-click="cancel_shared_entry_edit"
        class="absolute inset-0 bg-slate-950/66 backdrop-blur-[3px]"
      >
      </div>

      <section
        id="shared-entry-edit-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"shared-entry-edit-title-#{@entry.id}"}
        class="relative z-10 w-full max-w-4xl max-h-[88vh] overflow-y-auto rounded-3xl border border-base-content/16 bg-base-100 p-5 shadow-[0_40px_120px_rgba(8,19,35,0.55)] sm:p-6"
      >
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
            class="btn btn-ghost btn-sm border border-base-content/25 bg-base-100 shadow-sm"
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
          <div class="grid gap-3 rounded-2xl border border-base-content/12 bg-base-100 p-3 sm:grid-cols-2 sm:p-4">
            <.input
              field={@form[:description]}
              type="text"
              label="Descrição"
              class="w-full rounded-xl border border-base-content/24 bg-base-100 px-3 py-2 text-sm text-base-content shadow-sm transition focus:border-info/72 focus:ring-2 focus:ring-info/22"
              placeholder="Ex: Aluguel, mercado, conta de luz..."
            />
            <.input
              field={@form[:category]}
              type="text"
              label="Categoria"
              required
              class="w-full rounded-xl border border-base-content/24 bg-base-100 px-3 py-2 text-sm text-base-content shadow-sm transition focus:border-info/72 focus:ring-2 focus:ring-info/22"
            />
            <.input
              field={@form[:amount_cents]}
              type="text"
              label="Valor total"
              inputmode="decimal"
              required
              class="w-full rounded-xl border border-base-content/24 bg-base-100 px-3 py-2 text-sm text-base-content shadow-sm transition focus:border-info/72 focus:ring-2 focus:ring-info/22"
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
              class="w-full rounded-xl border border-base-content/24 bg-base-100 px-3 py-2 text-sm text-base-content shadow-sm transition focus:border-info/72 focus:ring-2 focus:ring-info/22"
            />
          </div>

          <section class="rounded-2xl border border-base-content/14 bg-base-100 p-4 shadow-sm">
            <h3 class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/64">
              Tipo de divisão
            </h3>
            <.input
              field={@form[:split_type]}
              type="select"
              options={@split_type_options}
              label="Como dividir entre as contas?"
              class="w-full rounded-xl border border-base-content/24 bg-base-100 px-3 py-2 text-sm text-base-content shadow-sm transition focus:border-info/72 focus:ring-2 focus:ring-info/22"
            />

            <div :if={@split_type == "percentage"} class="grid gap-3 sm:grid-cols-2">
              <.input
                field={@form[:split_mine_percentage]}
                type="text"
                label="Sua porcentagem (%)"
                inputmode="decimal"
                placeholder="Ex: 56,7"
                class="w-full rounded-xl border border-base-content/24 bg-base-100 px-3 py-2 text-sm text-base-content shadow-sm transition focus:border-info/72 focus:ring-2 focus:ring-info/22"
              />
              <.input
                field={@form[:split_mine_amount]}
                type="text"
                label="Seu valor (R$)"
                inputmode="decimal"
                placeholder="Calculado automaticamente"
                readonly
                class="w-full rounded-xl border border-base-content/18 bg-base-200/70 px-3 py-2 text-sm text-base-content/86"
              />
            </div>

            <div :if={@split_type == "fixed_amount"} class="grid gap-3 sm:grid-cols-2">
              <.input
                field={@form[:split_mine_amount]}
                type="text"
                label="Seu valor fixo (R$)"
                inputmode="decimal"
                placeholder="Ex: 120,00"
                class="w-full rounded-xl border border-base-content/24 bg-base-100 px-3 py-2 text-sm text-base-content shadow-sm transition focus:border-info/72 focus:ring-2 focus:ring-info/22"
              />
              <.input
                field={@form[:split_mine_percentage]}
                type="text"
                label="Sua porcentagem (%)"
                inputmode="decimal"
                placeholder="Calculada automaticamente"
                readonly
                class="w-full rounded-xl border border-base-content/18 bg-base-200/70 px-3 py-2 text-sm text-base-content/86"
              />
            </div>

            <div
              :if={@split_type == "income_ratio"}
              class="rounded-xl border border-info/35 bg-info/14 px-3 py-2 text-xs font-medium text-info-content"
            >
              A divisão automática usa a proporção de renda de referência do mês da transação.
            </div>
          </section>

          <section
            id="shared-entry-edit-preview"
            class="rounded-2xl border border-base-content/14 bg-base-100 p-4 shadow-sm"
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

          <div class="flex flex-col-reverse gap-2 border-t border-base-content/12 pt-3 sm:flex-row sm:justify-end">
            <button
              type="button"
              phx-click="cancel_shared_entry_edit"
              class="btn btn-ghost btn-sm border border-base-content/20"
            >
              Cancelar
            </button>
            <button type="submit" class="btn btn-primary btn-sm shadow-md shadow-primary/30">
              Salvar alterações
            </button>
          </div>
        </.form>
      </section>
    </div>
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
    |> assign(:shared_balance_chart, shared_balance_chart_svg(metrics))
    |> assign(:shared_trend_chart, shared_trend_chart_svg(trend))
    |> assign(:shared_entries_count, length(views))
    |> stream(:shared_entries, views, reset: true)
  end

  defp close_shared_entry_edit_modal(socket) do
    socket
    |> assign(:shared_entry_edit_entry, nil)
    |> assign(:shared_entry_edit_form, to_form(%{}, as: :shared_entry_edit))
    |> assign(:shared_entry_edit_preview, nil)
  end

  defp shared_entry_view_for_edit(scope, link_id, period, entry_id) do
    with {:ok, views} <- SharedFinance.list_shared_entries(scope, link_id, %{period: period}),
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

  defp shared_trend_chart_svg([]), do: nil

  defp shared_trend_chart_svg(trend) do
    data =
      Enum.map(trend, fn mt ->
        {"#{String.pad_leading(to_string(mt.month), 2, "0")}/#{mt.year}", mt.total_cents}
      end)

    dataset = Dataset.new(data, ["mês", "total"])

    Plot.new(dataset, Contex.BarChart, 560, 260,
      mapping: %{category_col: "mês", value_cols: ["total"]},
      data_labels: false,
      custom_value_formatter: &money_axis_formatter/1,
      title: "Recorrentes variáveis compartilhados"
    )
    |> Plot.to_svg()
  end

  defp money_axis_formatter(value) when is_number(value) do
    value
    |> round()
    |> format_cents()
  end

  defp money_axis_formatter(_), do: "R$ 0,00"

  @spec normalize_shared_period_filter(map()) :: String.t()
  defp normalize_shared_period_filter(params) do
    case Map.get(params, "period") do
      "current_month" -> "current_month"
      "last_3_months" -> "last_3_months"
      _ -> "all"
    end
  end

  defp shared_split_type_options do
    [
      {"Automática por renda", "income_ratio"},
      {"Percentual fixo", "percentage"},
      {"Valor fixo para você", "fixed_amount"}
    ]
  end
end
