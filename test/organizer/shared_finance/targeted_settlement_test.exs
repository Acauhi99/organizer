defmodule Organizer.SharedFinance.TargetedSettlementTest do
  use Organizer.DataCase, async: false

  import Organizer.AccountsFixtures

  alias Organizer.Accounts.Scope
  alias Organizer.Planning
  alias Organizer.SharedFinance

  defp make_scope(user), do: Scope.for_user(user)

  defp create_link(user_a, user_b) do
    scope_a = make_scope(user_a)
    scope_b = make_scope(user_b)
    {:ok, invite} = SharedFinance.create_invite(scope_a)
    {:ok, link} = SharedFinance.accept_invite(scope_b, invite.token)
    link
  end

  defp create_income(scope, amount_cents, occurred_on \\ Date.utc_today()) do
    {:ok, _entry} =
      Planning.create_finance_entry(scope, %{
        "description" => "Renda",
        "amount_cents" => amount_cents,
        "kind" => "income",
        "category" => "Salário",
        "occurred_on" => Date.to_iso8601(occurred_on)
      })

    :ok
  end

  defp create_shared_expense(scope, link_id, amount_cents, occurred_on \\ Date.utc_today()) do
    {:ok, entry} =
      Planning.create_finance_entry(scope, %{
        "description" => "Despesa compartilhada",
        "amount_cents" => amount_cents,
        "kind" => "expense",
        "category" => "Moradia",
        "occurred_on" => Date.to_iso8601(occurred_on)
      })

    {:ok, _updated_entry} = SharedFinance.share_finance_entry(scope, entry.id, link_id)
    :ok
  end

  describe "create_settlement_record_for_debt/4" do
    test "allocates payment only to the selected debt" do
      user_a = user_fixture()
      user_b = user_fixture()
      scope_a = make_scope(user_a)
      scope_b = make_scope(user_b)
      link = create_link(user_a, user_b)

      create_income(scope_a, 20_000)
      create_income(scope_b, 20_000)
      create_shared_expense(scope_b, link.id, 10_000)

      {:ok, [debt_before]} = SharedFinance.list_shared_entry_debts(scope_a, link.id)

      {:ok, cycle} =
        SharedFinance.get_or_create_settlement_cycle(scope_a, link.id, Date.utc_today())

      assert {:ok, _record} =
               SharedFinance.create_settlement_record_for_debt(
                 scope_a,
                 cycle.id,
                 debt_before.id,
                 %{
                   amount_cents: 1_250,
                   method: :pix,
                   transferred_at: DateTime.utc_now() |> DateTime.truncate(:second)
                 }
               )

      {:ok, [debt_after]} = SharedFinance.list_shared_entry_debts(scope_a, link.id)
      assert debt_after.outstanding_amount_cents == debt_before.outstanding_amount_cents - 1_250

      {:ok, records} = SharedFinance.list_settlement_records_with_allocations(scope_a, link.id)
      record = List.last(records)
      assert Enum.count(record.allocations) == 1
      [allocation] = record.allocations
      assert allocation.shared_entry_debt_id == debt_before.id
      assert allocation.amount_cents == 1_250
    end

    test "returns validation when payment exceeds selected debt outstanding amount" do
      user_a = user_fixture()
      user_b = user_fixture()
      scope_a = make_scope(user_a)
      scope_b = make_scope(user_b)
      link = create_link(user_a, user_b)

      create_income(scope_a, 10_000)
      create_income(scope_b, 10_000)
      create_shared_expense(scope_b, link.id, 2_000)

      {:ok, [debt]} = SharedFinance.list_shared_entry_debts(scope_a, link.id)

      {:ok, cycle} =
        SharedFinance.get_or_create_settlement_cycle(scope_a, link.id, Date.utc_today())

      assert {:error, {:validation, %{amount_cents: _}}} =
               SharedFinance.create_settlement_record_for_debt(scope_a, cycle.id, debt.id, %{
                 amount_cents: debt.outstanding_amount_cents + 1,
                 method: :pix,
                 transferred_at: DateTime.utc_now() |> DateTime.truncate(:second)
               })
    end

    test "returns not_found when current user is not the debtor of the selected debt" do
      user_a = user_fixture()
      user_b = user_fixture()
      scope_a = make_scope(user_a)
      scope_b = make_scope(user_b)
      link = create_link(user_a, user_b)

      create_income(scope_a, 10_000)
      create_income(scope_b, 10_000)
      create_shared_expense(scope_b, link.id, 2_000)

      {:ok, [debt]} = SharedFinance.list_shared_entry_debts(scope_a, link.id)

      {:ok, cycle} =
        SharedFinance.get_or_create_settlement_cycle(scope_a, link.id, Date.utc_today())

      assert {:error, :not_found} =
               SharedFinance.create_settlement_record_for_debt(scope_b, cycle.id, debt.id, %{
                 amount_cents: 500,
                 method: :pix,
                 transferred_at: DateTime.utc_now() |> DateTime.truncate(:second)
               })
    end
  end
end
