defmodule Organizer.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Organizer.Repo

  alias Organizer.Accounts.{User, UserToken, UserPreferences, OnboardingProgress}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Registers a user with email and password and confirms the account.

  This flow reduces onboarding friction by allowing immediate sign-in
  right after account creation.
  """
  def register_user_with_password(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for user registration with password.
  """
  def change_user_registration(user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, Keyword.put_new(opts, :confirm, false))
  end

  @doc """
  Finds or creates a user authenticated by Google OAuth.

  Matching priority:
  1. Existing user with the same `google_sub`
  2. Existing user with the same email (links `google_sub`)
  3. New user creation
  """
  def find_or_create_user_by_google(%{email: email, google_sub: google_sub})
      when is_binary(email) and is_binary(google_sub) do
    normalized_email = email |> String.trim() |> String.downcase()
    normalized_google_sub = String.trim(google_sub)

    if normalized_email == "" or normalized_google_sub == "" do
      {:error, :invalid_google_profile}
    else
      case Repo.get_by(User, google_sub: normalized_google_sub) do
        %User{} = user ->
          {:ok, user}

        nil ->
          find_or_create_user_by_google_email(normalized_email, normalized_google_sub)
      end
    end
  end

  def find_or_create_user_by_google(_attrs), do: {:error, :invalid_google_profile}

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Organizer.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Resets the user password.
  """
  def reset_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token lifecycle support

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  defp find_or_create_user_by_google_email(email, google_sub) do
    case Repo.get_by(User, email: email) do
      nil ->
        create_user_from_google_profile(email, google_sub)

      %User{google_sub: nil} = user ->
        link_google_account(user, google_sub)

      %User{google_sub: ^google_sub} = user ->
        {:ok, user}

      %User{} ->
        {:error, :google_account_conflict}
    end
  end

  defp create_user_from_google_profile(email, google_sub) do
    attrs = %{email: email, google_sub: google_sub}

    %User{}
    |> User.google_registration_changeset(attrs, confirm: true)
    |> Repo.insert()
  end

  defp link_google_account(%User{} = user, google_sub) do
    confirmed_at = user.confirmed_at || DateTime.utc_now(:second)

    user
    |> User.google_link_changeset(%{google_sub: google_sub, confirmed_at: confirmed_at})
    |> Repo.update()
    |> case do
      {:ok, linked_user} ->
        {:ok, linked_user}

      {:error, changeset} ->
        if google_sub_taken?(changeset) do
          {:error, :google_account_conflict}
        else
          {:error, changeset}
        end
    end
  end

  defp google_sub_taken?(changeset) do
    Enum.any?(changeset.errors, fn
      {:google_sub, {"has already been taken", _}} -> true
      _ -> false
    end)
  end

  ## User Preferences

  @doc """
  Gets or creates user preferences for the given user.

  Returns the user preferences with default values if they don't exist.

  ## Examples

      iex> get_or_create_user_preferences(user)
      {:ok, %UserPreferences{}}

  """
  def get_or_create_user_preferences(%User{} = user) do
    case Repo.get_by(UserPreferences, user_id: user.id) do
      nil ->
        %UserPreferences{user_id: user.id}
        |> UserPreferences.changeset(%{})
        |> Repo.insert()

      preferences ->
        {:ok, preferences}
    end
  end

  @doc """
  Updates user preferences.

  ## Examples

      iex> update_user_preferences(preferences, %{analytics_panel_default_visible: false})
      {:ok, %UserPreferences{}}

      iex> update_user_preferences(preferences, %{preferred_layout_mode: :invalid})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_preferences(%UserPreferences{} = preferences, attrs) do
    preferences
    |> UserPreferences.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Sets a single preference field for the user.

  This is a convenience function for updating individual preferences.

  ## Examples

      iex> set_preference(user, :analytics_panel_default_visible, false)
      {:ok, %UserPreferences{}}

  """
  def set_preference(%User{} = user, field, value) when is_atom(field) do
    with {:ok, preferences} <- get_or_create_user_preferences(user) do
      update_user_preferences(preferences, %{field => value})
    end
  end

  ## Onboarding Progress

  @doc """
  Gets or creates onboarding progress for the given user.

  Returns the onboarding progress with default values if it doesn't exist.

  ## Examples

      iex> get_or_create_onboarding_progress(user)
      {:ok, %OnboardingProgress{}}

  """
  def get_or_create_onboarding_progress(%User{} = user) do
    case Repo.get_by(OnboardingProgress, user_id: user.id) do
      nil ->
        %OnboardingProgress{user_id: user.id}
        |> OnboardingProgress.changeset(%{})
        |> Repo.insert()

      progress ->
        {:ok, progress}
    end
  end

  @doc """
  Advances the onboarding to the next step.

  ## Examples

      iex> advance_onboarding_step(progress)
      {:ok, %OnboardingProgress{}}

  """
  def advance_onboarding_step(%OnboardingProgress{} = progress) do
    new_step = progress.current_step + 1
    completed_steps = Enum.uniq([progress.current_step | progress.completed_steps])

    progress
    |> OnboardingProgress.changeset(%{
      current_step: new_step,
      completed_steps: completed_steps
    })
    |> Repo.update()
  end

  @doc """
  Marks the onboarding as completed.

  ## Examples

      iex> complete_onboarding(progress)
      {:ok, %OnboardingProgress{}}

  """
  def complete_onboarding(%OnboardingProgress{} = progress) do
    progress
    |> OnboardingProgress.changeset(%{
      completed_at: DateTime.utc_now(),
      completed_steps: Enum.uniq([progress.current_step | progress.completed_steps])
    })
    |> Repo.update()
  end

  @doc """
  Dismisses the onboarding without completing it.

  ## Examples

      iex> dismiss_onboarding(progress)
      {:ok, %OnboardingProgress{}}

  """
  def dismiss_onboarding(%OnboardingProgress{} = progress) do
    progress
    |> OnboardingProgress.changeset(%{dismissed: true})
    |> Repo.update()
  end

  @doc """
  Restarts the onboarding tutorial from the beginning.

  ## Examples

      iex> restart_onboarding(progress)
      {:ok, %OnboardingProgress{}}

  """
  def restart_onboarding(%OnboardingProgress{} = progress) do
    progress
    |> OnboardingProgress.changeset(%{
      current_step: 1,
      dismissed: false,
      completed_at: nil
    })
    |> Repo.update()
  end
end
