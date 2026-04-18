defmodule Organizer.Accounts.OnboardingProgress do
  use Ecto.Schema
  import Ecto.Changeset

  schema "onboarding_progress" do
    field :current_step, :integer, default: 1
    field :completed_steps, {:array, :integer}, default: []
    field :dismissed, :boolean, default: false
    field :completed_at, :utc_datetime

    belongs_to :user, Organizer.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(progress, attrs) do
    progress
    |> cast(attrs, [:current_step, :completed_steps, :dismissed, :completed_at])
    |> validate_required([:user_id, :current_step])
    |> validate_number(:current_step, greater_than: 0, less_than_or_equal_to: 5)
  end
end
