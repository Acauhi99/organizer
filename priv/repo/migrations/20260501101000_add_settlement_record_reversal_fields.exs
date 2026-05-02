defmodule Organizer.Repo.Migrations.AddSettlementRecordReversalFields do
  use Ecto.Migration

  def change do
    alter table(:settlement_records) do
      add :status, :string, null: false, default: "active"
      add :reversed_at, :utc_datetime
      add :reversal_reason, :string
      add :reversed_by_id, references(:users, on_delete: :nilify_all)
    end

    create index(:settlement_records, [:status])
    create index(:settlement_records, [:reversed_by_id])
  end
end
