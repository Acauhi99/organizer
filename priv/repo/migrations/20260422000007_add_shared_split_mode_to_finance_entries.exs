defmodule Organizer.Repo.Migrations.AddSharedSplitModeToFinanceEntries do
  use Ecto.Migration

  def change do
    alter table(:finance_entries) do
      add :shared_split_mode, :string
      add :shared_manual_mine_cents, :integer
    end

    create index(:finance_entries, [:shared_split_mode])
  end
end
