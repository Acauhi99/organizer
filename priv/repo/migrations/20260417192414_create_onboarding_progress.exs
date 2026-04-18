defmodule Organizer.Repo.Migrations.CreateOnboardingProgress do
  use Ecto.Migration

  def change do
    create table(:onboarding_progress) do
      add :current_step, :integer, default: 1, null: false
      add :completed_steps, {:array, :integer}, default: [], null: false
      add :dismissed, :boolean, default: false, null: false
      add :completed_at, :utc_datetime
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:onboarding_progress, [:user_id])
  end
end
