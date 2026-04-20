defmodule OrganizerWeb.Components.QuickFinanceHero do
  use Phoenix.Component
  import OrganizerWeb.CoreComponents

  attr :quick_finance_form, :any, required: true
  attr :quick_finance_kind, :string, required: true

  def quick_finance_hero(assigns) do
    ~H"""
    <section
      id="quick-finance-hero"
      class="surface-card order-4 rounded-2xl p-5 scroll-mt-20"
      data-onboarding-target="quick-finance"
    >
      <header class="mb-4 space-y-1">
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/62">
          Lançamento rápido
        </p>
        <h2 class="text-2xl font-black tracking-[-0.02em] text-base-content">
          Registrar renda e gastos por formulário
        </h2>
        <p class="text-sm leading-6 text-base-content/75">
          Use presets para acelerar o cadastro e mantenha os dados financeiros organizados sem depender de chat.
        </p>
      </header>

      <div class="mb-4 flex flex-wrap gap-2">
        <button
          id="quick-preset-income-salary"
          type="button"
          phx-click="quick_finance_preset"
          phx-value-preset="income_salary"
          class={preset_class(@quick_finance_kind == "income")}
        >
          Renda: salário
        </button>
        <button
          id="quick-preset-income-extra"
          type="button"
          phx-click="quick_finance_preset"
          phx-value-preset="income_extra"
          class={preset_class(@quick_finance_kind == "income")}
        >
          Renda: extra
        </button>
        <button
          id="quick-preset-expense-fixed"
          type="button"
          phx-click="quick_finance_preset"
          phx-value-preset="expense_fixed"
          class={preset_class(@quick_finance_kind == "expense")}
        >
          Gasto fixo
        </button>
        <button
          id="quick-preset-expense-variable"
          type="button"
          phx-click="quick_finance_preset"
          phx-value-preset="expense_variable"
          class={preset_class(@quick_finance_kind == "expense")}
        >
          Gasto variável
        </button>
      </div>

      <.form
        for={@quick_finance_form}
        id="quick-finance-form"
        phx-change="quick_finance_validate"
        phx-submit="create_quick_finance"
        class="space-y-4"
      >
        <div class="grid gap-3 sm:grid-cols-3 lg:grid-cols-6">
          <.input
            field={@quick_finance_form[:kind]}
            type="select"
            label="Tipo"
            options={[{"Renda", "income"}, {"Gasto", "expense"}]}
          />

          <.input
            field={@quick_finance_form[:amount_cents]}
            id="quick-finance-amount"
            type="number"
            label="Valor (centavos)"
            placeholder="Ex: 12990"
            min="1"
            required
          />

          <.input
            field={@quick_finance_form[:occurred_on]}
            type="date"
            label="Data"
          />

          <.input
            field={@quick_finance_form[:category]}
            type="select"
            label="Categoria"
            options={category_options(@quick_finance_kind)}
          />

          <.input
            :if={@quick_finance_kind == "expense"}
            field={@quick_finance_form[:expense_profile]}
            type="select"
            label="Natureza"
            options={[
              {"Fixa", "fixed"},
              {"Variável", "variable"},
              {"Recorrente fixa", "recurring_fixed"},
              {"Recorrente variável", "recurring_variable"}
            ]}
          />

          <.input
            :if={@quick_finance_kind == "expense"}
            field={@quick_finance_form[:payment_method]}
            type="select"
            label="Pagamento"
            options={[{"Débito", "debit"}, {"Crédito", "credit"}]}
          />
        </div>

        <.input
          field={@quick_finance_form[:description]}
          type="text"
          label="Descrição"
          placeholder="Opcional"
        />

        <.button type="submit" variant="primary" class="w-full sm:w-auto">
          Registrar lançamento
        </.button>
      </.form>
    </section>
    """
  end

  defp category_options("income") do
    [
      {"Salário", "Salário"},
      {"Renda extra", "Renda extra"},
      {"Freelance", "Freelance"},
      {"Reembolso", "Reembolso"},
      {"Dividendos", "Dividendos"}
    ]
  end

  defp category_options(_kind) do
    [
      {"Alimentação", "Alimentação"},
      {"Moradia", "Moradia"},
      {"Transporte", "Transporte"},
      {"Saúde", "Saúde"},
      {"Lazer", "Lazer"},
      {"Educação", "Educação"},
      {"Assinaturas", "Assinaturas"}
    ]
  end

  defp preset_class(active?) do
    [
      "btn btn-sm transition",
      active? && "btn-primary",
      not active? && "btn-soft"
    ]
  end
end
