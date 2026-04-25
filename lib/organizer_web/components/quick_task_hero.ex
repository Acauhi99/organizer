defmodule OrganizerWeb.Components.QuickTaskHero do
  use Phoenix.Component
  import OrganizerWeb.CoreComponents

  attr :quick_task_form, :any, required: true

  def quick_task_hero(assigns) do
    ~H"""
    <section
      id="quick-task-hero"
      class="surface-card order-5 rounded-2xl p-5 scroll-mt-20"
      data-onboarding-target="quick-task"
    >
      <header class="mb-4 space-y-1">
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/62">
          Lançamento rápido
        </p>
        <h2 class="text-2xl font-black tracking-[-0.02em] text-base-content">
          Registrar tarefas por formulário
        </h2>
        <p class="text-sm leading-6 text-base-content/75">
          Cadastre tarefas com prioridade, prazo e status. Depois, detalhe com checklist dinâmica na operação diária.
        </p>
      </header>

      <.form
        for={@quick_task_form}
        id="quick-task-form"
        phx-change="quick_task_validate"
        phx-submit="create_quick_task"
        class="space-y-4"
      >
        <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <.input
            field={@quick_task_form[:title]}
            id="quick-task-title"
            type="text"
            label="Título"
            placeholder="Ex: Revisar orçamento do mês"
            required
          />

          <.input
            field={@quick_task_form[:priority]}
            type="select"
            label="Prioridade"
            options={[{"Baixa", "low"}, {"Média", "medium"}, {"Alta", "high"}]}
          />

          <.input
            field={@quick_task_form[:status]}
            type="select"
            label="Status"
            options={[{"A fazer", "todo"}, {"Em andamento", "in_progress"}, {"Concluída", "done"}]}
          />

          <.input
            field={@quick_task_form[:due_on]}
            type="text"
            label="Prazo"
            placeholder="dd/mm/aaaa"
            inputmode="numeric"
            maxlength="10"
            pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
          />
        </div>

        <.input
          field={@quick_task_form[:notes]}
          id="quick-task-notes"
          type="textarea"
          label="Notas"
          placeholder="Opcional"
          rows="4"
        />

        <.button type="submit" variant="soft" class="w-full sm:w-auto">
          Registrar tarefa
        </.button>
      </.form>
    </section>
    """
  end
end
