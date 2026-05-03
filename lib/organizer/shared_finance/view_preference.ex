defmodule Organizer.SharedFinance.ViewPreference do
  use Ecto.Schema
  import Ecto.Changeset

  schema "shared_finance_view_preferences" do
    field :from_year, :integer
    field :from_month, :integer
    field :to_year, :integer
    field :to_month, :integer
    field :settlement_focus_year, :integer
    field :settlement_focus_month, :integer

    belongs_to :user, Organizer.Accounts.User
    belongs_to :account_link, Organizer.SharedFinance.AccountLink

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [
      :from_year,
      :from_month,
      :to_year,
      :to_month,
      :settlement_focus_year,
      :settlement_focus_month
    ])
    |> validate_month(:from_month)
    |> validate_month(:to_month)
    |> validate_month(:settlement_focus_month)
    |> validate_year(:from_year)
    |> validate_year(:to_year)
    |> validate_year(:settlement_focus_year)
    |> validate_range_pair(:from_year, :from_month)
    |> validate_range_pair(:to_year, :to_month)
    |> validate_range_pair(:settlement_focus_year, :settlement_focus_month)
    |> unique_constraint([:user_id, :account_link_id],
      name: :shared_finance_view_preferences_user_link_index
    )
  end

  defp validate_month(changeset, field) do
    validate_number(changeset, field, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
  end

  defp validate_year(changeset, field) do
    validate_number(changeset, field, greater_than_or_equal_to: 1900, less_than_or_equal_to: 3000)
  end

  defp validate_range_pair(changeset, year_field, month_field) do
    year = get_field(changeset, year_field)
    month = get_field(changeset, month_field)

    cond do
      is_nil(year) and is_nil(month) ->
        changeset

      is_nil(year) ->
        add_error(changeset, year_field, "can't be blank when month is set")

      is_nil(month) ->
        add_error(changeset, month_field, "can't be blank when year is set")

      true ->
        changeset
    end
  end
end
