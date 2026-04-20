defmodule OrganizerWeb.Components.OnboardingOverlay do
  use Phoenix.Component
  import OrganizerWeb.CoreComponents

  attr :active, :boolean, required: true
  attr :current_step, :integer, required: true
  attr :total_steps, :integer, default: 6
  attr :can_skip, :boolean, default: true

  def onboarding_overlay(assigns) do
    ~H"""
    <div
      :if={@active}
      id="onboarding-overlay"
      class="fixed inset-0 z-[9999] flex items-center justify-center p-4"
      phx-hook="OnboardingOverlay"
      role="dialog"
      aria-labelledby="onboarding-title"
      aria-describedby="onboarding-description"
      aria-modal="true"
    >
      <div class="absolute inset-0 bg-[rgba(113,104,88,0.44)] backdrop-blur-[4px]"></div>
      <div class="onboarding-spotlight" data-target={spotlight_target(@current_step)}></div>
      <div class="relative z-[10000] max-w-[32rem] w-full border border-info/40 rounded-[1.25rem] p-7 bg-base-100/95 shadow-[0_26px_64px_rgba(106,121,142,0.3)] backdrop-blur-[12px]">
        <.onboarding_step
          step={@current_step}
          total={@total_steps}
          content={step_content(@current_step)}
        />
        <.onboarding_controls
          current={@current_step}
          total={@total_steps}
          can_skip={@can_skip}
        />
      </div>
    </div>
    """
  end

  attr :step, :integer, required: true
  attr :total, :integer, required: true
  attr :content, :map, required: true

  defp onboarding_step(assigns) do
    ~H"""
    <div class="grid gap-4" data-onboarding-step={@step}>
      <h2
        id="onboarding-title"
        class="text-[1.35rem] font-bold tracking-[-0.02em] text-base-content/98"
      >
        {@content.title}
      </h2>
      <p id="onboarding-description" class="text-[0.95rem] leading-[1.6] text-base-content/85">
        {@content.description}
      </p>

      <div :if={@content[:example]} class="empty-state-example">
        <p class="empty-state-example-label">Exemplo:</p>
        <code class="empty-state-example-code">{@content.example}</code>
      </div>

      <div class="flex gap-2 mt-6">
        <div
          :for={step_num <- 1..@total}
          class={[
            "w-2 h-2 rounded-full transition-all duration-200",
            if(step_num == @step,
              do:
                "w-6 bg-gradient-to-r from-info to-success shadow-[0_0_12px_rgba(124,170,196,0.42)]",
              else: "bg-base-content/30"
            )
          ]}
        >
        </div>
      </div>
    </div>
    """
  end

  attr :current, :integer, required: true
  attr :total, :integer, required: true
  attr :can_skip, :boolean, required: true

  defp onboarding_controls(assigns) do
    ~H"""
    <div class="flex gap-3 mt-6">
      <button
        :if={@current > 1}
        id="onboarding-prev-btn"
        type="button"
        phx-click="prev_onboarding_step"
        class="btn btn-soft btn-sm"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Anterior
      </button>

      <button
        :if={@can_skip}
        id="onboarding-skip-btn"
        type="button"
        phx-click="skip_onboarding"
        class="btn btn-soft btn-sm"
      >
        Pular
      </button>

      <button
        id="onboarding-next-btn"
        type="button"
        phx-click={if @current < @total, do: "next_onboarding_step", else: "complete_onboarding"}
        class="btn btn-primary btn-sm"
      >
        {if @current < @total, do: "Próximo", else: "Concluir"}
        <.icon name="hero-arrow-right" class="size-4" />
      </button>
    </div>
    """
  end

  # Private helper functions

  defp step_content(1) do
    %{
      title: "Bem-vindo ao Organizer!",
      description:
        "O Organizer permite organizar tarefas e finanças com formulários objetivos e fluxo guiado.",
      example: "Tipo: Gasto\nValor: 12990\nCategoria: Alimentação\nData: hoje"
    }
  end

  defp step_content(2) do
    %{
      title: "Lançamento Rápido",
      description:
        "Use o card de lançamento rápido para registrar renda e gastos com presets e campos claros.",
      example: "Preset: Gasto variável\nCategoria: Alimentação\nPagamento: Débito"
    }
  end

  defp step_content(3) do
    %{
      title: "Filtros Operacionais",
      description:
        "No painel de Operação diária, filtre por período, tipo e categoria para focar no que importa.",
      example: nil
    }
  end

  defp step_content(4) do
    %{
      title: "Edição Direta",
      description:
        "Edite tarefas e lançamentos direto na lista quando precisar ajustar detalhes.",
      example: nil
    }
  end

  defp step_content(5) do
    %{
      title: "Painéis Secundários",
      description:
        "Use os painéis de Operações e Analytics para visualizar e gerenciar suas tarefas e finanças. Você pode ocultar ou mostrar esses painéis conforme necessário.",
      example: nil
    }
  end

  defp step_content(6) do
    %{
      title: "Conecte outra conta",
      description:
        "Crie um vínculo com outra pessoa para compartilhar lançamentos e acompanhar acertos de forma transparente. Você encontra essa área logo abaixo do cabeçalho.",
      example: nil
    }
  end

  defp spotlight_target(1), do: "#quick-finance-hero"
  defp spotlight_target(2), do: "#quick-finance-form"
  defp spotlight_target(3), do: "#operations-panel"
  defp spotlight_target(4), do: "#operations-panel"
  defp spotlight_target(5), do: "#operations-panel"
  defp spotlight_target(6), do: "#account-link-panel"
end
