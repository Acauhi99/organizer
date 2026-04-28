defmodule OrganizerWeb.AccountLinkLive do
  use OrganizerWeb, :live_view

  alias Organizer.Planning
  alias Organizer.SharedFinance

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Organizer.PubSub, "account_links:#{scope.user.id}")
    end

    {:ok, links} = SharedFinance.list_account_links(scope)
    sharing_metrics = load_sharing_metrics(scope, links)

    socket =
      socket
      |> assign(:current_scope, scope)
      |> assign(:account_links, links)
      |> assign(:sharing_metrics, sharing_metrics)
      |> assign(:invite_url, nil)
      |> assign(:invite_token, nil)
      |> assign(:pending_link_deactivation, nil)
      |> assign(:invite_accept_form, invite_accept_form())

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    socket =
      case socket.assigns.live_action do
        :index -> assign(socket, :page_title, "Compartilhamentos")
        :new_invite -> assign(socket, :page_title, "Novo Convite")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_invite", _params, socket) do
    scope = socket.assigns.current_scope

    case SharedFinance.create_invite(scope) do
      {:ok, invite} ->
        invite_url = OrganizerWeb.Endpoint.url() <> "/account-links/accept/#{invite.token}"

        socket =
          socket
          |> assign(:invite_url, invite_url)
          |> assign(:invite_token, invite.token)

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível gerar o convite.")}
    end
  end

  @impl true
  def handle_event("copy_invite_url", _params, socket) do
    case socket.assigns.invite_url do
      invite_url when is_binary(invite_url) and invite_url != "" ->
        {:noreply,
         socket
         |> push_event("copy-to-clipboard", %{text: invite_url})
         |> put_flash(:info, "Link copiado. Agora é só enviar para a outra conta.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Gere um convite antes de copiar o link.")}
    end
  end

  @impl true
  def handle_event("accept_invite", params, socket) do
    scope = socket.assigns.current_scope
    token = extract_invite_token(params)

    case SharedFinance.accept_invite(scope, token) do
      {:ok, link} ->
        {:noreply,
         socket
         |> put_flash(:info, "Compartilhamento estabelecido com sucesso.")
         |> push_navigate(to: ~p"/account-links/#{link.id}")}

      {:error, :invite_invalid} ->
        {:noreply,
         socket
         |> assign(:invite_accept_form, invite_accept_form(%{"token" => token}))
         |> put_flash(:error, "Convite inválido ou expirado.")}

      {:error, :self_invite_not_allowed} ->
        {:noreply,
         socket
         |> assign(:invite_accept_form, invite_accept_form(%{"token" => token}))
         |> put_flash(:error, "Você não pode aceitar o próprio convite.")}

      {:error, :link_already_exists} ->
        {:noreply,
         socket
         |> assign(:invite_accept_form, invite_accept_form(%{"token" => token}))
         |> put_flash(:error, "Já existe um compartilhamento ativo com este usuário.")}
    end
  end

  @impl true
  def handle_event("prompt_deactivate_link", %{"id" => id} = params, socket) do
    with {:ok, link_id} <- parse_int(id) do
      pending_link_deactivation = %{
        id: link_id,
        partner_email: Map.get(params, "partner_email", "")
      }

      {:noreply, assign(socket, :pending_link_deactivation, pending_link_deactivation)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Não foi possível preparar a desativação.")}
    end
  end

  @impl true
  def handle_event("cancel_deactivate_link", _params, socket) do
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
    case parse_int(id) do
      {:ok, link_id} ->
        {:noreply, deactivate_link(socket, link_id)}

      :error ->
        {:noreply, put_flash(socket, :error, "Não foi possível desativar o compartilhamento.")}
    end
  end

  @impl true
  def handle_info({:account_link_updated, _}, socket) do
    scope = socket.assigns.current_scope
    {:ok, links} = SharedFinance.list_account_links(scope)
    sharing_metrics = load_sharing_metrics(scope, links)

    {:noreply,
     socket |> assign(:account_links, links) |> assign(:sharing_metrics, sharing_metrics)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide={true}>
      <%= case @live_action do %>
        <% :index -> %>
          <section class="collab-shell responsive-shell mx-auto max-w-5xl space-y-6">
            <header class="surface-card collab-hero rounded-3xl p-6 sm:p-8">
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
                  class="btn btn-primary btn-sm sm:btn-md"
                >
                  <.icon name="hero-paper-airplane" class="size-4" /> Novo convite
                </.link>
              </div>
            </header>

            <section class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
              <article class="micro-surface rounded-2xl p-4">
                <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">
                  Compartilhamentos ativos
                </p>
                <p class="mt-1 text-2xl font-semibold text-base-content">
                  {@sharing_metrics.links_active}
                </p>
              </article>

              <article class="micro-surface rounded-2xl p-4">
                <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">
                  Lançamentos vinculados
                </p>
                <p class="mt-1 text-2xl font-semibold text-base-content">
                  {@sharing_metrics.finances_shared_total}
                </p>
              </article>

              <article class="micro-surface rounded-2xl p-4">
                <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">
                  Compartilhamentos ativos
                </p>
                <p class="mt-1 text-2xl font-semibold text-base-content">
                  {@sharing_metrics.links_active}
                </p>
              </article>

              <article class="micro-surface rounded-2xl p-4">
                <p class="text-xs uppercase tracking-[0.12em] text-base-content/62">
                  Itens sincronizados
                </p>
                <p class="mt-1 text-2xl font-semibold text-base-content">
                  {@sharing_metrics.shared_total}
                </p>
              </article>
            </section>

            <section class="surface-card rounded-3xl p-5 sm:p-6">
              <div class="flex items-center justify-between">
                <h2 class="text-sm font-semibold uppercase tracking-[0.14em] text-base-content/70">
                  Lista de compartilhamentos
                </h2>
                <span class="text-xs text-base-content/65">{length(@account_links)} registro(s)</span>
              </div>

              <ul id="account-links-list" class="mt-4 space-y-3">
                <%= if Enum.empty?(@account_links) do %>
                  <li
                    id="account-link-empty"
                    class="ds-empty-state rounded-2xl border border-dashed px-4 py-6 text-sm text-base-content/75"
                  >
                    Nenhum compartilhamento ativo. Gere um convite para começar a compartilhar.
                  </li>
                <% end %>

                <%= for link <- @account_links do %>
                  <li
                    id={"account-link-#{link.id}"}
                    class="shared-entry-row micro-surface flex flex-col gap-3 rounded-2xl p-4 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <div class="min-w-0">
                      <p class="truncate text-sm font-semibold text-base-content/92">
                        {partner_email(@current_scope.user.id, link)}
                      </p>
                      <p class="text-xs text-base-content/62">Compartilhamento #{link.id} • ativo</p>
                    </div>

                    <div class="flex flex-wrap gap-2">
                      <.link navigate={~p"/account-links/#{link.id}"} class="btn btn-soft btn-xs">
                        Finanças
                      </.link>
                      <.link
                        navigate={~p"/account-links/#{link.id}/settlement"}
                        class="btn btn-outline btn-xs"
                      >
                        Acerto
                      </.link>
                      <button
                        id={"deactivate-link-#{link.id}"}
                        type="button"
                        phx-click="prompt_deactivate_link"
                        phx-value-id={link.id}
                        phx-value-partner_email={partner_email(@current_scope.user.id, link)}
                        class="btn btn-outline btn-xs btn-error"
                      >
                        Desativar
                      </button>
                    </div>
                  </li>
                <% end %>
              </ul>
            </section>

            <.destructive_confirm_modal
              id="account-link-deactivate-confirmation-modal"
              show={is_map(@pending_link_deactivation)}
              title="Desativar compartilhamento?"
              message="Essa ação encerra o vínculo entre as contas e interrompe novos compartilhamentos por este link."
              confirm_event="confirm_deactivate_link"
              cancel_event="cancel_deactivate_link"
              confirm_button_id="confirm-deactivate-link-btn"
              cancel_button_id="cancel-deactivate-link-btn"
              confirm_label="Desativar compartilhamento"
            >
              <p :if={is_map(@pending_link_deactivation)} class="font-medium text-base-content">
                Parceiro: {Map.get(@pending_link_deactivation, :partner_email, "conta vinculada")}
              </p>
            </.destructive_confirm_modal>
          </section>
        <% :new_invite -> %>
          <section class="collab-shell responsive-shell mx-auto max-w-5xl space-y-6">
            <header class="surface-card collab-hero rounded-3xl p-6 sm:p-8">
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
              <section class="surface-card rounded-3xl p-6">
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
                  class="btn btn-primary mt-4 w-full sm:w-auto"
                >
                  <.icon name="hero-paper-airplane" class="size-4" /> Gerar link de convite
                </button>

                <div :if={@invite_url} class="mt-4 space-y-2">
                  <p class="text-xs font-semibold uppercase tracking-[0.12em] text-base-content/62">
                    Link gerado
                  </p>
                  <div
                    id="invite-url"
                    class="micro-surface rounded-xl border border-base-content/15 p-3 break-all text-sm font-mono text-base-content/90"
                  >
                    {@invite_url}
                  </div>
                  <div class="flex flex-wrap items-center gap-2">
                    <button
                      id="copy-invite-url-btn"
                      type="button"
                      phx-click="copy_invite_url"
                      class="btn btn-soft btn-xs sm:btn-sm"
                    >
                      <.icon name="hero-clipboard-document" class="size-4" /> Copiar link
                    </button>
                    <p class="text-xs text-base-content/68">
                      Envie este link para a outra pessoa aceitar o convite em 1 clique.
                    </p>
                  </div>
                </div>
              </section>

              <section class="surface-card rounded-3xl p-6">
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

  defp extract_invite_token(%{"invite" => %{"token" => token}}), do: String.trim(token || "")
  defp extract_invite_token(%{"token" => token}), do: String.trim(token || "")
  defp extract_invite_token(_), do: ""

  defp parse_int(value) when is_integer(value), do: {:ok, value}

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_int(_), do: :error

  defp deactivate_link(socket, link_id) do
    scope = socket.assigns.current_scope

    with {:ok, _link} <- SharedFinance.deactivate_account_link(scope, link_id) do
      {:ok, links} = SharedFinance.list_account_links(scope)
      sharing_metrics = load_sharing_metrics(scope, links)

      socket
      |> assign(:pending_link_deactivation, nil)
      |> assign(:account_links, links)
      |> assign(:sharing_metrics, sharing_metrics)
      |> put_flash(:info, "Compartilhamento desativado.")
    else
      _ ->
        socket
        |> assign(:pending_link_deactivation, nil)
        |> put_flash(:error, "Não foi possível desativar o compartilhamento.")
    end
  end

  defp load_sharing_metrics(scope, links) do
    {:ok, finances} =
      Planning.list_finance_entries(scope, %{
        days: "365",
        kind: "all",
        expense_profile: "all",
        payment_method: "all"
      })

    finances_shared_total = Enum.count(finances, &is_integer(&1.shared_with_link_id))

    %{
      links_active: length(links),
      finances_shared_total: finances_shared_total,
      shared_total: finances_shared_total
    }
  end

  defp partner_email(user_id, link) do
    if user_id == link.user_a_id do
      link.user_b.email
    else
      link.user_a.email
    end
  end
end
