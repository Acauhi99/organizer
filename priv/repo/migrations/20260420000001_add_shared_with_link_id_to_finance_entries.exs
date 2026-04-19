defmodule Organizer.Repo.Migrations.AddSharedWithLinkIdToFinanceEntries do
  use Ecto.Migration

  def change do
    alter table(:finance_entries) do
      add :shared_with_link_id, :integer
    end
  end
end
