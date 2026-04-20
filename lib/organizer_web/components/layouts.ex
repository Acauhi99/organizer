defmodule OrganizerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use OrganizerWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :wide, :boolean,
    default: false,
    doc: "when true uses a wider content container for dashboard and analytics views"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class={["px-4 pb-2 pt-4 sm:px-6 lg:px-8", !@current_scope && "public-shell-header"]}>
      <div class={[
        "surface-card mx-auto flex max-w-7xl flex-col gap-4 rounded-3xl p-4 sm:flex-row sm:items-center sm:justify-between sm:p-6",
        !@current_scope && "public-shell-header-card"
      ]}>
        <div class="space-y-1">
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-base-content/60">
            Organizer
          </p>
          <p class="text-sm text-base-content/80">
            Registro rápido por formulário e vínculo por link para compartilhar com contexto.
          </p>
        </div>

        <div class="flex items-center gap-3">
          <%= if @current_scope do %>
            <.link href={~p"/dashboard"} class="btn btn-outline btn-sm header-cta tracking-[0.02em]">
              Painel
            </.link>
          <% else %>
            <.link
              href={~p"/users/register"}
              class="btn btn-outline btn-sm header-cta tracking-[0.02em]"
            >
              Criar conta
            </.link>
          <% end %>
        </div>
      </div>
    </header>

    <main id="main-content" class="px-4 py-8 sm:px-6 sm:py-12 lg:px-8">
      <div class={["mx-auto space-y-4", @wide && "max-w-7xl", !@wide && "max-w-2xl"]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Não conseguimos acessar a internet")}
        autohide={false}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Tentando reconectar")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Algo deu errado!")}
        autohide={false}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Tentando reconectar")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
