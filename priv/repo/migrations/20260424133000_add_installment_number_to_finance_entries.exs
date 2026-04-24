defmodule Organizer.Repo.Migrations.AddInstallmentNumberToFinanceEntries do
  use Ecto.Migration

  def change do
    alter table(:finance_entries) do
      add :installment_number, :integer
    end

    create index(:finance_entries, [:user_id, :installment_number])
  end
end
