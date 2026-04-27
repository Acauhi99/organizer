defmodule Organizer.Repo.Migrations.BackfillSharedSplitFieldsAndResetSnapshots do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE finance_entries
    SET shared_split_mode = 'income_ratio'
    WHERE shared_with_link_id IS NOT NULL
      AND shared_split_mode IS NULL
    """)

    execute("""
    UPDATE finance_entries
    SET shared_manual_mine_cents = NULL
    WHERE shared_split_mode IS NULL
       OR shared_split_mode != 'manual'
    """)

    execute("""
    UPDATE finance_entries
    SET shared_manual_mine_cents = 0
    WHERE shared_split_mode = 'manual'
      AND shared_manual_mine_cents < 0
    """)

    execute("""
    UPDATE finance_entries
    SET shared_manual_mine_cents = amount_cents
    WHERE shared_split_mode = 'manual'
      AND shared_manual_mine_cents > amount_cents
    """)

    execute("DELETE FROM shared_split_snapshots")
  end

  def down do
    :ok
  end
end
