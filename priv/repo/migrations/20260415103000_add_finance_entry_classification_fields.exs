defmodule Organizer.Repo.Migrations.AddFinanceEntryClassificationFields do
  use Ecto.Migration

  def change do
    alter table(:finance_entries) do
      add :expense_profile, :string
      add :payment_method, :string
    end

    create index(:finance_entries, [:user_id, :expense_profile])
    create index(:finance_entries, [:user_id, :payment_method])
  end
end
