defmodule Organizer.SharedFinance.Invite do
  use Ecto.Schema
  import Ecto.Changeset

  schema "invites" do
    field :token, :string
    field :status, Ecto.Enum, values: [:pending, :accepted, :expired]
    field :expires_at, :utc_datetime
    belongs_to :inviter, Organizer.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:token, :status, :expires_at])
    |> validate_required([:token, :status, :expires_at])
    |> unique_constraint(:token, name: :invites_token_index)
  end
end
