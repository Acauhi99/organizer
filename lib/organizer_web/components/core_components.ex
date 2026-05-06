defmodule OrganizerWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework.
  Here are useful references:

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: OrganizerWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :auto_dismiss_ms, :integer, default: 3000, doc: "auto dismiss delay in milliseconds"
  attr :autohide, :boolean, default: true, doc: "whether flash auto-dismisses"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      data-auto-dismiss-ms={if @autohide, do: @auto_dismiss_ms, else: nil}
      class="fixed right-4 top-4 z-50 w-[min(24rem,calc(100vw-2rem))]"
      {@rest}
    >
      <div class={[
        "flex items-start gap-3 rounded-2xl border px-3 py-2.5 text-wrap shadow-[0_20px_54px_-28px_rgba(15,23,42,0.85)] backdrop-blur",
        @kind == :info &&
          "border-cyan-300/45 bg-slate-900/94 text-cyan-100 shadow-[0_18px_52px_-28px_rgba(34,211,238,0.45)]",
        @kind == :error &&
          "border-rose-300/55 bg-slate-900/95 text-rose-100 shadow-[0_18px_52px_-28px_rgba(244,63,94,0.5)]"
      ]}>
        <.icon
          :if={@kind == :info}
          name="hero-information-circle"
          class="mt-0.5 size-5 shrink-0 text-cyan-200"
        />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-circle"
          class="mt-0.5 size-5 shrink-0 text-rose-200"
        />
        <div class="min-w-0">
          <p :if={@title} class="font-semibold text-base-content">{@title}</p>
          <p class="text-sm leading-6 text-base-content/88">{msg}</p>
        </div>
        <button
          type="button"
          class="ml-auto inline-flex items-center justify-center self-start rounded-lg border border-slate-400/30 bg-slate-900/70 p-1 text-slate-300 transition hover:border-cyan-300/45 hover:text-cyan-100"
          aria-label={gettext("close")}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any, default: nil
  attr :variant, :string, values: ~w(primary soft outline)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    base_class = [
      "inline-flex items-center justify-center gap-2 rounded-xl border px-3 py-2 text-sm font-semibold transition duration-200 ease-out focus-visible:outline-none focus-visible:ring-2",
      button_variant_class(assigns[:variant]),
      disabled_button_class(rest[:disabled])
    ]

    merged_class = base_class ++ List.wrap(assigns[:class])
    assigns = assign(assigns, :class, merged_class)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  defp button_variant_class("primary") do
    "border-cyan-200/70 bg-gradient-to-r from-cyan-300 to-emerald-300 text-slate-950 shadow-[0_14px_30px_-16px_rgba(34,211,238,0.72)] hover:from-cyan-200 hover:to-emerald-200 focus-visible:ring-cyan-100/70"
  end

  defp button_variant_class("outline") do
    "border-cyan-300/45 bg-transparent text-slate-100 hover:border-cyan-200/70 hover:bg-cyan-400/12 focus-visible:ring-cyan-300/40"
  end

  defp button_variant_class(_variant) do
    "border-cyan-300/30 bg-slate-900/82 text-cyan-100 hover:border-cyan-200/70 hover:bg-cyan-400/15 focus-visible:ring-cyan-300/35"
  end

  defp disabled_button_class(true), do: "cursor-not-allowed opacity-55 saturate-75"
  defp disabled_button_class("true"), do: "cursor-not-allowed opacity-55 saturate-75"
  defp disabled_button_class(_), do: nil

  @doc """
  Renders a standardized modal shell with shared backdrop and dialog behavior.
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :cancel_event, :string, default: nil
  attr :aria_labelledby, :string, default: nil
  attr :aria_describedby, :string, default: nil
  attr :z_index_class, :string, default: "z-[120]"
  attr :container_class, :string, default: nil
  attr :dialog_class, :string, default: nil
  attr :backdrop_class, :string, default: nil
  attr :close_on_escape, :boolean, default: true
  attr :close_on_backdrop, :boolean, default: true
  attr :rest, :global

  slot :overlay
  slot :inner_block, required: true

  def app_modal(assigns) do
    ~H"""
    <div
      :if={@show}
      id={@id}
      class={[
        "fixed inset-0 flex items-end justify-center px-3 py-4 sm:items-center sm:p-6",
        @container_class,
        @z_index_class
      ]}
      phx-window-keydown={if @close_on_escape, do: @cancel_event}
      phx-key={if @close_on_escape, do: "escape"}
      aria-hidden="false"
      {@rest}
    >
      <%= if @close_on_backdrop and is_binary(@cancel_event) do %>
        <button
          id={"#{@id}-backdrop"}
          type="button"
          phx-click={@cancel_event}
          aria-label={gettext("close")}
          class={[
            "absolute inset-0 bg-slate-950/66 backdrop-blur-[3px]",
            @backdrop_class
          ]}
        >
        </button>
      <% else %>
        <div
          id={"#{@id}-backdrop"}
          aria-hidden="true"
          class={[
            "absolute inset-0 bg-slate-950/66 backdrop-blur-[3px]",
            @backdrop_class
          ]}
        >
        </div>
      <% end %>

      {render_slot(@overlay)}

      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby={@aria_labelledby}
        aria-describedby={@aria_describedby}
        class={[
          "relative z-10 w-full rounded-3xl border border-base-content/16 bg-base-100 shadow-[0_40px_120px_rgba(8,19,35,0.55)]",
          @dialog_class
        ]}
      >
        {render_slot(@inner_block)}
      </section>
    </div>
    """
  end

  @doc """
  Renders a confirmation modal for destructive actions.
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :title, :string, required: true
  attr :message, :string, required: true
  attr :confirm_event, :string, required: true
  attr :cancel_event, :string, required: true
  attr :confirm_label, :string, default: "Confirmar exclusão"
  attr :cancel_label, :string, default: "Cancelar"
  attr :confirm_button_id, :string, default: nil
  attr :cancel_button_id, :string, default: nil
  attr :severity, :string, default: "danger", values: ~w(danger critical)
  attr :impact_label, :string, default: nil

  slot :inner_block

  def destructive_confirm_modal(assigns) do
    assigns =
      assigns
      |> assign_new(:confirm_button_id, fn -> "#{assigns.id}-confirm" end)
      |> assign_new(:cancel_button_id, fn -> "#{assigns.id}-cancel" end)
      |> assign(:dialog_class, destructive_dialog_class(assigns.severity))
      |> assign(:icon_name, destructive_icon_name(assigns.severity))
      |> assign(:icon_wrapper_class, destructive_icon_wrapper_class(assigns.severity))
      |> assign(:impact_badge_class, destructive_impact_badge_class(assigns.severity))
      |> assign(:confirm_button_class, destructive_confirm_button_class(assigns.severity))

    ~H"""
    <.app_modal
      id={@id}
      show={@show}
      cancel_event={@cancel_event}
      aria_labelledby={"#{@id}-title"}
      z_index_class="z-[140]"
      backdrop_class="bg-slate-950/70 backdrop-blur-[2px]"
      dialog_class={@dialog_class}
    >
      <div class="flex items-start gap-3">
        <div class={@icon_wrapper_class}>
          <.icon name={@icon_name} class="size-5" />
        </div>
        <div class="min-w-0">
          <h2 id={"#{@id}-title"} class="text-base font-semibold text-base-content">
            {@title}
          </h2>
          <p class="mt-1 text-sm leading-6 text-base-content/74">
            {@message}
          </p>
          <p
            :if={is_binary(@impact_label) and String.trim(@impact_label) != ""}
            class={@impact_badge_class}
          >
            {@impact_label}
          </p>
          <div :if={@inner_block != []} class="mt-2 text-sm text-base-content/82">
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>

      <div class="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
        <button
          id={@cancel_button_id}
          type="button"
          phx-click={@cancel_event}
          class={destructive_cancel_button_class()}
        >
          {@cancel_label}
        </button>
        <button
          id={@confirm_button_id}
          type="button"
          phx-click={@confirm_event}
          class={@confirm_button_class}
        >
          {@confirm_label}
        </button>
      </div>
    </.app_modal>
    """
  end

  defp destructive_dialog_class("critical") do
    "max-w-md rounded-2xl border-error/45 p-5 shadow-[0_32px_110px_rgba(10,18,34,0.62)] sm:p-6"
  end

  defp destructive_dialog_class(_severity) do
    "max-w-md rounded-2xl border-error/30 p-5 shadow-[0_32px_110px_rgba(10,18,34,0.56)] sm:p-6"
  end

  defp destructive_icon_name("critical"), do: "hero-exclamation-circle"
  defp destructive_icon_name(_severity), do: "hero-exclamation-triangle"

  defp destructive_icon_wrapper_class("critical") do
    "mt-0.5 rounded-full border border-error/45 bg-error/18 p-2 text-error"
  end

  defp destructive_icon_wrapper_class(_severity) do
    "mt-0.5 rounded-full border border-error/35 bg-error/14 p-2 text-error"
  end

  defp destructive_impact_badge_class("critical") do
    "mt-2 inline-flex rounded-full border border-error/42 bg-error/15 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.12em] text-error"
  end

  defp destructive_impact_badge_class(_severity) do
    "mt-2 inline-flex rounded-full border border-base-content/16 bg-base-100/65 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.12em] text-base-content/76"
  end

  defp destructive_cancel_button_class do
    "inline-flex items-center justify-center rounded-xl border border-slate-400/30 bg-slate-900/70 px-3 py-1.5 text-xs font-semibold text-slate-200 transition hover:border-cyan-300/45 hover:text-cyan-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/35"
  end

  defp destructive_confirm_button_class(_severity) do
    "inline-flex items-center justify-center rounded-xl border border-rose-300/55 bg-rose-500/18 px-3 py-1.5 text-xs font-semibold text-rose-100 shadow-[0_14px_30px_-16px_rgba(244,63,94,0.7)] transition hover:border-rose-200/75 hover:bg-rose-500/26 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-300/45"
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-3 space-y-1.5">
      <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
      <label class="inline-flex cursor-pointer items-center gap-2 text-sm text-base-content/88">
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={[
            @class ||
              "size-4 rounded border border-cyan-300/45 bg-slate-900/85 text-cyan-300 shadow-[inset_0_0_0_1px_rgba(34,211,238,0.08)] transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300/35",
            @errors != [] && (@error_class || "border-rose-300/70 ring-2 ring-rose-300/25")
          ]}
          {@rest}
        />
        <span class="text-xs font-semibold uppercase tracking-[0.12em] text-base-content/72">
          {@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-3 space-y-1.5">
      <label
        :if={@label}
        for={@id}
        class="block text-xs font-semibold uppercase tracking-[0.12em] text-base-content/68"
      >
        {@label}
      </label>
      <select
        id={@id}
        name={@name}
        class={[
          @class ||
            "w-full rounded-xl border border-cyan-300/22 bg-slate-900/82 px-3 py-2 text-sm text-base-content transition focus:border-cyan-200/60 focus:outline-none focus:ring-2 focus:ring-cyan-300/25",
          @errors != [] && (@error_class || "border-rose-300/70 ring-2 ring-rose-300/25")
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-3 space-y-1.5">
      <label
        :if={@label}
        for={@id}
        class="block text-xs font-semibold uppercase tracking-[0.12em] text-base-content/68"
      >
        {@label}
      </label>
      <textarea
        id={@id}
        name={@name}
        class={[
          @class ||
            "w-full rounded-xl border border-cyan-300/22 bg-slate-900/82 px-3 py-2 text-sm text-base-content transition focus:border-cyan-200/60 focus:outline-none focus:ring-2 focus:ring-cyan-300/25",
          @errors != [] && (@error_class || "border-rose-300/70 ring-2 ring-rose-300/25")
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="mb-3 space-y-1.5">
      <label
        :if={@label}
        for={@id}
        class="block text-xs font-semibold uppercase tracking-[0.12em] text-base-content/68"
      >
        {@label}
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          @class ||
            "w-full rounded-xl border border-cyan-300/22 bg-slate-900/82 px-3 py-2 text-sm text-base-content placeholder:text-base-content/45 transition focus:border-cyan-200/60 focus:outline-none focus:ring-2 focus:ring-cyan-300/25",
          @errors != [] && (@error_class || "border-rose-300/70 ring-2 ring-rose-300/25")
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Shared function used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[
      @actions != [] && "flex items-center justify-between gap-6",
      "pb-4 border-b border-base-content/10"
    ]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 tracking-tight">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-x-auto rounded-2xl border border-cyan-300/20 bg-slate-900/72 shadow-[0_20px_56px_-34px_rgba(34,211,238,0.35)]">
      <table class="w-full min-w-[40rem] border-collapse">
        <thead class="bg-slate-900/92">
          <tr class="border-b border-cyan-300/18">
            <th
              :for={col <- @col}
              class="px-3 py-2 text-left text-[0.72rem] font-semibold uppercase tracking-[0.1em] text-base-content/72"
            >
              {col[:label]}
            </th>
            <th
              :if={@action != []}
              class="px-3 py-2 text-left text-[0.72rem] font-semibold uppercase tracking-[0.1em] text-base-content/72"
            >
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
          class="divide-y divide-cyan-300/14"
        >
          <tr
            :for={row <- @rows}
            id={@row_id && @row_id.(row)}
            class="odd:bg-slate-900/62 even:bg-slate-900/48"
          >
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={[
                "px-3 py-2 text-sm text-base-content/90",
                @row_click && "cursor-pointer hover:bg-cyan-400/8"
              ]}
            >
              {render_slot(col, @row_item.(row))}
            </td>
            <td :if={@action != []} class="w-0 px-3 py-2 text-sm font-semibold">
              <div class="flex gap-2">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Wrapper around Flop.Phoenix.pagination with app defaults.
  """
  attr :meta, Flop.Meta, required: true
  attr :path, :any, default: nil
  attr :on_paginate, JS, default: nil
  attr :target, :string, default: nil
  attr :class, :string, default: nil
  attr :aria_label, :string, default: "Pagination"
  attr :window_size, :integer, default: 5
  attr :scroll_to, :string, default: nil

  def pagination(assigns) do
    current_page = Map.get(assigns.meta, :current_page, 1)
    total_pages = max(Map.get(assigns.meta, :total_pages, 1), 1)
    total_count = Map.get(assigns.meta, :total_count, 0) || 0
    page_size = Map.get(assigns.meta, :page_size, 0) || 0

    {start_item, end_item} =
      if total_count == 0 or page_size <= 0 do
        {0, 0}
      else
        start_item = (current_page - 1) * page_size + 1
        end_item = min(current_page * page_size, total_count)
        {start_item, end_item}
      end

    page_numbers = pagination_window_pages(current_page, total_pages, assigns.window_size)
    on_paginate = pagination_on_paginate(assigns.on_paginate, assigns.scroll_to)

    assigns =
      assigns
      |> assign(:current_page, current_page)
      |> assign(:total_pages, total_pages)
      |> assign(:total_count, total_count)
      |> assign(:start_item, start_item)
      |> assign(:end_item, end_item)
      |> assign(:page_numbers, page_numbers)
      |> assign(:on_paginate, on_paginate)

    ~H"""
    <nav
      aria-label={@aria_label}
      class={[
        "mt-4 rounded-2xl border border-base-content/12 bg-base-100/55 p-3.5 backdrop-blur sm:p-4",
        @class
      ]}
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <p class="text-[0.7rem] font-medium uppercase tracking-[0.14em] text-base-content/66">
          Exibindo {@start_item}–{@end_item} de {@total_count}
        </p>
        <p class="rounded-full border border-base-content/16 bg-base-100/75 px-3 py-1 text-xs font-semibold text-base-content/86">
          Página {@current_page} de {@total_pages}
        </p>
      </div>

      <div class="mt-3 flex items-center justify-between gap-2">
        <.pagination_link
          page={@current_page - 1}
          enabled={@current_page > 1}
          path={@path}
          on_paginate={@on_paginate}
          target={@target}
          class="min-w-[6.3rem] justify-center"
          aria_label="Página anterior"
        >
          <.icon name="hero-chevron-left" class="size-3.5" /> Anterior
        </.pagination_link>

        <div class="hidden flex-wrap items-center justify-center gap-1 sm:flex">
          <.pagination_link
            :for={page_number <- @page_numbers}
            page={page_number}
            enabled={true}
            path={@path}
            on_paginate={@on_paginate}
            target={@target}
            class="min-w-9 justify-center"
            aria_current={if page_number == @current_page, do: "page"}
            active={page_number == @current_page}
            aria_label={"Ir para página #{page_number}"}
          >
            {page_number}
          </.pagination_link>
        </div>

        <.pagination_link
          page={@current_page + 1}
          enabled={@current_page < @total_pages}
          path={@path}
          on_paginate={@on_paginate}
          target={@target}
          class="min-w-[6.3rem] justify-center"
          aria_label="Próxima página"
        >
          Próxima <.icon name="hero-chevron-right" class="size-3.5" />
        </.pagination_link>
      </div>
    </nav>
    """
  end

  attr :page, :integer, required: true
  attr :enabled, :boolean, default: true
  attr :path, :any, default: nil
  attr :on_paginate, JS, default: nil
  attr :target, :string, default: nil
  attr :class, :string, default: nil
  attr :active, :boolean, default: false
  attr :aria_current, :string, default: nil
  attr :aria_label, :string, default: nil
  slot :inner_block, required: true

  defp pagination_link(assigns) do
    base_class = [
      "inline-flex items-center gap-1 rounded-xl border px-3 py-1.5 text-xs font-semibold transition",
      assigns.active &&
        "border-primary/55 bg-primary/14 text-primary shadow-[0_0_0_1px_color-mix(in_oklab,var(--color-primary)_24%,transparent)]",
      !assigns.active &&
        "border-base-content/20 bg-base-100/82 text-base-content/78 hover:border-info/42 hover:bg-info/12 hover:text-base-content",
      !assigns.enabled &&
        "cursor-not-allowed border-base-content/12 text-base-content/38 opacity-70",
      assigns.class
    ]

    assigns = assign(assigns, :base_class, base_class)

    cond do
      not assigns.enabled ->
        ~H"""
        <button
          type="button"
          class={@base_class}
          disabled
          aria-disabled="true"
          aria-label={@aria_label}
        >
          {render_slot(@inner_block)}
        </button>
        """

      is_binary(assigns.path) ->
        ~H"""
        <.link
          patch={pagination_path(@path, @page)}
          phx-click={@on_paginate}
          phx-value-page={if @on_paginate, do: @page}
          phx-target={@target}
          aria-current={@aria_current}
          aria-label={@aria_label}
          class={@base_class}
        >
          {render_slot(@inner_block)}
        </.link>
        """

      not is_nil(assigns.on_paginate) ->
        ~H"""
        <button
          type="button"
          phx-click={@on_paginate}
          phx-value-page={@page}
          phx-target={@target}
          aria-current={@aria_current}
          aria-label={@aria_label}
          class={@base_class}
        >
          {render_slot(@inner_block)}
        </button>
        """

      true ->
        ~H"""
        <button
          type="button"
          class={@base_class}
          aria-current={@aria_current}
          aria-label={@aria_label}
        >
          {render_slot(@inner_block)}
        </button>
        """
    end
  end

  defp pagination_window_pages(current_page, total_pages, window_size)
       when is_integer(current_page) and is_integer(total_pages) and total_pages > 0 do
    window_size = max(window_size, 1)

    cond do
      total_pages <= window_size ->
        Enum.to_list(1..total_pages)

      true ->
        half = div(window_size, 2)
        raw_start = current_page - half
        raw_end = current_page + half

        start_page = max(raw_start, 1)
        end_page = min(raw_end, total_pages)
        visible_count = end_page - start_page + 1

        {start_page, end_page} =
          cond do
            visible_count == window_size ->
              {start_page, end_page}

            start_page == 1 ->
              {1, min(total_pages, window_size)}

            end_page == total_pages ->
              {max(1, total_pages - window_size + 1), total_pages}

            true ->
              {start_page, end_page}
          end

        Enum.to_list(start_page..end_page)
    end
  end

  defp pagination_window_pages(_current_page, _total_pages, _window_size), do: [1]

  defp pagination_path(path, page) when is_binary(path) and is_integer(page) and page > 0 do
    uri = URI.parse(path)
    query_params = if uri.query, do: Plug.Conn.Query.decode(uri.query), else: %{}

    new_query =
      query_params |> Map.put("page", Integer.to_string(page)) |> Plug.Conn.Query.encode()

    uri
    |> Map.put(:query, new_query)
    |> URI.to_string()
  end

  defp pagination_path(path, _page), do: path

  defp pagination_on_paginate(on_paginate, scroll_to) do
    scroll_to =
      case scroll_to do
        value when is_binary(value) -> String.trim(value)
        _ -> nil
      end

    cond do
      is_nil(scroll_to) or scroll_to == "" ->
        on_paginate

      is_nil(on_paginate) ->
        JS.dispatch("phx:scroll-to-element", detail: %{selector: scroll_to})

      true ->
        JS.dispatch(on_paginate, "phx:scroll-to-element", detail: %{selector: scroll_to})
    end
  end

  @doc """
  Wrapper around Flop.Phoenix.filter_fields.
  """
  attr :form, :any, required: true
  attr :fields, :list, required: true
  slot :inner_block, required: true

  def filter_fields(assigns) do
    ~H"""
    <Flop.Phoenix.filter_fields :let={entry} form={@form} fields={@fields}>
      {render_slot(@inner_block, entry)}
    </Flop.Phoenix.filter_fields>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="space-y-2 rounded-2xl border border-cyan-300/18 bg-slate-900/70 p-2.5 shadow-[0_18px_48px_-30px_rgba(34,211,238,0.4)]">
      <li
        :for={item <- @item}
        class="rounded-xl border border-cyan-300/15 bg-slate-900/75 p-3"
      >
        <div>
          <div class="text-sm font-semibold text-base-content">{item.title}</div>
          <div class="mt-1 text-sm text-base-content/82">{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(OrganizerWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(OrganizerWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
