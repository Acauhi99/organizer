defmodule OrganizerWeb.AccountLinkLive do
  use OrganizerWeb, :live_view

  alias Organizer.SharedFinance

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Organizer.PubSub, "account_links:#{scope.user.id}")
    end

    {:ok, links} = SharedFinance.list_account_links(scope)

    socket =
      socket
      |> assign(:current_scope, scope)
      |> assign(:account_links, links)
      |> assign(:invite_url, nil)
      |> assign(:invite_token, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    socket =
      case socket.assigns.live_action do
        :index -> assign(socket, :page_title, "Vínculos")
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
  def handle_event("accept_invite", %{"token" => token}, socket) do
    scope = socket.assigns.current_scope

    case SharedFinance.accept_invite(scope, token) do
      {:ok, link} ->
        {:noreply,
         socket
         |> put_flash(:info, "Vínculo estabelecido com sucesso.")
         |> push_navigate(to: ~p"/account-links/#{link.id}")}

      {:error, :invite_invalid} ->
        {:noreply, put_flash(socket, :error, "Convite inválido ou expirado.")}

      {:error, :self_invite_not_allowed} ->
        {:noreply, put_flash(socket, :error, "Você não pode aceitar o próprio convite.")}

      {:error, :link_already_exists} ->
        {:noreply, put_flash(socket, :error, "Já existe um vínculo ativo com este usuário.")}
    end
  end

  @impl true
  def handle_event("deactivate_link", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case SharedFinance.deactivate_account_link(scope, String.to_integer(id)) do
      {:ok, _link} ->
        {:ok, links} = SharedFinance.list_account_links(scope)

        {:noreply,
         socket
         |> assign(:account_links, links)
         |> put_flash(:info, "Vínculo desativado.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível desativar o vínculo.")}
    end
  end

  @impl true
  def handle_info({:account_link_updated, _}, socket) do
    scope = socket.assigns.current_scope
    {:ok, links} = SharedFinance.list_account_links(scope)
    {:noreply, assign(socket, :account_links, links)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%= case @live_action do %>
        <% :index -> %>
          <div class="max-w-2xl mx-auto p-6">
            <div class="flex items-center justify-between mb-6">
              <h1 class="text-2xl font-semibold text-base-content">Vínculos</h1>
              <.link
                navigate={~p"/account-links/invite"}
                id="new-invite-btn"
                class="btn btn-primary btn-sm"
              >
                Novo Convite
              </.link>
            </div>

            <ul id="account-links-list" class="space-y-3">
              <%= for link <- @account_links do %>
                <li
                  id={"account-link-#{link.id}"}
                  class="surface-card flex items-center justify-between p-4"
                >
                  <span class="text-base-content font-mono text-sm">
                    {partner_email(@current_scope.user.id, link)}
                  </span>
                  <button
                    id={"deactivate-link-#{link.id}"}
                    phx-click="deactivate_link"
                    phx-value-id={link.id}
                    class="btn btn-outline btn-sm btn-error"
                  >
                    Desativar
                  </button>
                </li>
              <% end %>
            </ul>
          </div>
        <% :new_invite -> %>
          <div class="max-w-lg mx-auto p-6">
            <h1 class="text-2xl font-semibold text-base-content mb-6">Novo Convite</h1>

            <div class="surface-card p-6 space-y-4">
              <button id="create-invite-btn" phx-click="create_invite" class="btn btn-primary w-full">
                Gerar link de convite
              </button>

              <%= if @invite_url do %>
                <div class="space-y-2">
                  <p class="text-sm text-base-content/70">Compartilhe este link:</p>
                  <div
                    id="invite-url"
                    class="micro-surface p-3 rounded-lg break-all text-sm font-mono text-base-content"
                  >
                    {@invite_url}
                  </div>
                </div>
              <% end %>
            </div>

            <div class="surface-card p-6 mt-4">
              <h2 class="text-lg font-semibold text-base-content mb-4">Aceitar convite</h2>
              <form id="accept-invite-form" phx-submit="accept_invite" class="space-y-3">
                <div>
                  <label class="block text-sm font-medium text-base-content/70 mb-1">
                    Token do convite
                  </label>
                  <input
                    type="text"
                    name="token"
                    placeholder="Cole o token aqui"
                    class="input input-bordered w-full"
                  />
                </div>
                <button type="submit" class="btn btn-primary w-full">
                  Aceitar convite
                </button>
              </form>
            </div>
          </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp partner_email(user_id, link) do
    if user_id == link.user_a_id do
      link.user_b.email
    else
      link.user_a.email
    end
  end
end
