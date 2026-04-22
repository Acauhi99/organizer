defmodule OrganizerWeb.Components.QuickFinanceHero do
  use Phoenix.Component
  import OrganizerWeb.CoreComponents

  attr :quick_finance_form, :any, required: true
  attr :quick_finance_kind, :string, required: true
  attr :account_links, :list, default: []
  attr :current_user_id, :integer, default: 0

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
        <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-6">
          <.input
            field={@quick_finance_form[:kind]}
            type="select"
            label="Tipo"
            options={[{"Renda", "income"}, {"Gasto", "expense"}]}
          />

          <.input
            field={@quick_finance_form[:amount_cents]}
            id="quick-finance-amount"
            type="text"
            label="Valor"
            placeholder="Ex: 182,54"
            autocomplete="off"
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

        <section
          :if={@quick_finance_kind == "expense"}
          id="quick-finance-share-controls"
          class="rounded-xl border border-base-content/14 bg-base-100/45 p-3"
        >
          <.input
            field={@quick_finance_form[:share_with_link]}
            id="quick-finance-share-with-link"
            type="checkbox"
            label=" Compartilhar gasto com conta vinculada"
            disabled={Enum.empty?(@account_links)}
          />

          <.input
            field={@quick_finance_form[:shared_with_link_id]}
            id="quick-finance-share-link-id"
            type="select"
            label="Conta vinculada"
            options={share_link_options(@account_links, @current_user_id)}
            disabled={Enum.empty?(@account_links) || !share_enabled?(@quick_finance_form)}
          />

          <.input
            field={@quick_finance_form[:shared_split_mode]}
            id="quick-finance-share-mode"
            type="select"
            label="Forma de compartilhamento"
            options={[
              {"Padrão (por % de renda)", "income_ratio"},
              {"Manual (valor fixo)", "manual"}
            ]}
            disabled={Enum.empty?(@account_links) || !share_enabled?(@quick_finance_form)}
          />

          <div
            :if={share_enabled?(@quick_finance_form) && manual_share_mode?(@quick_finance_form)}
            id="quick-finance-manual-split"
            class="mt-2 grid gap-2 rounded-xl border border-info/20 bg-info/5 p-3 sm:grid-cols-2"
          >
            <.input
              field={@quick_finance_form[:shared_manual_mine_amount]}
              id="quick-finance-manual-mine-amount"
              type="text"
              label="Quanto você paga"
              placeholder="Ex: 200,00"
              autocomplete="off"
            />

            <.input
              field={@quick_finance_form[:shared_manual_theirs_amount]}
              id="quick-finance-manual-theirs-amount"
              type="text"
              label="Quanto a outra conta paga"
              readonly
            />

            <p class="text-xs text-base-content/68 sm:col-span-2">
              Ao informar o seu valor, o restante é preenchido automaticamente para a outra conta.
            </p>
          </div>

          <p :if={Enum.empty?(@account_links)} class="text-xs text-base-content/70">
            Você ainda não possui vínculo ativo. Crie um vínculo para compartilhar gastos.
          </p>
        </section>

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

  defp share_enabled?(quick_finance_form) do
    case quick_finance_form[:share_with_link] do
      %{value: value} -> truthy?(value)
      _ -> false
    end
  end

  defp manual_share_mode?(quick_finance_form) do
    case quick_finance_form[:shared_split_mode] do
      %{value: "manual"} -> true
      _ -> false
    end
  end

  defp truthy?(value) when is_boolean(value), do: value
  defp truthy?(value) when value in ["true", "on", "1"], do: true
  defp truthy?(_value), do: false

  defp share_link_options([], _current_user_id), do: [{"Sem vínculo ativo", ""}]

  defp share_link_options(account_links, current_user_id) do
    Enum.map(account_links, fn link ->
      {share_link_label(link, current_user_id), to_string(link.id)}
    end)
  end

  defp share_link_label(link, current_user_id) do
    partner_email =
      cond do
        current_user_id == link.user_a_id and is_map(link.user_b) ->
          Map.get(link.user_b, :email, "conta vinculada")

        current_user_id == link.user_b_id and is_map(link.user_a) ->
          Map.get(link.user_a, :email, "conta vinculada")

        true ->
          "conta vinculada"
      end

    "Vínculo ##{link.id} • #{partner_email}"
  end
end
