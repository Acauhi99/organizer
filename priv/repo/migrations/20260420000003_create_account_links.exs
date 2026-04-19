defmodule Organizer.Repo.Migrations.CreateAccountLinks do
  use Ecto.Migration

  def change do
    create table(:account_links) do
      add :user_a_id, references(:users, on_delete: :delete_all), null: false
      add :user_b_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "active"
      add :invite_id, references(:invites, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:account_links, [:user_a_id, :user_b_id],
             where: "status = 'active'",
             name: :account_links_pair_index
           )
  end
end
