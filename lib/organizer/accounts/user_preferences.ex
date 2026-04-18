defmodule Organizer.Accounts.UserPreferences do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_preferences" do
    field :analytics_panel_default_visible, :boolean, default: true
    field :operations_panel_default_visible, :boolean, default: true
    field :onboarding_completed, :boolean, default: false

    field :preferred_layout_mode, Ecto.Enum,
      values: [:expanded, :focused, :minimal],
      default: :expanded

    field :bulk_import_block_size_preference, :integer, default: 3

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
      :preferred_layout_mode,
      :bulk_import_block_size_preference
    ])
    |> validate_required([:user_id])
    |> validate_inclusion(:preferred_layout_mode, [:expanded, :focused, :minimal])
    |> validate_number(:bulk_import_block_size_preference,
      greater_than: 0,
      less_than_or_equal_to: 20
    )
  end
end
