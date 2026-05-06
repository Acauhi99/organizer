defmodule OrganizerWeb.Components.OnboardingOverlay do
  use Phoenix.Component
  import OrganizerWeb.CoreComponents

  attr :active, :boolean, required: true
  attr :current_step, :integer, required: true
  attr :total_steps, :integer, default: 6
  attr :can_skip, :boolean, default: true

  def onboarding_overlay(assigns) do
    ~H"""
    <.app_modal
      id="onboarding-overlay"
      show={@active}
      close_on_escape={false}
      close_on_backdrop={false}
      z_index_class="z-[9999]"
      container_class="items-center p-4 sm:p-4"
      backdrop_class="bg-slate-950/72 backdrop-blur-[6px]"
      dialog_class="max-w-[32rem] rounded-[1.25rem] border border-cyan-300/30 bg-slate-900/95 p-7 shadow-[0_28px_74px_rgba(2,6,23,0.78),0_0_0_1px_rgba(34,211,238,0.16)] backdrop-blur-[12px]"
      aria_labelledby="onboarding-title"
      aria_describedby="onboarding-description"
      phx-hook="OnboardingOverlay"
    >
      <:overlay>
        <div class="onboarding-spotlight" data-target={spotlight_target(@current_step)}></div>
      </:overlay>

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
    </.app_modal>
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
        class="text-[1.35rem] font-bold tracking-[-0.02em] text-slate-50"
      >
        {@content.title}
      </h2>
      <p id="onboarding-description" class="text-[0.95rem] leading-[1.6] text-slate-300">
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
                "w-6 bg-gradient-to-r from-cyan-300 to-emerald-300 shadow-[0_0_16px_rgba(45,212,191,0.48)]",
              else: "bg-slate-500/60"
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
    <div class={controls_container_classes()}>
      <button
        :if={@current > 1}
        id="onboarding-prev-btn"
        type="button"
        phx-click="prev_onboarding_step"
        class={secondary_button_classes()}
      >
        <.icon name="hero-arrow-left" class="size-4" /> Anterior
      </button>

      <button
        :if={@can_skip}
        id="onboarding-skip-btn"
        type="button"
        phx-click="skip_onboarding"
        class={skip_button_classes()}
      >
        Pular
      </button>

      <button
        id="onboarding-next-btn"
        type="button"
        phx-click={if @current < @total, do: "next_onboarding_step", else: "complete_onboarding"}
        class={primary_button_classes()}
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
        "O Organizer permite organizar finanças com formulários objetivos e fluxo guiado.",
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
      description: "Edite lançamentos direto na lista quando precisar ajustar detalhes.",
      example: nil
    }
  end

  defp step_content(5) do
    %{
      title: "Áreas de operação",
      description:
        "Use os painéis de métricas e operação em Finanças para agir sem misturar contextos.",
      example: nil
    }
  end

  defp step_content(6) do
    %{
      title: "Conecte outra conta",
      description:
        "Crie um compartilhamento com outra pessoa para compartilhar lançamentos e acompanhar acertos de forma transparente. Você encontra essa área logo abaixo do cabeçalho.",
      example: nil
    }
  end

  defp spotlight_target(1), do: "#quick-finance-hero"
  defp spotlight_target(2), do: "#quick-finance-form"
  defp spotlight_target(3), do: "#finance-operations-panel"
  defp spotlight_target(4), do: "#finance-operations-panel"
  defp spotlight_target(5), do: "#finance-metrics-panel"
  defp spotlight_target(6), do: "a[href='/account-links']"

  defp controls_container_classes do
    "mt-7 flex flex-wrap items-center gap-3 border-t border-cyan-300/20 pt-5"
  end

  defp button_base_classes do
    "inline-flex h-9 items-center justify-center gap-2 rounded-lg border px-3 text-sm font-semibold transition duration-200 ease-out focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 disabled:pointer-events-none disabled:opacity-60"
  end

  defp secondary_button_classes do
    [
      button_base_classes(),
      "border-cyan-300/30 bg-slate-800/70 text-slate-100 hover:border-cyan-200/60 hover:bg-slate-700/80 focus-visible:outline-cyan-300"
    ]
  end

  defp skip_button_classes do
    [
      button_base_classes(),
      "border-transparent bg-transparent text-slate-300 hover:bg-slate-800/70 hover:text-cyan-200 focus-visible:outline-cyan-300"
    ]
  end

  defp primary_button_classes do
    [
      button_base_classes(),
      "ml-auto border-cyan-200/70 bg-gradient-to-r from-cyan-300 to-emerald-300 text-slate-950 shadow-[0_12px_26px_rgba(45,212,191,0.3)] hover:from-cyan-200 hover:to-emerald-200 focus-visible:outline-cyan-100"
    ]
  end
end
