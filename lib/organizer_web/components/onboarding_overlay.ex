defmodule OrganizerWeb.Components.OnboardingOverlay do
  use Phoenix.Component
  import OrganizerWeb.CoreComponents

  attr :active, :boolean, required: true
  attr :current_step, :integer, required: true
  attr :total_steps, :integer, default: 5
  attr :can_skip, :boolean, default: true

  def onboarding_overlay(assigns) do
    ~H"""
    <div
      :if={@active}
      id="onboarding-overlay"
      class="fixed inset-0 z-[9999] flex items-center justify-center p-4"
      role="dialog"
      aria-labelledby="onboarding-title"
      aria-describedby="onboarding-description"
      aria-modal="true"
    >
      <div class="absolute inset-0 bg-[rgba(8,16,28,0.85)] backdrop-blur-[4px]"></div>
      <div class="onboarding-spotlight" data-target={spotlight_target(@current_step)}></div>
      <div class="relative z-[10000] max-w-[32rem] w-full border border-info/40 rounded-[1.25rem] p-7 bg-base-100/95 shadow-[0_30px_80px_rgba(3,12,26,0.6)] backdrop-blur-[12px]">
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
                "w-6 bg-gradient-to-r from-cyan-400 to-emerald-400 shadow-[0_0_12px_rgba(34,211,238,0.6)]",
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
        "O Organizer permite que você organize sua vida através de importação em lote. Cole linhas de texto e o sistema interpreta automaticamente, criando tarefas, lançamentos financeiros e metas.",
      example: "tarefa: Revisar documentação\nfinança: -50 Almoço\nmeta: Ler 12 livros este ano"
    }
  end

  defp step_content(2) do
    %{
      title: "Formato de Importação",
      description:
        "Cada linha segue o formato 'tipo: conteúdo'. O sistema reconhece automaticamente o tipo (tarefa, finança ou meta) e extrai as informações relevantes.",
      example:
        "tarefa: Comprar mantimentos\nfinança: -120.50 Supermercado\nmeta: Economizar R$ 5000"
    }
  end

  defp step_content(3) do
    %{
      title: "Sistema de Pré-visualização",
      description:
        "Antes de importar, você pode revisar todas as linhas interpretadas. O sistema destaca erros e sugere correções automaticamente.",
      example: nil
    }
  end

  defp step_content(4) do
    %{
      title: "Correções Automáticas",
      description:
        "O sistema oferece sugestões inteligentes para corrigir linhas com erro. Você pode aceitar as sugestões ou editar manualmente.",
      example: nil
    }
  end

  defp step_content(5) do
    %{
      title: "Painéis Secundários",
      description:
        "Use os painéis de Operações e Analytics para visualizar e gerenciar suas tarefas, finanças e metas. Você pode ocultar ou mostrar esses painéis conforme necessário.",
      example: nil
    }
  end

  defp spotlight_target(1), do: "#bulk-import-hero"
  defp spotlight_target(2), do: "#bulk-payload-input"
  defp spotlight_target(3), do: "#bulk-preview-btn"
  defp spotlight_target(4), do: "#bulk-import-hero"
  defp spotlight_target(5), do: "#panel-visibility-controls"
end
