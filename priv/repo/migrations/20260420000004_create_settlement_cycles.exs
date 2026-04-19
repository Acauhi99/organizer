defmodule Organizer.Repo.Migrations.CreateSettlementCycles do
  use Ecto.Migration

  def change do
    create table(:settlement_cycles) do
      add :account_link_id, references(:account_links, on_delete: :delete_all), null: false
      add :reference_month, :integer, null: false
      add :reference_year, :integer, null: false
      add :status, :string, null: false, default: "open"
      add :balance_cents, :integer, null: false, default: 0
      add :debtor_id, references(:users, on_delete: :nilify_all)
      add :confirmed_by_a, :integer, null: false, default: 0
      add :confirmed_by_b, :integer, null: false, default: 0
      add :settled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:settlement_cycles, [:account_link_id, :reference_month, :reference_year],
             name: :settlement_cycles_link_month_index
           )
  end
end
