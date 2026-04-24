defmodule Organizer.Planning.QualityAuditTest do
  use Organizer.DataCase

  alias Organizer.Planning
  alias Organizer.Planning.FinanceEntry

  import Organizer.AccountsFixtures

  describe "Req 1: update_task validation consistency" do
    test "update_task with blank title returns validation error" do
      scope = user_scope_fixture()

      # Create a valid task first
      assert {:ok, task} =
               Planning.create_task(scope, %{
                 "title" => "Valid task",
                 "priority" => "medium"
               })

      # Try to update with blank title
      assert {:error, {:validation, errors}} =
               Planning.update_task(scope, task.id, %{"title" => "   "})

      assert Map.has_key?(errors, :title)
    end

    test "update_task with whitespace-only title returns validation error" do
      scope = user_scope_fixture()

      assert {:ok, task} =
               Planning.create_task(scope, %{
                 "title" => "Original title",
                 "priority" => "low"
               })

      # Update with whitespace-only title
      assert {:error, {:validation, errors}} =
               Planning.update_task(scope, task.id, %{"title" => "\t\n  "})

      assert Map.has_key?(errors, :title)
    end
  end

  describe "Req 2: important_date and fixed_cost validation" do
    test "create_important_date with invalid attributes returns error without hitting database" do
      scope = user_scope_fixture()

      # Title too short
      assert {:error, {:validation, errors}} =
               Planning.create_important_date(scope, %{
                 "title" => "x",
                 "category" => "personal",
                 "date" => "2025-12-25"
               })

      assert Map.has_key?(errors, :title)

      # Invalid category - use a string that won't be converted to atom
      assert {:error, {:validation, errors}} =
               Planning.create_important_date(scope, %{
                 "title" => "Valid title",
                 "category" => "x",
                 "date" => "2025-12-25"
               })

      assert Map.has_key?(errors, :category)
    end

    test "create_fixed_cost with invalid attributes returns error without hitting database" do
      scope = user_scope_fixture()

      # Name too short
      assert {:error, {:validation, errors}} =
               Planning.create_fixed_cost(scope, %{
                 "name" => "x",
                 "amount_cents" => 5000,
                 "billing_day" => 15
               })

      assert Map.has_key?(errors, :name)

      # Invalid billing_day
      assert {:error, {:validation, errors}} =
               Planning.create_fixed_cost(scope, %{
                 "name" => "Valid name",
                 "amount_cents" => 5000,
                 "billing_day" => 35
               })

      assert Map.has_key?(errors, :billing_day)

      # Amount_cents zero or negative
      assert {:error, {:validation, errors}} =
               Planning.create_fixed_cost(scope, %{
                 "name" => "Valid name",
                 "amount_cents" => 0,
                 "billing_day" => 15
               })

      assert Map.has_key?(errors, :amount_cents)
    end
  end

  describe "Req 7: amount_cents upper limit validation" do
    test "FinanceEntry.changeset with amount_cents > 1_000_000_000 returns invalid changeset" do
      changeset =
        FinanceEntry.changeset(%FinanceEntry{}, %{
          kind: :expense,
          expense_profile: :variable,
          payment_method: :debit,
          amount_cents: 1_000_000_001,
          category: "test",
          occurred_on: Date.utc_today()
        })

      refute changeset.valid?
      assert %{amount_cents: _} = errors_on(changeset)
    end

    test "FinanceEntry.changeset with amount_cents = 1_000_000_000 is valid" do
      changeset =
        FinanceEntry.changeset(%FinanceEntry{}, %{
          kind: :expense,
          expense_profile: :variable,
          payment_method: :debit,
          amount_cents: 1_000_000_000,
          category: "test",
          occurred_on: Date.utc_today()
        })

      assert changeset.valid?
    end

    test "FinanceEntry.changeset with amount_cents below limit is valid" do
      changeset =
        FinanceEntry.changeset(%FinanceEntry{}, %{
          kind: :income,
          amount_cents: 500_000,
          category: "salary",
          occurred_on: Date.utc_today()
        })

      assert changeset.valid?
    end
  end
end
