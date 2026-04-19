defmodule Organizer.SharedFinance.FinanceEntryPropertyTest do
  use Organizer.DataCase, async: false
  use ExUnitProperties

  import Organizer.AccountsFixtures

  alias Organizer.Planning.FinanceEntry
  alias Organizer.Repo

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp valid_expense_attrs(expense_profile) do
    %{
      kind: :expense,
      expense_profile: expense_profile,
      payment_method: :debit,
      amount_cents: 1_000,
      category: "test-category",
      occurred_on: Date.utc_today()
    }
  end

  defp valid_income_attrs do
    %{
      kind: :income,
      amount_cents: 5_000,
      category: "salario",
      occurred_on: Date.utc_today()
    }
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 1: Round-trip de expense_profile
  # Validates: Requirements 1.7
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 1
  property "Property 1: round-trip de expense_profile — inserir e recuperar preserva o valor" do
    user = user_fixture()

    check all(
            profile <-
              StreamData.member_of([:fixed, :variable, :recurring_fixed, :recurring_variable]),
            min_runs: 100
          ) do
      attrs = valid_expense_attrs(profile)

      changeset = FinanceEntry.changeset(%FinanceEntry{user_id: user.id}, attrs)
      assert changeset.valid?, "changeset inválido para profile=#{inspect(profile)}"

      {:ok, inserted} = Repo.insert(changeset)
      retrieved = Repo.get!(FinanceEntry, inserted.id)

      assert retrieved.expense_profile == profile,
             "round-trip falhou: inserido #{inspect(profile)}, recuperado #{inspect(retrieved.expense_profile)}"

      Repo.delete!(retrieved)
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 2: Validação de expense_profile para despesas
  # Validates: Requirements 1.1, 1.2
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 2
  property "Property 2: changeset de despesa é válido sse expense_profile está nos quatro permitidos" do
    valid_profiles = MapSet.new([:fixed, :variable, :recurring_fixed, :recurring_variable])

    check all(
            profile <- StreamData.atom(:alphanumeric),
            min_runs: 200
          ) do
      attrs = %{
        kind: :expense,
        expense_profile: profile,
        payment_method: :debit,
        amount_cents: 1_000,
        category: "test-category",
        occurred_on: Date.utc_today()
      }

      changeset = FinanceEntry.changeset(%FinanceEntry{user_id: 1}, attrs)

      if MapSet.member?(valid_profiles, profile) do
        assert changeset.valid?,
               "esperado changeset válido para profile=#{inspect(profile)}, mas foi inválido"
      else
        refute changeset.valid?,
               "esperado changeset inválido para profile=#{inspect(profile)}, mas foi válido"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 3: Ignorar expense_profile para receitas
  # Validates: Requirements 1.3
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 3
  property "Property 3: para kind=:income, changeset é válido independente de expense_profile" do
    check all(
            profile <-
              StreamData.one_of([
                StreamData.constant(nil),
                StreamData.atom(:alphanumeric)
              ]),
            min_runs: 100
          ) do
      base_attrs = valid_income_attrs()

      attrs =
        if is_nil(profile) do
          base_attrs
        else
          Map.put(base_attrs, :expense_profile, profile)
        end

      changeset = FinanceEntry.changeset(%FinanceEntry{user_id: 1}, attrs)

      assert changeset.valid?,
             "esperado changeset válido para income com expense_profile=#{inspect(profile)}, mas foi inválido: #{inspect(changeset.errors)}"
    end
  end
end
