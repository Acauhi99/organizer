defmodule Organizer.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Organizer.Repo

  alias Organizer.Accounts.{User, UserToken, UserPreferences, OnboardingProgress}

  @task_focus_timer_statuses ["idle", "running", "paused", "finished"]
  @task_focus_default_duration_minutes 30
  @task_focus_min_minutes 1
  @task_focus_max_minutes 600

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

  @doc """
  Returns the persisted task focus timer state for a user.
  """
  def get_task_focus_timer_state(%User{} = user) do
    with {:ok, preferences} <- get_or_create_user_preferences(user) do
      {:ok, normalize_task_focus_timer_state(preferences.task_focus_timer_state)}
    end
  end

  @doc """
  Persists task focus timer state for a user.
  """
  def set_task_focus_timer_state(%User{} = user, attrs) when is_map(attrs) do
    normalized_state = normalize_task_focus_timer_state(attrs)

    with {:ok, preferences} <- get_or_create_user_preferences(user) do
      update_user_preferences(preferences, %{task_focus_timer_state: normalized_state})
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

  defp normalize_task_focus_timer_state(nil), do: nil
  defp normalize_task_focus_timer_state(%{} = attrs) when map_size(attrs) == 0, do: nil

  defp normalize_task_focus_timer_state(%{} = attrs) do
    duration_minutes =
      normalize_integer(
        timer_state_value(
          attrs,
          "durationMinutes",
          :duration_minutes,
          @task_focus_default_duration_minutes
        ),
        @task_focus_default_duration_minutes,
        @task_focus_min_minutes,
        @task_focus_max_minutes
      )

    total_seconds = duration_minutes * 60

    status =
      normalize_status(
        timer_state_value(attrs, "status", :status, "idle"),
        "idle"
      )

    remaining_seconds =
      normalize_integer(
        timer_state_value(attrs, "remainingSeconds", :remaining_seconds, total_seconds),
        total_seconds,
        0,
        total_seconds
      )

    task_id = normalize_string(timer_state_value(attrs, "taskId", :task_id, ""))
    task_label = normalize_string(timer_state_value(attrs, "taskLabel", :task_label, ""))
    notified = truthy?(timer_state_value(attrs, "notified", :notified, false))

    ends_at_ms =
      normalize_optional_non_negative_integer(
        timer_state_value(attrs, "endsAtMs", :ends_at_ms, nil)
      )

    normalized = %{
      "taskId" => task_id,
      "taskLabel" => task_label,
      "durationMinutes" => duration_minutes,
      "remainingSeconds" => remaining_seconds,
      "status" => status,
      "endsAtMs" => ends_at_ms,
      "notified" => notified
    }

    normalized =
      cond do
        normalized["status"] == "running" and is_nil(normalized["endsAtMs"]) ->
          Map.merge(normalized, %{
            "status" => "paused",
            "endsAtMs" => nil
          })

        normalized["status"] == "paused" ->
          Map.put(normalized, "endsAtMs", nil)

        normalized["status"] == "finished" ->
          Map.merge(normalized, %{
            "remainingSeconds" => 0,
            "endsAtMs" => nil
          })

        normalized["status"] == "idle" ->
          Map.merge(normalized, %{
            "remainingSeconds" =>
              if(normalized["remainingSeconds"] == 0, do: total_seconds, else: remaining_seconds),
            "endsAtMs" => nil
          })

        true ->
          normalized
      end

    if normalized["status"] == "running" and normalized["remainingSeconds"] <= 0 do
      Map.merge(normalized, %{
        "status" => "finished",
        "remainingSeconds" => 0,
        "endsAtMs" => nil
      })
    else
      normalized
    end
  end

  defp normalize_task_focus_timer_state(_invalid), do: nil

  defp timer_state_value(attrs, camel_key, snake_key, default) do
    Map.get(attrs, camel_key) ||
      Map.get(attrs, Macro.underscore(camel_key)) ||
      Map.get(attrs, snake_key) ||
      default
  end

  defp normalize_string(value) when is_binary(value), do: value
  defp normalize_string(value) when is_nil(value), do: ""
  defp normalize_string(value), do: to_string(value)

  defp normalize_status(value, fallback) do
    normalized = value |> normalize_string() |> String.trim()
    if normalized in @task_focus_timer_statuses, do: normalized, else: fallback
  end

  defp normalize_integer(value, fallback, min_value, max_value) do
    value
    |> parse_integer()
    |> case do
      {:ok, parsed} -> parsed |> max(min_value) |> min(max_value)
      :error -> fallback
    end
  end

  defp normalize_optional_non_negative_integer(value) do
    case parse_integer(value) do
      {:ok, parsed} when parsed >= 0 -> parsed
      _ -> nil
    end
  end

  defp parse_integer(value) when is_integer(value), do: {:ok, value}

  defp parse_integer(value) when is_float(value) do
    {:ok, value |> Float.floor() |> trunc()}
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_integer(_value), do: :error

  defp truthy?(value), do: value in [true, "true", 1, "1"]
end
