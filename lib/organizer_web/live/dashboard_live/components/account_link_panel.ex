defmodule OrganizerWeb.DashboardLive.Components.AccountLinkPanel do
  use OrganizerWeb, :html

  attr :account_links, :list, required: true
  attr :current_user_id, :integer, required: true

  def account_link_panel(assigns) do
    ~H"""
    <section
      id="account-link-panel"
      class="surface-card order-2 rounded-2xl p-4 scroll-mt-20"
      data-onboarding-target="account-link"
    >
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div class="space-y-1">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
            Vínculo entre contas
          </h2>
          <p class="text-xs text-base-content/65">
            Conecte duas contas para compartilhar lançamentos e acompanhar acertos em conjunto.
          </p>
        </div>

        <span class={[
          "inline-flex w-fit items-center gap-1.5 rounded-full border px-3 py-1 text-[0.68rem] font-semibold uppercase tracking-[0.08em]",
          Enum.empty?(@account_links) && "border-warning/35 bg-warning/12 text-warning",
          not Enum.empty?(@account_links) &&
            "border-success/40 bg-success/12 text-success-content"
        ]}>
          <.icon
            name={if(Enum.empty?(@account_links), do: "hero-link-slash", else: "hero-link")}
            class="size-3.5"
          />
          {if Enum.empty?(@account_links), do: "Sem vínculo ativo", else: "Vínculo ativo"}
        </span>
      </div>

      <%= if Enum.empty?(@account_links) do %>
        <div id="account-link-empty-state" class="micro-surface mt-4 grid gap-4 rounded-xl p-4">
          <p class="text-sm leading-6 text-base-content/80">
            Gere um convite para conectar outra pessoa e ativar o fluxo de finanças compartilhadas.
          </p>

          <div class="flex flex-wrap gap-2">
            <.link
              id="account-link-create-btn"
              navigate={~p"/account-links/invite"}
              class="btn btn-primary btn-sm"
            >
              <.icon name="hero-paper-airplane" class="size-4" /> Criar convite
            </.link>
            <.link
              id="account-link-open-area-btn"
              navigate={~p"/account-links"}
              class="btn btn-soft btn-sm"
            >
              Abrir área de vínculos
            </.link>
          </div>
        </div>
      <% else %>
        <div id="account-link-list" class="mt-4 grid gap-2">
          <article
            :for={link <- Enum.take(@account_links, 3)}
            id={"dashboard-account-link-#{link.id}"}
            class="micro-surface flex flex-col gap-3 rounded-xl p-3 sm:flex-row sm:items-center sm:justify-between"
          >
            <div class="min-w-0">
              <p class="truncate text-sm font-semibold text-base-content/92">
                {partner_email(@current_user_id, link)}
              </p>
              <p class="text-xs text-base-content/65">
                Vínculo #{link.id} • status ativo
              </p>
            </div>

            <div class="flex flex-wrap gap-2">
              <.link
                id={"dashboard-open-link-#{link.id}"}
                navigate={~p"/account-links/#{link.id}"}
                class="btn btn-soft btn-xs"
              >
                Finanças
              </.link>
              <.link
                id={"dashboard-settlement-link-#{link.id}"}
                navigate={~p"/account-links/#{link.id}/settlement"}
                class="btn btn-outline btn-xs"
              >
                Acerto
              </.link>
            </div>
          </article>
        </div>

        <div :if={length(@account_links) > 3} class="mt-2 text-xs text-base-content/60">
          +{length(@account_links) - 3} vínculo(s) disponível(is) na área completa.
        </div>

        <div class="mt-3">
          <.link
            id="account-link-manage-btn"
            navigate={~p"/account-links"}
            class="btn btn-soft btn-sm"
          >
            Gerenciar vínculos
          </.link>
        </div>
      <% end %>
    </section>
    """
  end

  defp partner_email(current_user_id, link) do
    if current_user_id == link.user_a_id do
      link.user_b.email
    else
      link.user_a.email
    end
  end
end
