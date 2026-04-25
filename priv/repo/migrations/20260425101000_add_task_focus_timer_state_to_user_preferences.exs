defmodule Organizer.Repo.Migrations.AddTaskFocusTimerStateToUserPreferences do
  use Ecto.Migration

  def change do
    alter table(:user_preferences) do
      add :task_focus_timer_state, :map
    end
  end
end
