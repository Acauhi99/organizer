defmodule Organizer.Repo.Migrations.CreateSettlementRecords do
  use Ecto.Migration

  def change do
    create table(:settlement_records) do
      add :settlement_cycle_id, references(:settlement_cycles, on_delete: :delete_all),
        null: false

      add :payer_id, references(:users, on_delete: :delete_all), null: false
      add :receiver_id, references(:users, on_delete: :delete_all), null: false
      add :amount_cents, :integer, null: false
      add :method, :string, null: false
      add :transferred_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
