defmodule OrganizerWeb.DashboardLive.Components.PlanningOperationsPanel do
  use Phoenix.Component

  import OrganizerWeb.CoreComponents,
    only: [app_modal: 1, button: 1, destructive_confirm_modal: 1, icon: 1, input: 1]

  alias Organizer.DateSupport

  attr :fixed_cost_form, :any, required: true
  attr :important_date_form, :any, required: true
  attr :fixed_costs, :list, default: []
  attr :important_dates, :list, default: []
  attr :fixed_cost_edit_entry, :any, default: nil
  attr :fixed_cost_edit_form, :any, required: true
  attr :important_date_edit_entry, :any, default: nil
  attr :important_date_edit_form, :any, required: true
  attr :pending_fixed_cost_delete, :any, default: nil
  attr :pending_important_date_delete, :any, default: nil

  def planning_operations_panel(assigns) do
    ~H"""
    <section id="planning-operations-panel" class="surface-card rounded-2xl p-4 scroll-mt-20">
      <div class="max-w-3xl">
        <h2 class="text-2xl font-black tracking-[-0.02em] text-base-content">
          Custos fixos e datas importantes
        </h2>
        <p class="text-sm leading-6 text-base-content/75">
          Configure lembretes operacionais para reduzir esquecimentos e facilitar correções futuras.
        </p>
      </div>

      <div class="mt-4 grid gap-4 xl:grid-cols-2">
        <article
          id="fixed-costs-form-card"
          class="micro-surface rounded-xl border border-base-content/14 p-4"
        >
          <h3 class="text-sm font-semibold uppercase tracking-[0.12em] text-base-content/70">
            Novo custo fixo
          </h3>

          <.form
            for={@fixed_cost_form}
            id="fixed-cost-form"
            phx-submit="create_fixed_cost"
            class="mt-3 space-y-3"
          >
            <.input field={@fixed_cost_form[:name]} type="text" label="Nome" required />
            <.input
              field={@fixed_cost_form[:amount_cents]}
              type="text"
              label="Valor"
              placeholder="Ex: 350,00"
              inputmode="numeric"
              data-money-mask="true"
              required
            />

            <div class="grid gap-3 sm:grid-cols-2">
              <.input
                field={@fixed_cost_form[:billing_day]}
                type="number"
                label="Dia de cobrança"
                min="1"
                max="31"
                step="1"
                required
              />
              <.input
                field={@fixed_cost_form[:starts_on]}
                type="text"
                label="Início (opcional)"
                placeholder="dd/mm/aaaa"
                inputmode="numeric"
                maxlength="10"
                pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
                data-date-picker="date"
              />
            </div>

            <.input
              field={@fixed_cost_form[:active]}
              type="select"
              label="Status"
              options={[{"Ativo", "true"}, {"Inativo", "false"}]}
            />

            <.button type="submit" variant="primary" class="w-full sm:w-auto">
              Salvar custo fixo
            </.button>
          </.form>
        </article>

        <article
          id="important-dates-form-card"
          class="micro-surface rounded-xl border border-base-content/14 p-4"
        >
          <h3 class="text-sm font-semibold uppercase tracking-[0.12em] text-base-content/70">
            Nova data importante
          </h3>

          <.form
            for={@important_date_form}
            id="important-date-form"
            phx-submit="create_important_date"
            class="mt-3 space-y-3"
          >
            <.input field={@important_date_form[:title]} type="text" label="Título" required />

            <div class="grid gap-3 sm:grid-cols-2">
              <.input
                field={@important_date_form[:category]}
                type="select"
                label="Categoria"
                options={important_date_category_options()}
              />
              <.input
                field={@important_date_form[:date]}
                type="text"
                label="Data"
                placeholder="dd/mm/aaaa"
                inputmode="numeric"
                maxlength="10"
                pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
                data-date-picker="date"
                required
              />
            </div>

            <.input
              field={@important_date_form[:notes]}
              type="text"
              label="Observações"
              placeholder="Opcional"
            />

            <.button type="submit" variant="primary" class="w-full sm:w-auto">
              Salvar data importante
            </.button>
          </.form>
        </article>
      </div>

      <div class="mt-4 grid gap-4 xl:grid-cols-2">
        <article
          id="fixed-costs-list-card"
          class="micro-surface rounded-xl border border-base-content/14 p-4"
        >
          <div class="flex items-center justify-between gap-2">
            <h3 class="text-sm font-semibold uppercase tracking-[0.12em] text-base-content/70">
              Custos fixos
            </h3>
            <span class="text-xs text-base-content/62">{length(@fixed_costs)} item(ns)</span>
          </div>

          <ul id="fixed-costs-list" class="mt-3 space-y-2">
            <li
              :if={Enum.empty?(@fixed_costs)}
              id="fixed-costs-empty"
              class="rounded-xl border border-dashed border-base-content/25 px-4 py-6 text-sm text-base-content/72"
            >
              Nenhum custo fixo cadastrado.
            </li>

            <li
              :for={cost <- @fixed_costs}
              id={"fixed-cost-#{cost.id}"}
              class="rounded-xl border border-base-content/14 bg-base-100/70 p-3"
            >
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <p class="truncate text-sm font-semibold text-base-content">{cost.name}</p>
                  <p class="text-xs text-base-content/68">
                    {format_cents(cost.amount_cents)} • dia {cost.billing_day}
                    <span :if={is_struct(cost.starts_on, Date)}>
                      • início {DateSupport.format_pt_br(cost.starts_on)}
                    </span>
                  </p>
                </div>

                <span class={fixed_cost_status_badge_class(cost.active)}>
                  {if cost.active, do: "Ativo", else: "Inativo"}
                </span>
              </div>

              <div class="mt-2 flex items-center justify-end gap-1.5">
                <button
                  id={"fixed-cost-edit-btn-#{cost.id}"}
                  type="button"
                  phx-click="start_edit_fixed_cost"
                  phx-value-id={cost.id}
                  class="ds-inline-btn rounded-md px-2 py-1 text-xs"
                >
                  Editar
                </button>
                <button
                  id={"fixed-cost-delete-btn-#{cost.id}"}
                  type="button"
                  phx-click="prompt_delete_fixed_cost"
                  phx-value-id={cost.id}
                  class="ds-inline-btn ds-inline-btn-danger rounded-md px-2 py-1 text-xs"
                >
                  Excluir
                </button>
              </div>
            </li>
          </ul>
        </article>

        <article
          id="important-dates-list-card"
          class="micro-surface rounded-xl border border-base-content/14 p-4"
        >
          <div class="flex items-center justify-between gap-2">
            <h3 class="text-sm font-semibold uppercase tracking-[0.12em] text-base-content/70">
              Datas importantes
            </h3>
            <span class="text-xs text-base-content/62">{length(@important_dates)} item(ns)</span>
          </div>

          <ul id="important-dates-list" class="mt-3 space-y-2">
            <li
              :if={Enum.empty?(@important_dates)}
              id="important-dates-empty"
              class="rounded-xl border border-dashed border-base-content/25 px-4 py-6 text-sm text-base-content/72"
            >
              Nenhuma data importante cadastrada.
            </li>

            <li
              :for={important_date <- @important_dates}
              id={"important-date-#{important_date.id}"}
              class="rounded-xl border border-base-content/14 bg-base-100/70 p-3"
            >
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <p class="truncate text-sm font-semibold text-base-content">
                    {important_date.title}
                  </p>
                  <p class="text-xs text-base-content/68">
                    {DateSupport.format_pt_br(important_date.date)} • {important_date_category_label(
                      important_date.category
                    )}
                  </p>
                  <p
                    :if={is_binary(important_date.notes) and String.trim(important_date.notes) != ""}
                    class="mt-0.5 text-xs text-base-content/70"
                  >
                    {important_date.notes}
                  </p>
                </div>
              </div>

              <div class="mt-2 flex items-center justify-end gap-1.5">
                <button
                  id={"important-date-edit-btn-#{important_date.id}"}
                  type="button"
                  phx-click="start_edit_important_date"
                  phx-value-id={important_date.id}
                  class="ds-inline-btn rounded-md px-2 py-1 text-xs"
                >
                  Editar
                </button>
                <button
                  id={"important-date-delete-btn-#{important_date.id}"}
                  type="button"
                  phx-click="prompt_delete_important_date"
                  phx-value-id={important_date.id}
                  class="ds-inline-btn ds-inline-btn-danger rounded-md px-2 py-1 text-xs"
                >
                  Excluir
                </button>
              </div>
            </li>
          </ul>
        </article>
      </div>

      <.app_modal
        id="fixed-cost-edit-modal"
        show={is_map(@fixed_cost_edit_entry)}
        cancel_event="cancel_edit_fixed_cost"
        aria_labelledby={if is_map(@fixed_cost_edit_entry), do: "fixed-cost-edit-title", else: nil}
        dialog_class="max-w-2xl rounded-2xl p-5 sm:p-6"
      >
        <section id="fixed-cost-edit-dialog">
          <div class="flex items-start justify-between gap-3">
            <h3 id="fixed-cost-edit-title" class="text-lg font-semibold text-base-content">
              Editar custo fixo
            </h3>
            <button
              type="button"
              phx-click="cancel_edit_fixed_cost"
              class="btn btn-ghost btn-sm border border-base-content/16"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <.form
            for={@fixed_cost_edit_form}
            id="fixed-cost-edit-form"
            phx-submit="save_fixed_cost"
            class="mt-4 space-y-3"
          >
            <input
              type="hidden"
              name="_id"
              value={if is_map(@fixed_cost_edit_entry), do: @fixed_cost_edit_entry.id, else: ""}
            />

            <.input field={@fixed_cost_edit_form[:name]} type="text" label="Nome" required />
            <.input
              field={@fixed_cost_edit_form[:amount_cents]}
              type="text"
              label="Valor"
              inputmode="numeric"
              data-money-mask="true"
              required
            />

            <div class="grid gap-3 sm:grid-cols-2">
              <.input
                field={@fixed_cost_edit_form[:billing_day]}
                type="number"
                label="Dia de cobrança"
                min="1"
                max="31"
                step="1"
                required
              />
              <.input
                field={@fixed_cost_edit_form[:starts_on]}
                type="text"
                label="Início (opcional)"
                placeholder="dd/mm/aaaa"
                inputmode="numeric"
                maxlength="10"
                pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
                data-date-picker="date"
              />
            </div>

            <.input
              field={@fixed_cost_edit_form[:active]}
              type="select"
              label="Status"
              options={[{"Ativo", "true"}, {"Inativo", "false"}]}
            />

            <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit_fixed_cost">
                Cancelar
              </button>
              <button type="submit" class="btn btn-primary btn-sm">Salvar custo fixo</button>
            </div>
          </.form>
        </section>
      </.app_modal>

      <.app_modal
        id="important-date-edit-modal"
        show={is_map(@important_date_edit_entry)}
        cancel_event="cancel_edit_important_date"
        aria_labelledby={
          if is_map(@important_date_edit_entry), do: "important-date-edit-title", else: nil
        }
        dialog_class="max-w-2xl rounded-2xl p-5 sm:p-6"
      >
        <section id="important-date-edit-dialog">
          <div class="flex items-start justify-between gap-3">
            <h3 id="important-date-edit-title" class="text-lg font-semibold text-base-content">
              Editar data importante
            </h3>
            <button
              type="button"
              phx-click="cancel_edit_important_date"
              class="btn btn-ghost btn-sm border border-base-content/16"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <.form
            for={@important_date_edit_form}
            id="important-date-edit-form"
            phx-submit="save_important_date"
            class="mt-4 space-y-3"
          >
            <input
              type="hidden"
              name="_id"
              value={
                if is_map(@important_date_edit_entry), do: @important_date_edit_entry.id, else: ""
              }
            />

            <.input field={@important_date_edit_form[:title]} type="text" label="Título" required />

            <div class="grid gap-3 sm:grid-cols-2">
              <.input
                field={@important_date_edit_form[:category]}
                type="select"
                label="Categoria"
                options={important_date_category_options()}
              />
              <.input
                field={@important_date_edit_form[:date]}
                type="text"
                label="Data"
                placeholder="dd/mm/aaaa"
                inputmode="numeric"
                maxlength="10"
                pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
                data-date-picker="date"
                required
              />
            </div>

            <.input field={@important_date_edit_form[:notes]} type="text" label="Observações" />

            <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="cancel_edit_important_date"
              >
                Cancelar
              </button>
              <button type="submit" class="btn btn-primary btn-sm">Salvar data</button>
            </div>
          </.form>
        </section>
      </.app_modal>

      <.destructive_confirm_modal
        id="fixed-cost-delete-confirmation-modal"
        show={is_map(@pending_fixed_cost_delete)}
        title="Excluir custo fixo?"
        message="Este custo fixo deixará de aparecer nos seus controles operacionais."
        severity="danger"
        impact_label="Impacto: remoção definitiva do custo"
        confirm_event="confirm_delete_fixed_cost"
        cancel_event="cancel_delete_fixed_cost"
        confirm_button_id="fixed-cost-delete-confirm-btn"
        cancel_button_id="fixed-cost-delete-cancel-btn"
        confirm_label="Sim, excluir custo"
      >
        <p :if={is_map(@pending_fixed_cost_delete)} class="font-medium text-base-content">
          {Map.get(@pending_fixed_cost_delete, :name, "Custo fixo")}
        </p>
      </.destructive_confirm_modal>

      <.destructive_confirm_modal
        id="important-date-delete-confirmation-modal"
        show={is_map(@pending_important_date_delete)}
        title="Excluir data importante?"
        message="Esta data deixará de gerar contexto para seu planejamento."
        severity="danger"
        impact_label="Impacto: remoção definitiva da data"
        confirm_event="confirm_delete_important_date"
        cancel_event="cancel_delete_important_date"
        confirm_button_id="important-date-delete-confirm-btn"
        cancel_button_id="important-date-delete-cancel-btn"
        confirm_label="Sim, excluir data"
      >
        <p :if={is_map(@pending_important_date_delete)} class="font-medium text-base-content">
          {Map.get(@pending_important_date_delete, :title, "Data importante")}
        </p>
      </.destructive_confirm_modal>
    </section>
    """
  end

  defp fixed_cost_status_badge_class(true),
    do: "badge badge-sm border-success/62 bg-success/24 text-success font-semibold"

  defp fixed_cost_status_badge_class(false),
    do: "badge badge-sm border-warning/62 bg-warning/24 text-warning-content font-semibold"

  defp fixed_cost_status_badge_class(_),
    do: "badge badge-sm border-base-content/34 bg-base-100 text-base-content/90 font-semibold"

  defp important_date_category_options do
    [
      {"Pessoal", "personal"},
      {"Financeiro", "finance"},
      {"Trabalho", "work"}
    ]
  end

  defp important_date_category_label(:personal), do: "Pessoal"
  defp important_date_category_label(:finance), do: "Financeiro"
  defp important_date_category_label(:work), do: "Trabalho"

  defp important_date_category_label(value) when is_binary(value) do
    case String.trim(value) do
      "personal" -> "Pessoal"
      "finance" -> "Financeiro"
      "work" -> "Trabalho"
      other -> other
    end
  end

  defp important_date_category_label(_value), do: "Categoria"

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
end
