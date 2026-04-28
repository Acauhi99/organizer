defmodule OrganizerWeb.Components.QuickFinanceHero do
  use Phoenix.Component
  import OrganizerWeb.CoreComponents

  attr :quick_finance_form, :any, required: true
  attr :quick_finance_kind, :string, required: true
  attr :quick_finance_preset, :string, default: nil
  attr :account_links, :list, default: []
  attr :current_user_id, :integer, default: 0
  attr :category_suggestions, :map, default: %{}

  def quick_finance_hero(assigns) do
    ~H"""
    <section
      id="quick-finance-hero"
      class="surface-card rounded-2xl p-5 scroll-mt-20"
      data-onboarding-target="quick-finance"
    >
      <header class="mb-4 space-y-1">
        <h2 class="text-2xl font-black tracking-[-0.02em] text-base-content">
          Lançamento rápido
        </h2>
        <p class="text-sm leading-6 text-base-content/75">
          Registrar renda e gastos por formulário
        </p>
      </header>

      <div class="mb-4 flex flex-wrap gap-2">
        <button
          id="quick-preset-income-salary"
          type="button"
          phx-click="quick_finance_preset"
          phx-value-preset="income_salary"
          class={preset_class(@quick_finance_preset == "income_salary")}
        >
          Renda: salário
        </button>
        <button
          id="quick-preset-income-extra"
          type="button"
          phx-click="quick_finance_preset"
          phx-value-preset="income_extra"
          class={preset_class(@quick_finance_preset == "income_extra")}
        >
          Renda: extra
        </button>
        <button
          id="quick-preset-expense-fixed"
          type="button"
          phx-click="quick_finance_preset"
          phx-value-preset="expense_fixed"
          class={preset_class(@quick_finance_preset == "expense_fixed")}
        >
          Gasto fixo
        </button>
        <button
          id="quick-preset-expense-variable"
          type="button"
          phx-click="quick_finance_preset"
          phx-value-preset="expense_variable"
          class={preset_class(@quick_finance_preset == "expense_variable")}
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
            type="text"
            label="Data"
            placeholder="dd/mm/aaaa"
            inputmode="numeric"
            maxlength="10"
            pattern="^[0-9]{2}/[0-9]{2}/[0-9]{4}$"
          />

          <.input
            field={@quick_finance_form[:category]}
            type="text"
            label="Categoria"
            placeholder="Ex: Alimentação"
            list={category_datalist_id(@quick_finance_kind)}
          />

          <.input
            field={@quick_finance_form[:expense_profile]}
            type="select"
            label={entry_profile_label(@quick_finance_kind)}
            options={entry_profile_options(@quick_finance_kind)}
          />

          <.input
            :if={@quick_finance_kind == "expense"}
            field={@quick_finance_form[:payment_method]}
            type="select"
            label="Pagamento"
            options={[{"Débito", "debit"}, {"Crédito", "credit"}]}
          />

          <.input
            :if={@quick_finance_kind == "expense" && payment_credit?(@quick_finance_form)}
            field={@quick_finance_form[:installment_number]}
            id="quick-finance-installment-number"
            type="number"
            label="Parcela atual"
            min="1"
            max="120"
            step="1"
            required
          />

          <.input
            :if={@quick_finance_kind == "expense" && payment_credit?(@quick_finance_form)}
            field={@quick_finance_form[:installments_count]}
            id="quick-finance-installments-count"
            type="number"
            label="Total de parcelas"
            min="1"
            max="120"
            step="1"
            required
          />
        </div>

        <p
          :if={@quick_finance_kind == "expense"}
          id="quick-finance-fixed-guidance"
          class="text-xs text-base-content/70"
        >
          Lançamentos com natureza fixa permanecem ativos no sistema até você cancelar ou excluir.
        </p>

        <datalist id={category_datalist_id(@quick_finance_kind)}>
          <option
            :for={category <- category_options(@quick_finance_kind, @category_suggestions)}
            value={category}
          >
            {category}
          </option>
        </datalist>

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
            Você ainda não possui compartilhamento ativo. Crie um compartilhamento para compartilhar gastos.
          </p>
        </section>

        <.button type="submit" variant="primary" class="w-full sm:w-auto">
          Registrar lançamento
        </.button>
      </.form>
    </section>
    """
  end

  defp category_options("income", suggestions) do
    default_income_categories()
    |> merge_with_suggestions(Map.get(suggestions, :income, []))
  end

  defp category_options(_kind, suggestions) do
    default_expense_categories()
    |> merge_with_suggestions(Map.get(suggestions, :expense, []))
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

  defp payment_credit?(quick_finance_form) do
    case quick_finance_form[:payment_method] do
      %{value: "credit"} -> true
      _ -> false
    end
  end

  defp category_datalist_id("income"), do: "quick-finance-income-categories"
  defp category_datalist_id(_kind), do: "quick-finance-expense-categories"

  defp default_income_categories do
    ["Salário", "Renda extra", "Freelance", "Reembolso", "Dividendos"]
  end

  defp default_expense_categories do
    ["Alimentação", "Moradia", "Transporte", "Saúde", "Lazer", "Educação", "Assinaturas"]
  end

  defp merge_with_suggestions(defaults, suggestions) when is_list(suggestions) do
    (defaults ++ suggestions)
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&String.downcase/1)
  end

  defp share_link_options([], _current_user_id), do: [{"Sem compartilhamento ativo", ""}]

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

    "Compartilhamento ##{link.id} • #{partner_email}"
  end

  defp entry_profile_label("income"), do: "Natureza da renda"
  defp entry_profile_label(_kind), do: "Natureza da despesa"

  defp entry_profile_options("income") do
    [
      {"Variável", "variable"},
      {"Fixa (repete mensalmente)", "fixed"}
    ]
  end

  defp entry_profile_options(_kind) do
    [
      {"Fixa", "fixed"},
      {"Variável", "variable"},
      {"Recorrente fixa", "recurring_fixed"},
      {"Recorrente variável", "recurring_variable"}
    ]
  end
end
