defmodule Organizer.SharedFinance.SplitCalculatorPropertyTest do
  use Organizer.DataCase, async: false
  use ExUnitProperties

  import Organizer.AccountsFixtures

  alias Organizer.Planning.FinanceEntry
  alias Organizer.Repo
  alias Organizer.SharedFinance.SplitCalculator

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 8: SplitRatio é proporcional à renda e soma 1.0
  # Validates: Requirements 3.2
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 8
  property "Property 8: ratio_a + ratio_b == 1.0 e ratio_a é proporcional à renda" do
    check all(
            income_a <- StreamData.positive_integer(),
            income_b <- StreamData.positive_integer(),
            min_runs: 100
          ) do
      {ratio_a, ratio_b} = SplitCalculator.calculate_split_ratio(income_a, income_b)

      assert abs(ratio_a + ratio_b - 1.0) < 1.0e-10,
             "ratio_a + ratio_b deve ser 1.0, mas foi #{ratio_a + ratio_b}"

      expected_ratio_a = income_a / (income_a + income_b)

      assert abs(ratio_a - expected_ratio_a) < 1.0e-10,
             "ratio_a deve ser #{expected_ratio_a}, mas foi #{ratio_a}"
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 9: Sem fallback 50/50 quando renda combinada é zero
  # Validates: Requirements 3.4
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 9
  test "Property 9: calculate_split_ratio(0, 0) retorna {1.0, 0.0}" do
    assert SplitCalculator.calculate_split_ratio(0, 0) == {1.0, 0.0}
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 10: ReferenceIncome é soma de receitas do mês
  # Validates: Requirements 3.3
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 10
  property "Property 10: calculate_reference_income retorna soma exata das receitas do mês" do
    today = Date.utc_today()
    month = today.month
    year = today.year

    check all(
            income_amounts <-
              StreamData.list_of(StreamData.integer(1..100_000), min_length: 0, max_length: 5),
            min_runs: 50
          ) do
      user = user_fixture()

      # Insert FinanceEntry income entries in current month
      Enum.each(income_amounts, fn amount ->
        %FinanceEntry{}
        |> FinanceEntry.changeset(%{
          kind: :income,
          amount_cents: amount,
          category: "receita-teste",
          occurred_on: today
        })
        |> Ecto.Changeset.put_assoc(:user, user)
        |> Repo.insert!()
      end)

      expected_sum = Enum.sum(income_amounts)
      result = SplitCalculator.calculate_reference_income(user.id, month, year)

      assert result == expected_sum,
             "esperado #{expected_sum}, mas calculate_reference_income retornou #{result}"
    end
  end

  test "calculate_reference_income ignora fixed costs e considera apenas receitas" do
    today = Date.utc_today()
    user = user_fixture()

    %Organizer.Planning.FixedCost{}
    |> Organizer.Planning.FixedCost.changeset(%{
      name: "aluguel",
      amount_cents: 500_000,
      billing_day: 1,
      starts_on: today,
      active: true
    })
    |> Ecto.Changeset.put_assoc(:user, user)
    |> Repo.insert!()

    %FinanceEntry{}
    |> FinanceEntry.changeset(%{
      kind: :income,
      amount_cents: 200_000,
      category: "salario",
      occurred_on: today
    })
    |> Ecto.Changeset.put_assoc(:user, user)
    |> Repo.insert!()

    assert SplitCalculator.calculate_reference_income(user.id, today.month, today.year) == 200_000
  end

  test "calculate_reference_income projeta renda fixa para meses futuros" do
    user = user_fixture()

    %FinanceEntry{}
    |> FinanceEntry.changeset(%{
      kind: :income,
      expense_profile: :fixed,
      amount_cents: 300_000,
      category: "salario-fixo",
      occurred_on: ~D[2026-01-05]
    })
    |> Ecto.Changeset.put_assoc(:user, user)
    |> Repo.insert!()

    assert SplitCalculator.calculate_reference_income(user.id, 4, 2026) == 300_000
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 11: Conservação de valor nos splits
  # Validates: Requirements 4.7
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 11
  property "Property 11: amount_a + amount_b == amount_cents para qualquer split" do
    check all(
            amount_cents <- StreamData.positive_integer(),
            ratio_a <- StreamData.float(min: 0.0, max: 1.0),
            min_runs: 100
          ) do
      {amount_a, amount_b} = SplitCalculator.split_amount(amount_cents, ratio_a)

      assert amount_a + amount_b == amount_cents,
             "conservação de valor falhou: #{amount_a} + #{amount_b} != #{amount_cents} (ratio_a=#{ratio_a})"
    end
  end
end
