defmodule OrganizerWeb.AccountLinkLive do
  use OrganizerWeb, :live_view

  import Ecto.Query

  alias Organizer.Planning
  alias Organizer.Repo
  alias Organizer.SharedFinance
  alias Organizer.SharedFinance.SharedEntryDebt
  alias OrganizerWeb.{FlashFeedback, FunnelTelemetry}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    page = 1
    page_size = 10
    filter_q = ""

    {:ok, {links, links_meta}} =
      SharedFinance.list_account_links_with_meta(scope, %{
        page: page,
        page_size: page_size,
        q: filter_q
      })

    sharing_metrics = load_sharing_metrics(scope, links_meta.total_count || length(links))

    socket =
      socket
      |> assign(:current_scope, scope)
      |> assign(:account_links, links)
      |> assign(:account_links_meta, links_meta)
      |> assign(:account_links_page, page)
      |> assign(:account_links_next_page, page + 1)
      |> assign(:account_links_page_size, page_size)
      |> assign(:account_links_has_more?, Map.get(links_meta, :has_next_page?, false))
      |> assign(:account_links_loading_more?, false)
      |> assign(:account_links_filter_q, filter_q)
      |> assign(:sharing_metrics, sharing_metrics)
      |> assign(:invite_url, nil)
      |> assign(:pending_link_deactivation, nil)
      |> assign(:invite_accept_form, invite_accept_form())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      case socket.assigns.live_action do
        :index ->
          socket
          |> assign(:page_title, "Compartilhamentos")
          |> maybe_restore_account_links_filter(params)

        :new_invite ->
          assign(socket, :page_title, "Novo Convite")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_invite", _params, socket) do
    scope = socket.assigns.current_scope

    track_funnel(:invite_create, :start)

    case SharedFinance.create_invite(scope) do
      {:ok, invite} ->
        track_funnel(:invite_create, :success)
        invite_url = OrganizerWeb.Endpoint.url() <> "/account-links/accept/#{invite.token}"

        socket =
          socket
          |> assign(:invite_url, invite_url)

        {:noreply, socket}

      {:error, _reason} ->
        track_funnel(:invite_create, :error, %{reason: "unexpected"})

        {:noreply,
         error_feedback(
           socket,
           "Não foi possível gerar o convite",
           "Tente novamente em alguns instantes"
         )}
    end
  end

  @impl true
  def handle_event("copy_invite_url", _params, socket) do
    case socket.assigns.invite_url do
      invite_url when is_binary(invite_url) and invite_url != "" ->
        {:noreply,
         socket
         |> push_event("copy-to-clipboard", %{text: invite_url})
         |> info_feedback("Link de convite copiado", "Envie o link para a outra conta")}

      _ ->
        {:noreply,
         error_feedback(
           socket,
           "Nenhum convite foi gerado",
           "Clique em gerar convite e tente copiar novamente"
         )}
    end
  end

  @impl true
  def handle_event("accept_invite", params, socket) do
    scope = socket.assigns.current_scope
    token = extract_invite_token(params)

    track_funnel(:invite_accept, :start)

    case SharedFinance.accept_invite(scope, token) do
      {:ok, link} ->
        track_funnel(:invite_accept, :success)

        {:noreply,
         socket
         |> info_feedback(
           "Compartilhamento estabelecido com sucesso",
           "Você será redirecionado para gerenciar o vínculo"
         )
         |> push_navigate(to: ~p"/account-links/#{link.id}")}

      {:error, :invite_invalid} ->
        track_funnel(:invite_accept, :error, %{reason: "invite_invalid"})

        {:noreply,
         socket
         |> assign(:invite_accept_form, invite_accept_form(%{"token" => token}))
         |> error_feedback("Convite inválido ou expirado", "Peça um novo convite para continuar")}

      {:error, :self_invite_not_allowed} ->
        track_funnel(:invite_accept, :error, %{reason: "self_invite_not_allowed"})

        {:noreply,
         socket
         |> assign(:invite_accept_form, invite_accept_form(%{"token" => token}))
         |> error_feedback(
           "Você não pode aceitar o próprio convite",
           "Use o convite em outra conta"
         )}

      {:error, :link_already_exists} ->
        track_funnel(:invite_accept, :error, %{reason: "link_already_exists"})

        {:noreply,
         socket
         |> assign(:invite_accept_form, invite_accept_form(%{"token" => token}))
         |> error_feedback(
           "Este compartilhamento já está ativo",
           "Acesse o vínculo na lista de compartilhamentos"
         )}
    end
  end

  @impl true
  def handle_event("prompt_deactivate_link", %{"id" => id}, socket) do
    track_funnel(:account_link_deactivate, :start)
    {:noreply, prepare_link_deactivation_confirmation(socket, id)}
  end

  @impl true
  def handle_event("cancel_deactivate_link", _params, socket) do
    track_funnel(:account_link_deactivate, :cancel)
    {:noreply, assign(socket, :pending_link_deactivation, nil)}
  end

  @impl true
  def handle_event("confirm_deactivate_link", _params, socket) do
    case socket.assigns.pending_link_deactivation do
      %{id: link_id} -> {:noreply, deactivate_link(socket, link_id)}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("deactivate_link", %{"id" => id}, socket) do
    track_funnel(:account_link_deactivate, :start)

    {:noreply,
     prepare_link_deactivation_confirmation(socket, id)
     |> info_feedback(
       "A desativação do compartilhamento precisa de confirmação",
       "Revise o vínculo e confirme para continuar"
     )}
  end

  @impl true
  def handle_event("filter_account_links", %{"filters" => filters}, socket) do
    filter_q =
      filters
      |> Map.get("q", "")
      |> normalize_filter_q()

    {:noreply,
     socket
     |> assign(:account_links_filter_q, filter_q)
     |> assign(:account_links_loading_more?, false)
     |> load_account_links_page(1, reset: true)}
  end

  @impl true
  def handle_event("load_more_account_links", params, socket) do
    cond do
      socket.assigns.account_links_loading_more? ->
        {:noreply, socket}

      not socket.assigns.account_links_has_more? ->
        {:noreply, socket}

      true ->
        next_page =
          params
          |> Map.get("page", socket.assigns.account_links_next_page)
          |> parse_positive_page()

        {:noreply,
         socket
         |> assign(:account_links_loading_more?, true)
         |> load_account_links_page(next_page, reset: false)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide={true}>
      <%= case @live_action do %>
        <% :index -> %>
          <section class="collab-shell responsive-shell mx-auto max-w-5xl space-y-6">
            <header class={collab_header_class("p-6 sm:p-8")}>
              <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
                <div class="space-y-2">
                  <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/62">
                    Fluxo colaborativo
                  </p>
                  <h1 class="text-2xl font-black tracking-[-0.02em] text-base-content sm:text-3xl">
                    Compartilhamentos entre contas
                  </h1>
                  <p class="max-w-2xl text-sm leading-6 text-base-content/78">
                    Conecte outra pessoa por convite, compartilhe lançamentos e acompanhe acertos no mesmo fluxo.
                  </p>
                </div>
                <.link
                  navigate={~p"/account-links/invite"}
                  id="new-invite-btn"
                  class="inline-flex items-center gap-2 rounded-xl border border-cyan-300/70 bg-cyan-400/90 px-4 py-2 text-sm font-semibold text-slate-950 shadow-[0_16px_36px_-20px_rgba(34,211,238,0.8)] transition hover:bg-cyan-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-200/60"
                >
                  <.icon name="hero-paper-airplane" class="size-4" /> Novo convite
                </.link>
              </div>
            </header>

            <section class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
              <article class={neon_card_class("p-4")}>
                <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">
                  Lançamentos compartilhados
                </p>
                <p class="mt-1 text-2xl font-semibold text-base-content">
                  {@sharing_metrics.finances_shared_total}
                </p>
              </article>

              <article class={neon_card_class("p-4")}>
                <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">
                  Compartilhamentos ativos
                </p>
                <p class="mt-1 text-2xl font-semibold text-base-content">
                  {@sharing_metrics.links_active}
                </p>
              </article>

              <article class={neon_card_class("p-4")}>
                <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">
                  Dívidas em aberto
                </p>
                <p class="mt-1 text-2xl font-semibold text-base-content">
                  {@sharing_metrics.open_debts_total}
                </p>
              </article>

              <article class={neon_card_class("p-4")}>
                <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">
                  Saldo pendente
                </p>
                <p class="mt-1 text-2xl font-semibold font-mono text-warning">
                  {format_cents(@sharing_metrics.outstanding_total_cents)}
                </p>
              </article>
            </section>

            <section class={neon_surface_class("p-5 sm:p-6")}>
              <div class="flex items-center justify-between">
                <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
                  Lista de compartilhamentos
                </h2>
                <span class="text-xs text-base-content/65">
                  {Map.get(@account_links_meta, :total_count, length(@account_links))} registro(s)
                </span>
              </div>

              <form id="account-links-filters" phx-change="filter_account_links" class="mt-4">
                <.input
                  type="text"
                  name="filters[q]"
                  value={@account_links_filter_q}
                  placeholder="Filtrar por e-mail do participante..."
                  maxlength="120"
                />
              </form>

              <div
                id="account-links-scroll-area"
                phx-hook="InfiniteScroll"
                data-event="load_more_account_links"
                data-has-more={to_string(@account_links_has_more?)}
                data-loading={to_string(@account_links_loading_more?)}
                data-next-page={@account_links_next_page}
                class="operations-scroll-area operations-scroll-area--list mt-4 rounded-2xl border border-cyan-300/20 bg-slate-900/65 p-3 shadow-[inset_0_0_0_1px_rgba(34,211,238,0.04)]"
              >
                <ul id="account-links-list" class="space-y-3">
                  <%= if Enum.empty?(@account_links) do %>
                    <li
                      id="account-link-empty"
                      class="rounded-2xl border border-dashed border-cyan-300/30 bg-slate-900/55 px-4 py-6 text-sm text-slate-300"
                    >
                      Nenhum compartilhamento ativo. Gere um convite para começar a compartilhar.
                    </li>
                  <% end %>

                  <%= for link <- @account_links do %>
                    <li
                      id={"account-link-#{link.id}"}
                      class={shared_entry_row_class("gap-3")}
                    >
                      <div class="min-w-0">
                        <p class="truncate text-sm font-semibold text-base-content/92">
                          {partner_email(@current_scope.user.id, link)}
                        </p>
                        <p class="text-xs text-base-content/62">
                          Compartilhamento #{link.id} • ativo
                        </p>
                      </div>

                      <div class="flex flex-wrap gap-2">
                        <.link
                          navigate={~p"/account-links/#{link.id}"}
                          class="inline-flex items-center rounded-lg border border-cyan-300/35 bg-slate-900/85 px-2.5 py-1 text-xs font-medium text-cyan-100 transition hover:border-cyan-200/70 hover:bg-cyan-400/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/35"
                        >
                          Gerenciar
                        </.link>
                        <button
                          id={"deactivate-link-#{link.id}"}
                          type="button"
                          phx-click="prompt_deactivate_link"
                          phx-value-id={link.id}
                          class="inline-flex items-center rounded-lg border border-rose-300/45 bg-rose-500/10 px-2.5 py-1 text-xs font-medium text-rose-100 transition hover:border-rose-200/70 hover:bg-rose-500/20 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-300/35"
                        >
                          Desativar
                        </button>
                      </div>
                    </li>
                  <% end %>
                </ul>

                <div :if={@account_links_loading_more?} class="px-1 py-2">
                  <p class="text-center text-xs text-base-content/62">
                    Carregando mais compartilhamentos...
                  </p>
                </div>
              </div>
            </section>

            <.destructive_confirm_modal
              id="account-link-deactivate-confirmation-modal"
              show={is_map(@pending_link_deactivation)}
              title="Desativar compartilhamento entre contas?"
              message="Você vai encerrar o vínculo ativo e bloquear novos compartilhamentos neste link."
              severity="critical"
              impact_label="Impacto: colaboração interrompida para as duas contas"
              confirm_event="confirm_deactivate_link"
              cancel_event="cancel_deactivate_link"
              confirm_button_id="confirm-deactivate-link-btn"
              cancel_button_id="cancel-deactivate-link-btn"
              confirm_label="Sim, desativar compartilhamento"
            >
              <p :if={is_map(@pending_link_deactivation)} class="font-medium text-base-content">
                Parceiro: {Map.get(@pending_link_deactivation, :partner_email, "conta vinculada")}
              </p>
            </.destructive_confirm_modal>
          </section>
        <% :new_invite -> %>
          <section class="collab-shell responsive-shell mx-auto max-w-5xl space-y-6">
            <header class={collab_header_class("p-6 sm:p-8")}>
              <p class="text-xs font-semibold uppercase tracking-[0.16em] text-base-content/62">
                Convite por link
              </p>
              <h1 class="mt-2 text-2xl font-black tracking-[-0.02em] text-base-content sm:text-3xl">
                Gerar e aceitar convite
              </h1>
              <p class="mt-3 max-w-2xl text-sm leading-6 text-base-content/78">
                Compartilhe o link para criar o compartilhamento. Se recebeu um token, cole abaixo para aceitar.
              </p>
            </header>

            <div class="grid gap-5 lg:grid-cols-[1.05fr_0.95fr]">
              <section class={neon_surface_class("p-6")}>
                <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/68">
                  Gerar convite
                </h2>
                <p class="mt-2 text-sm text-base-content/78">
                  Crie um link único e envie para a pessoa que deseja conectar.
                </p>
                <button
                  id="create-invite-btn"
                  type="button"
                  phx-click="create_invite"
                  class="mt-4 inline-flex w-full items-center justify-center gap-2 rounded-xl border border-cyan-300/70 bg-cyan-400/90 px-4 py-2 text-sm font-semibold text-slate-950 shadow-[0_16px_36px_-20px_rgba(34,211,238,0.8)] transition hover:bg-cyan-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-200/60 sm:w-auto"
                >
                  <.icon name="hero-paper-airplane" class="size-4" /> Gerar link de convite
                </button>

                <div :if={@invite_url} class="mt-4 space-y-2">
                  <p class="text-xs font-semibold uppercase tracking-[0.12em] text-base-content/62">
                    Link gerado
                  </p>
                  <div
                    id="invite-url"
                    class={
                      neon_card_class(
                        "rounded-xl border-cyan-300/25 p-3 break-all text-sm font-mono text-base-content/90"
                      )
                    }
                  >
                    {@invite_url}
                  </div>
                  <div class="flex flex-wrap items-center gap-2">
                    <button
                      id="copy-invite-url-btn"
                      type="button"
                      phx-click="copy_invite_url"
                      class="inline-flex items-center rounded-lg border border-cyan-300/35 bg-slate-900/85 px-2.5 py-1 text-xs font-medium text-cyan-100 transition hover:border-cyan-200/70 hover:bg-cyan-400/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/35 sm:px-3 sm:py-1.5"
                    >
                      <.icon name="hero-clipboard-document" class="size-4" /> Copiar link
                    </button>
                    <p class="text-xs text-base-content/68">
                      Envie este link para a outra pessoa aceitar o convite em 1 clique.
                    </p>
                  </div>
                </div>
              </section>

              <section class={neon_surface_class("p-6")}>
                <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/68">
                  Aceitar convite
                </h2>
                <p class="mt-2 text-sm text-base-content/78">
                  Cole o token recebido para conectar as contas imediatamente.
                </p>

                <.form
                  for={@invite_accept_form}
                  id="accept-invite-form"
                  phx-submit="accept_invite"
                  class="mt-4 space-y-3"
                >
                  <.input
                    field={@invite_accept_form[:token]}
                    label="Token do convite"
                    placeholder="Cole o token aqui"
                    required
                  />
                  <.button type="submit" variant="primary" class="w-full">
                    Aceitar convite
                  </.button>
                </.form>
              </section>
            </div>
          </section>
      <% end %>
    </Layouts.app>
    """
  end

  defp invite_accept_form(params \\ %{}) do
    to_form(Map.merge(%{"token" => ""}, params), as: :invite)
  end

  defp extract_invite_token(%{"invite" => %{"token" => token}}), do: parse_invite_token(token)
  defp extract_invite_token(%{"token" => token}), do: parse_invite_token(token)
  defp extract_invite_token(_), do: ""

  defp parse_invite_token(token) when is_binary(token) do
    cleaned = String.trim(token)

    cond do
      cleaned == "" ->
        ""

      String.contains?(cleaned, "/account-links/accept/") ->
        cleaned
        |> URI.parse()
        |> Map.get(:path, "")
        |> String.split("/account-links/accept/")
        |> List.last()
        |> to_string()
        |> String.split("/")
        |> List.first()
        |> to_string()
        |> String.trim()

      true ->
        cleaned
    end
  end

  defp parse_invite_token(_token), do: ""

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

  defp prepare_link_deactivation_confirmation(socket, id) do
    scope = socket.assigns.current_scope

    with {:ok, link_id} <- parse_int(id),
         {:ok, link} <- SharedFinance.get_account_link(scope, link_id) do
      assign(socket, :pending_link_deactivation, %{
        id: link.id,
        partner_email: partner_email(scope.user.id, link)
      })
    else
      {:error, :not_found} ->
        error_feedback(
          socket,
          "Compartilhamento não encontrado",
          "Atualize a lista e tente novamente"
        )

      _ ->
        error_feedback(socket, "Não foi possível preparar a desativação", "Tente novamente")
    end
  end

  defp deactivate_link(socket, link_id) do
    scope = socket.assigns.current_scope

    with {:ok, _link} <- SharedFinance.deactivate_account_link(scope, link_id) do
      track_funnel(:account_link_deactivate, :success)

      socket
      |> assign(:pending_link_deactivation, nil)
      |> load_account_links_page(1, reset: true)
      |> info_feedback(
        "Compartilhamento desativado",
        "Se precisar, gere um novo convite para reconectar"
      )
    else
      _ ->
        track_funnel(:account_link_deactivate, :error, %{reason: "unexpected"})

        socket
        |> assign(:pending_link_deactivation, nil)
        |> error_feedback(
          "Não foi possível desativar o compartilhamento",
          "Tente novamente em alguns instantes"
        )
    end
  end

  defp load_sharing_metrics(scope, links_active_count) do
    {:ok, finances} =
      Planning.list_finance_entries(scope, %{
        days: "365",
        kind: "all",
        expense_profile: "all",
        payment_method: "all"
      })

    finances_shared_total = Enum.count(finances, &is_integer(&1.shared_with_link_id))

    {open_debts_total, outstanding_total_cents} =
      scope
      |> active_link_ids_for_scope()
      |> outstanding_debt_totals_for_links()

    %{
      links_active: links_active_count,
      finances_shared_total: finances_shared_total,
      open_debts_total: open_debts_total,
      outstanding_total_cents: outstanding_total_cents
    }
  end

  defp load_account_links_page(socket, page, opts) do
    reset? = Keyword.get(opts, :reset, true)
    scope = socket.assigns.current_scope
    page_size = socket.assigns.account_links_page_size
    filter_q = Map.get(socket.assigns, :account_links_filter_q, "")

    case SharedFinance.list_account_links_with_meta(scope, %{
           page: page,
           page_size: page_size,
           q: filter_q
         }) do
      {:ok, {links, links_meta}} ->
        current_links = Map.get(socket.assigns, :account_links, [])

        merged_links =
          if reset? do
            links
          else
            current_links ++ links
          end

        current_page = Map.get(links_meta, :current_page, page)

        sharing_metrics =
          load_sharing_metrics(scope, links_meta.total_count || length(merged_links))

        socket
        |> assign(:account_links, merged_links)
        |> assign(:account_links_meta, links_meta)
        |> assign(:account_links_page, current_page)
        |> assign(:account_links_next_page, current_page + 1)
        |> assign(:account_links_has_more?, Map.get(links_meta, :has_next_page?, false))
        |> assign(:account_links_loading_more?, false)
        |> assign(:sharing_metrics, sharing_metrics)

      _ ->
        socket
        |> assign(:account_links_loading_more?, false)
        |> error_feedback(
          "Não foi possível carregar os compartilhamentos",
          "Atualize a página e tente novamente"
        )
    end
  end

  defp maybe_restore_account_links_filter(socket, params) do
    filter_q =
      params
      |> Map.get("q", Map.get(socket.assigns, :account_links_filter_q, ""))
      |> normalize_filter_q()

    if filter_q == Map.get(socket.assigns, :account_links_filter_q, "") do
      socket
    else
      socket
      |> assign(:account_links_filter_q, filter_q)
      |> load_account_links_page(1, reset: true)
    end
  end

  defp normalize_filter_q(value) when is_binary(value), do: String.trim(value)
  defp normalize_filter_q(_), do: ""

  defp partner_email(user_id, link) do
    if user_id == link.user_a_id do
      link.user_b.email
    else
      link.user_a.email
    end
  end

  defp active_link_ids_for_scope(scope) do
    case SharedFinance.list_account_links(scope) do
      {:ok, links} -> Enum.map(links, & &1.id)
      _ -> []
    end
  end

  defp outstanding_debt_totals_for_links([]), do: {0, 0}

  defp outstanding_debt_totals_for_links(link_ids) when is_list(link_ids) do
    totals =
      from(d in SharedEntryDebt,
        where: d.account_link_id in ^link_ids and d.status in [:open, :partial],
        select: %{
          debt_count: count(d.id),
          amount_total: coalesce(sum(d.outstanding_amount_cents), 0)
        }
      )
      |> Repo.one()

    {
      if(is_nil(totals), do: 0, else: totals.debt_count || 0),
      if(is_nil(totals), do: 0, else: totals.amount_total || 0)
    }
  end

  defp format_cents(cents) when is_integer(cents) do
    abs_cents = abs(cents)
    integer_part = abs_cents |> div(100) |> Integer.to_string() |> add_thousands_separator()
    decimal_part = abs_cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    sign = if cents < 0, do: "-", else: ""

    "R$ #{sign}#{integer_part},#{decimal_part}"
  end

  defp format_cents(_cents), do: "R$ 0,00"

  defp add_thousands_separator(value) when is_binary(value) do
    value
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(".")
    |> String.reverse()
  end

  defp info_feedback(socket, happened, next_step) do
    put_flash(socket, :info, FlashFeedback.compose(happened, next_step))
  end

  defp error_feedback(socket, happened, next_step) do
    put_flash(socket, :error, FlashFeedback.compose(happened, next_step))
  end

  defp track_funnel(action, outcome, metadata \\ %{}) do
    FunnelTelemetry.track_step(:account_links, action, outcome, metadata)
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

  defp shared_entry_row_class(extra) do
    join_classes([
      "shared-entry-row flex flex-col rounded-2xl p-4 sm:flex-row sm:items-center sm:justify-between",
      neon_card_class(nil),
      extra
    ])
  end

  defp join_classes(classes) do
    classes
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end
end
