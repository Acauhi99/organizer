defmodule Organizer.Repo.Migrations.AddGoogleSubToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :google_sub, :string
    end

    create unique_index(:users, [:google_sub])
  end
end
