defmodule Organizer.Repo.Migrations.CreateSharedFinanceViewPreferences do
  use Ecto.Migration

  def change do
    create table(:shared_finance_view_preferences) do
      add :from_year, :integer
      add :from_month, :integer
      add :to_year, :integer
      add :to_month, :integer
      add :settlement_focus_year, :integer
      add :settlement_focus_month, :integer
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :account_link_id, references(:account_links, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shared_finance_view_preferences, [:user_id, :account_link_id],
             name: :shared_finance_view_preferences_user_link_index
           )

    create index(:shared_finance_view_preferences, [:account_link_id])
  end
end
