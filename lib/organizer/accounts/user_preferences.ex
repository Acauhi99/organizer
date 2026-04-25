defmodule Organizer.Accounts.UserPreferences do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_preferences" do
    field :analytics_panel_default_visible, :boolean, default: true
    field :operations_panel_default_visible, :boolean, default: true
    field :onboarding_completed, :boolean, default: false
    field :task_focus_timer_state, :map

    field :preferred_layout_mode, Ecto.Enum,
      values: [:expanded, :focused, :minimal],
      default: :expanded

    belongs_to :user, Organizer.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(preferences, attrs) do
    preferences
    |> cast(attrs, [
      :analytics_panel_default_visible,
      :operations_panel_default_visible,
      :onboarding_completed,
      :task_focus_timer_state,
      :preferred_layout_mode
    ])
    |> validate_required([:user_id])
    |> validate_inclusion(:preferred_layout_mode, [:expanded, :focused, :minimal])
  end
end
