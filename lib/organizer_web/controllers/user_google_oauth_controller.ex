defmodule OrganizerWeb.UserGoogleOAuthController do
  use OrganizerWeb, :controller

  alias Organizer.Accounts
  alias OrganizerWeb.FlashFeedback
  alias OrganizerWeb.UserAuth

  @oauth_state_key :google_oauth_state
  @oauth_code_verifier_key :google_oauth_code_verifier

  def request(conn, _params) do
    state = random_urlsafe(32)
    code_verifier = random_urlsafe(48)
    code_challenge = pkce_challenge(code_verifier)
    redirect_uri = url(conn, ~p"/users/auth/google/callback")

    case oauth_client().build_authorize_url(
           state: state,
           code_challenge: code_challenge,
           redirect_uri: redirect_uri
         ) do
      {:ok, authorize_url} ->
        conn
        |> put_session(@oauth_state_key, state)
        |> put_session(@oauth_code_verifier_key, code_verifier)
        |> redirect(external: authorize_url)

      {:error, :missing_configuration} ->
        conn
        |> error_feedback(
          "Login com Google ainda não está configurado",
          "Use e-mail e senha para entrar enquanto a integração não estiver disponível"
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, _reason} ->
        conn
        |> error_feedback(
          "Não foi possível iniciar o login com Google",
          "Tente novamente em instantes ou use e-mail e senha"
        )
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def callback(conn, %{"error" => _error}) do
    conn
    |> clear_oauth_session()
    |> error_feedback(
      "Login com Google foi cancelado ou negado",
      "Inicie novamente o login quando quiser continuar"
    )
    |> redirect(to: ~p"/users/log-in")
  end

  def callback(conn, %{"state" => returned_state, "code" => code}) do
    with {:ok, code_verifier} <- verify_oauth_state(conn, returned_state),
         {:ok, profile} <-
           oauth_client().fetch_userinfo(
             code,
             code_verifier,
             url(conn, ~p"/users/auth/google/callback")
           ),
         :ok <- ensure_verified_email(profile),
         {:ok, user} <- find_or_create_user(profile) do
      conn
      |> clear_oauth_session()
      |> info_feedback(
        "Login com Google realizado com sucesso",
        "Revise seus dados e continue sua rotina financeira"
      )
      |> UserAuth.log_in_user(user, %{"remember_me" => "true"})
    else
      {:error, :invalid_state} ->
        conn
        |> clear_oauth_session()
        |> error_feedback(
          "Sessão de login com Google inválida",
          "Tente novamente iniciando o login desde o começo"
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, :missing_configuration} ->
        conn
        |> clear_oauth_session()
        |> error_feedback(
          "Login com Google ainda não está configurado",
          "Use e-mail e senha para acessar sua conta"
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, :google_email_not_verified} ->
        conn
        |> clear_oauth_session()
        |> error_feedback(
          "Seu e-mail do Google precisa estar verificado para entrar",
          "Verifique o e-mail no Google e tente novamente"
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, :google_account_conflict} ->
        conn
        |> clear_oauth_session()
        |> error_feedback(
          "Este e-mail já está vinculado a outra conta Google",
          "Entre com senha para recuperar acesso"
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, _reason} ->
        conn
        |> clear_oauth_session()
        |> error_feedback(
          "Não foi possível concluir o login com Google",
          "Tente novamente em instantes"
        )
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def callback(conn, _params) do
    conn
    |> clear_oauth_session()
    |> error_feedback(
      "Resposta inválida do login com Google",
      "Inicie novamente o login para gerar uma nova resposta"
    )
    |> redirect(to: ~p"/users/log-in")
  end

  defp verify_oauth_state(conn, returned_state) do
    expected_state = get_session(conn, @oauth_state_key)
    code_verifier = get_session(conn, @oauth_code_verifier_key)

    cond do
      not is_binary(expected_state) ->
        {:error, :invalid_state}

      not is_binary(code_verifier) ->
        {:error, :invalid_state}

      not is_binary(returned_state) ->
        {:error, :invalid_state}

      byte_size(expected_state) != byte_size(returned_state) ->
        {:error, :invalid_state}

      not Plug.Crypto.secure_compare(expected_state, returned_state) ->
        {:error, :invalid_state}

      true ->
        {:ok, code_verifier}
    end
  end

  defp ensure_verified_email(%{email_verified: true}), do: :ok
  defp ensure_verified_email(_profile), do: {:error, :google_email_not_verified}

  defp find_or_create_user(%{email: email, sub: google_sub}) do
    Accounts.find_or_create_user_by_google(%{email: email, google_sub: google_sub})
  end

  defp find_or_create_user(_profile), do: {:error, :invalid_google_profile}

  defp clear_oauth_session(conn) do
    conn
    |> delete_session(@oauth_state_key)
    |> delete_session(@oauth_code_verifier_key)
  end

  defp random_urlsafe(byte_size) when is_integer(byte_size) and byte_size > 0 do
    :crypto.strong_rand_bytes(byte_size)
    |> Base.url_encode64(padding: false)
  end

  defp pkce_challenge(code_verifier) do
    :crypto.hash(:sha256, code_verifier)
    |> Base.url_encode64(padding: false)
  end

  defp oauth_client do
    Application.get_env(:organizer, :google_oauth_client, Organizer.GoogleOAuth)
  end

  defp info_feedback(conn, happened, next_step) do
    put_flash(conn, :info, FlashFeedback.compose(happened, next_step))
  end

  defp error_feedback(conn, happened, next_step) do
    put_flash(conn, :error, FlashFeedback.compose(happened, next_step))
  end
end
