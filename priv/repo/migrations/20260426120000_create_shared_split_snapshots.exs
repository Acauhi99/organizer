defmodule Organizer.Repo.Migrations.CreateSharedSplitSnapshots do
  use Ecto.Migration

  def change do
    create table(:shared_split_snapshots) do
      add :account_link_id, :integer, null: false
      add :finance_entry_id, :integer, null: false
      add :reference_month, :integer, null: false
      add :reference_year, :integer, null: false
      add :split_mode, :string, null: false
      add :ratio_a, :float, null: false
      add :ratio_b, :float, null: false
      add :amount_a_cents, :integer, null: false
      add :amount_b_cents, :integer, null: false
      add :income_a_cents, :integer, null: false
      add :income_b_cents, :integer, null: false
      add :calculated_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:shared_split_snapshots, [:account_link_id, :reference_year, :reference_month])
    create index(:shared_split_snapshots, [:finance_entry_id, :reference_year, :reference_month])
    create index(:shared_split_snapshots, [:calculated_at])
  end
end
