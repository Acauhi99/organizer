defmodule Organizer.Repo.Migrations.AddInstallmentsCountToFinanceEntries do
  use Ecto.Migration

  def change do
    alter table(:finance_entries) do
      add :installments_count, :integer
    end

    create index(:finance_entries, [:user_id, :installments_count])
  end
end
