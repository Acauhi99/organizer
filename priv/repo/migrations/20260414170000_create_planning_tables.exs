defmodule Organizer.Repo.Migrations.CreatePlanningTables do
  use Ecto.Migration

  def change do
    create table(:finance_entries) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :amount_cents, :integer, null: false
      add :category, :string, null: false
      add :description, :string
      add :occurred_on, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:finance_entries, [:user_id])
    create index(:finance_entries, [:user_id, :kind])
    create index(:finance_entries, [:user_id, :occurred_on])

    create table(:fixed_costs) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :amount_cents, :integer, null: false
      add :billing_day, :integer, null: false
      add :starts_on, :date
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:fixed_costs, [:user_id])
    create index(:fixed_costs, [:user_id, :active])

    create table(:important_dates) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :category, :string, null: false, default: "personal"
      add :date, :date, null: false
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:important_dates, [:user_id])
    create index(:important_dates, [:user_id, :date])

    create table(:goals) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :horizon, :string, null: false
      add :status, :string, null: false, default: "active"
      add :target_value, :integer
      add :current_value, :integer, default: 0, null: false
      add :due_on, :date
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:goals, [:user_id])
    create index(:goals, [:user_id, :horizon])
    create index(:goals, [:user_id, :status])
  end
end
