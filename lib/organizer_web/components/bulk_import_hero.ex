defmodule OrganizerWeb.Components.BulkImportHero do
  use Phoenix.Component
  import OrganizerWeb.CoreComponents

  attr :bulk_form, :any, required: true
  attr :bulk_payload_text, :string, required: true
  attr :bulk_result, :map, default: nil
  attr :bulk_preview, :map, default: nil
  attr :bulk_strict_mode, :boolean, required: true
  attr :last_bulk_import, :map, default: nil
  attr :bulk_recent_payloads, :list, required: true
  attr :bulk_template_favorites, :list, required: true
  attr :bulk_import_block_size, :integer, required: true
  attr :bulk_import_block_index, :integer, required: true
  attr :bulk_top_categories, :list, required: true
  attr :bulk_share_finances, :boolean, default: false
  attr :bulk_share_link_id, :integer, default: nil
  attr :account_links, :list, default: []
  attr :current_user_id, :integer, default: 0
  attr :onboarding_active, :boolean, required: true
  attr :onboarding_step, :integer, default: 1
  attr :has_any_imports, :boolean, required: true

  def bulk_import_hero(assigns) do
    ~H"""
    <section
      id="bulk-import-hero"
      class="bulk-import-hero"
      data-onboarding-target="bulk-import"
    >
      <div class="grid gap-2 mb-6">
        <h1 class="text-[1.75rem] md:text-[2.25rem] font-extrabold tracking-[-0.03em] text-base-content/98">
          Copy/Paste Studio
        </h1>
        <p class="text-[0.95rem] leading-[1.6] text-base-content/75">
          Cole o texto no formato
          <code class="font-mono text-[0.9rem] text-base-content/90">tipo: conteúdo</code>
          e importe.
        </p>
      </div>

      <.onboarding_hints
        :if={@onboarding_active && @onboarding_step <= 5}
        current_step={@onboarding_step}
      />

      <OrganizerWeb.DashboardLive.Components.BulkImportStudio.bulk_import_studio
        bulk_form={@bulk_form}
        bulk_payload_text={@bulk_payload_text}
        bulk_result={@bulk_result}
        bulk_preview={@bulk_preview}
        bulk_strict_mode={@bulk_strict_mode}
        last_bulk_import={@last_bulk_import}
        bulk_recent_payloads={@bulk_recent_payloads}
        bulk_template_favorites={@bulk_template_favorites}
        bulk_import_block_size={@bulk_import_block_size}
        bulk_import_block_index={@bulk_import_block_index}
        bulk_top_categories={@bulk_top_categories}
        bulk_share_finances={@bulk_share_finances}
        bulk_share_link_id={@bulk_share_link_id}
        account_links={@account_links}
        current_user_id={@current_user_id}
      />
    </section>
    """
  end

  attr :entity_type, :atom, required: true

  def empty_state_educational(assigns) do
    ~H"""
    <div
      id={"empty-state-#{@entity_type}"}
      class="grid gap-4 place-items-center text-center rounded-2xl p-8 bg-base-100/50"
      aria-live="polite"
      aria-atomic="true"
    >
      <div class="flex items-center justify-center w-12 h-12 rounded-full border border-info/35 bg-info/12 text-base-content/90">
        <.icon name={entity_icon(@entity_type)} class="size-6" />
      </div>
      <h3 class="text-base font-semibold text-base-content/90">{empty_state_title(@entity_type)}</h3>
      <p class="max-w-[26rem] text-sm leading-[1.6] text-base-content/70">
        {empty_state_description(@entity_type)}
      </p>

      <div class="grid gap-2 w-full max-w-[22rem] border border-base-content/15 rounded-xl p-3 bg-base-100/80">
        <p class="text-[0.7rem] font-bold uppercase tracking-[0.08em] text-base-content/60">
          Exemplo:
        </p>
        <code class="font-mono text-[0.82rem] leading-[1.5] text-base-content/90 bg-base-100/90 border border-base-content/12 rounded-lg p-3">
          {example_line(@entity_type)}
        </code>
      </div>

      <button
        id={"load-example-#{@entity_type}"}
        type="button"
        phx-click="load_example_to_bulk"
        phx-value-entity_type={@entity_type}
        class="btn btn-primary btn-sm"
      >
        <.icon name="hero-arrow-up-tray" class="size-4" /> Carregar no editor
      </button>
    </div>
    """
  end

  attr :current_step, :integer, required: true

  defp onboarding_hints(assigns) do
    ~H"""
    <div
      id="onboarding-hints"
      class="grid gap-3"
      data-step={@current_step}
    >
      <div class="flex items-start gap-3 border border-info/40 rounded-xl p-4 bg-base-100/50 backdrop-blur-[8px]">
        <div class="shrink-0 flex items-center justify-center w-10 h-10 rounded-lg bg-info/20 text-info/90">
          <.icon name={hint_icon(@current_step)} class="size-5" />
        </div>
        <div class="flex-1 grid gap-1">
          <strong class="text-sm font-semibold text-base-content/95">
            {hint_title(@current_step)}
          </strong>
          <p class="text-[0.8125rem] leading-[1.5] text-base-content/80">
            {hint_description(@current_step)}
          </p>
        </div>
      </div>

      <%!-- Visual indicators (arrows) pointing to relevant UI elements --%>
      <div
        :if={@current_step == 2}
        class="onboarding-arrow onboarding-arrow-down"
        data-target="bulk-payload-input"
      >
        <.icon name="hero-arrow-down" class="size-6" />
      </div>

      <div
        :if={@current_step == 3}
        class="onboarding-arrow onboarding-arrow-right"
        data-target="bulk-preview-btn"
      >
        <.icon name="hero-arrow-right" class="size-6" />
      </div>

      <div
        :if={@current_step == 5}
        class="onboarding-arrow onboarding-arrow-down"
        data-target="operations-panel"
      >
        <.icon name="hero-arrow-down" class="size-6" />
      </div>
    </div>
    """
  end

  # Helper functions for onboarding hints

  defp hint_icon(1), do: "hero-sparkles"
  defp hint_icon(2), do: "hero-document-text"
  defp hint_icon(3), do: "hero-eye"
  defp hint_icon(4), do: "hero-wrench-screwdriver"
  defp hint_icon(5), do: "hero-squares-2x2"
  defp hint_icon(_), do: "hero-light-bulb"

  defp hint_title(1), do: "Bem-vindo ao Copy/Paste Studio!"
  defp hint_title(2), do: "Digite suas linhas aqui"
  defp hint_title(3), do: "Revise antes de importar"
  defp hint_title(4), do: "Correções automáticas"
  defp hint_title(5), do: "Painéis de operação e analytics"
  defp hint_title(_), do: "Dica"

  defp hint_description(1) do
    "Este é o componente principal da plataforma. Cole linhas de texto e o sistema interpreta automaticamente."
  end

  defp hint_description(2) do
    "Use o formato 'tipo: conteúdo'. Exemplo: 'tarefa: Comprar mantimentos' ou 'finança: -50 Almoço'."
  end

  defp hint_description(3) do
    "Clique em 'Pré-visualizar' para revisar todas as linhas antes de importar. O sistema destaca erros automaticamente."
  end

  defp hint_description(4) do
    "O sistema oferece sugestões inteligentes para corrigir linhas com erro. Aceite as sugestões ou edite manualmente."
  end

  defp hint_description(5) do
    "Depois de importar, acompanhe tarefas e finanças nos painéis secundários para manter o ritmo diário."
  end

  defp hint_description(_) do
    "Cole suas linhas de texto no formato 'tipo: conteúdo' e clique em Pré-visualizar para revisar antes de importar."
  end

  # Helper functions for empty states

  defp entity_icon(:bulk_import), do: "hero-document-text"
  defp entity_icon(:tasks), do: "hero-check-circle"
  defp entity_icon(:finances), do: "hero-currency-dollar"

  defp empty_state_title(:bulk_import), do: "Comece a importar seus dados"
  defp empty_state_title(:tasks), do: "Nenhuma tarefa cadastrada"
  defp empty_state_title(:finances), do: "Nenhum lançamento financeiro"

  defp empty_state_description(:bulk_import) do
    "Use o Copy/Paste Studio para importar tarefas e lançamentos financeiros em lote. Cole linhas de texto no formato 'tipo: conteúdo' e o sistema interpreta automaticamente."
  end

  defp empty_state_description(:tasks) do
    "Comece importando tarefas usando o formato 'tarefa: título'. Você pode adicionar múltiplas tarefas de uma vez colando várias linhas."
  end

  defp empty_state_description(:finances) do
    "Importe lançamentos financeiros usando o formato 'finança: valor descrição'. Use valores negativos para despesas e positivos para receitas."
  end

  defp example_line(:bulk_import) do
    """
    tarefa: Revisar documentação
    finança: -50 Almoço
    """
  end

  defp example_line(:tasks) do
    """
    tarefa: Comprar mantimentos
    tarefa: Agendar consulta médica
    tarefa: Revisar relatório mensal
    """
  end

  defp example_line(:finances) do
    """
    finança: -120.50 Supermercado
    finança: 3500 Salário
    finança: -45 Transporte
    """
  end
end
