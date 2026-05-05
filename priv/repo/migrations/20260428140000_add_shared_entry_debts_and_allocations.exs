defmodule Organizer.Repo.Migrations.AddSharedEntryDebtsAndAllocations do
  use Ecto.Migration

  import Ecto.Query

  alias Organizer.Planning.FinanceEntry
  alias Organizer.Repo
  alias Organizer.SharedFinance.AccountLink
  alias Organizer.SharedFinance.SettlementCycle
  alias Organizer.SharedFinance.SplitCalculator

  defmodule SharedEntryDebtMigration do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: true}
    @timestamps_opts [type: :utc_datetime]

    schema "shared_entry_debts" do
      field(:account_link_id, :integer)
      field(:finance_entry_id, :integer)
      field(:debtor_id, :integer)
      field(:creditor_id, :integer)
      field(:reference_month, :integer)
      field(:reference_year, :integer)
      field(:original_amount_cents, :integer)
      field(:outstanding_amount_cents, :integer)
      field(:status, Ecto.Enum, values: [:open, :partial, :settled])

      Ecto.Schema.timestamps(type: :utc_datetime)
    end
  end

  defmodule SettlementRecordAllocationMigration do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: true}
    @timestamps_opts [type: :utc_datetime]

    schema "settlement_record_allocations" do
      field(:settlement_record_id, :integer)
      field(:shared_entry_debt_id, :integer)
      field(:amount_cents, :integer)

      Ecto.Schema.timestamps(type: :utc_datetime)
    end
  end

  defmodule SettlementRecordMigration do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: true}
    @timestamps_opts [type: :utc_datetime]

    schema "settlement_records" do
      field(:settlement_cycle_id, :integer)
      field(:payer_id, :integer)
      field(:receiver_id, :integer)
      field(:amount_cents, :integer)
      field(:method, :string)
      field(:transferred_at, :utc_datetime)

      Ecto.Schema.timestamps(type: :utc_datetime)
    end
  end

  def up do
    create table(:shared_entry_debts) do
      add :account_link_id, references(:account_links, on_delete: :delete_all), null: false
      add :finance_entry_id, references(:finance_entries, on_delete: :delete_all), null: false
      add :debtor_id, references(:users, on_delete: :delete_all), null: false
      add :creditor_id, references(:users, on_delete: :delete_all), null: false
      add :reference_month, :integer, null: false
      add :reference_year, :integer, null: false
      add :original_amount_cents, :integer, null: false
      add :outstanding_amount_cents, :integer, null: false
      add :status, :string, null: false, default: "open"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shared_entry_debts, [:finance_entry_id])

    create index(:shared_entry_debts, [:account_link_id, :status])

    create index(:shared_entry_debts, [
             :debtor_id,
             :creditor_id,
             :account_link_id,
             :status,
             :reference_year,
             :reference_month
           ])

    create table(:settlement_record_allocations) do
      add :settlement_record_id, references(:settlement_records, on_delete: :delete_all),
        null: false

      add :shared_entry_debt_id, references(:shared_entry_debts, on_delete: :delete_all),
        null: false

      add :amount_cents, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:settlement_record_allocations, [:settlement_record_id])
    create index(:settlement_record_allocations, [:shared_entry_debt_id])

    flush()

    backfill_shared_entry_debts_and_allocations()
  end

  def down do
    drop table(:settlement_record_allocations)
    drop table(:shared_entry_debts)
  end

  defp backfill_shared_entry_debts_and_allocations do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    link_map =
      Repo.all(from(l in AccountLink, select: {l.id, l}))
      |> Map.new()

    shared_expense_entries =
      Repo.all(
        from(fe in FinanceEntry,
          where:
            fe.kind == :expense and not is_nil(fe.shared_with_link_id) and
              not is_nil(fe.shared_split_mode)
        )
      )

    Enum.each(shared_expense_entries, fn entry ->
      link = Map.get(link_map, entry.shared_with_link_id)

      if is_nil(link) do
        :ok
      else
        debt_amount_cents = debt_amount_cents_for_entry(entry, link)

        if debt_amount_cents <= 0 do
          :ok
        else
          {debtor_id, creditor_id} = debtor_creditor_for_entry(entry, link)

          %SharedEntryDebtMigration{}
          |> Ecto.Changeset.change(%{
            account_link_id: entry.shared_with_link_id,
            finance_entry_id: entry.id,
            debtor_id: debtor_id,
            creditor_id: creditor_id,
            reference_month: entry.occurred_on.month,
            reference_year: entry.occurred_on.year,
            original_amount_cents: debt_amount_cents,
            outstanding_amount_cents: debt_amount_cents,
            status: :open,
            inserted_at: now,
            updated_at: now
          })
          |> Repo.insert!()
        end
      end
    end)

    records =
      Repo.all(
        from(sr in SettlementRecordMigration,
          order_by: [asc: sr.transferred_at, asc: sr.id]
        )
      )

    Enum.each(records, fn record ->
      cycle = Repo.get(SettlementCycle, record.settlement_cycle_id)

      available_debts =
        if is_nil(cycle) do
          []
        else
          Repo.all(
            from(d in SharedEntryDebtMigration,
              where:
                d.account_link_id == ^cycle.account_link_id and
                  d.debtor_id == ^record.payer_id and
                  d.creditor_id == ^record.receiver_id and
                  d.status in [:open, :partial],
              order_by: [asc: d.reference_year, asc: d.reference_month, asc: d.id]
            )
          )
        end

      if available_debts == [] do
        :ok
      else
        allocate_backfill(record, available_debts, now)
      end
    end)
  end

  defp allocate_backfill(record, debts, now) do
    Enum.reduce_while(debts, record.amount_cents, fn debt, remaining ->
      if remaining <= 0 do
        {:halt, 0}
      else
        allocated = min(remaining, debt.outstanding_amount_cents)
        new_outstanding = debt.outstanding_amount_cents - allocated

        status =
          cond do
            new_outstanding == 0 -> :settled
            new_outstanding < debt.original_amount_cents -> :partial
            true -> :open
          end

        debt
        |> Ecto.Changeset.change(%{
          outstanding_amount_cents: new_outstanding,
          status: status,
          updated_at: now
        })
        |> Repo.update!()

        %SettlementRecordAllocationMigration{}
        |> Ecto.Changeset.change(%{
          settlement_record_id: record.id,
          shared_entry_debt_id: debt.id,
          amount_cents: allocated,
          inserted_at: now,
          updated_at: now
        })
        |> Repo.insert!()

        {:cont, remaining - allocated}
      end
    end)

    :ok
  end

  defp debtor_creditor_for_entry(entry, link) do
    if entry.user_id == link.user_a_id do
      {link.user_b_id, link.user_a_id}
    else
      {link.user_a_id, link.user_b_id}
    end
  end

  defp debt_amount_cents_for_entry(entry, link) do
    mine_cents =
      case entry.shared_split_mode do
        :manual when is_integer(entry.shared_manual_mine_cents) ->
          min(max(entry.shared_manual_mine_cents, 0), entry.amount_cents)

        _ ->
          income_a =
            SplitCalculator.calculate_reference_income_with_carryover(
              link.user_a_id,
              entry.occurred_on.month,
              entry.occurred_on.year
            )

          income_b =
            SplitCalculator.calculate_reference_income_with_carryover(
              link.user_b_id,
              entry.occurred_on.month,
              entry.occurred_on.year
            )

          ratio_a_owner =
            cond do
              entry.user_id == link.user_a_id and income_a + income_b > 0 ->
                income_a / (income_a + income_b)

              entry.user_id == link.user_b_id and income_a + income_b > 0 ->
                income_b / (income_a + income_b)

              true ->
                1.0
            end

          round(entry.amount_cents * ratio_a_owner)
      end

    max(entry.amount_cents - mine_cents, 0)
  end
end
