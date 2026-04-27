defmodule Organizer.GoogleOAuth do
  @moduledoc """
  Google OAuth2 helper functions.
  """

  require Logger

  @default_authorize_endpoint "https://accounts.google.com/o/oauth2/v2/auth"
  @default_token_endpoint "https://oauth2.googleapis.com/token"
  @default_userinfo_endpoint "https://openidconnect.googleapis.com/v1/userinfo"

  @spec build_authorize_url(keyword()) :: {:ok, String.t()} | {:error, :missing_configuration}
  def build_authorize_url(opts) when is_list(opts) do
    with {:ok, client_id} <- fetch_config(:client_id) do
      state = Keyword.fetch!(opts, :state)
      code_challenge = Keyword.fetch!(opts, :code_challenge)
      redirect_uri = Keyword.fetch!(opts, :redirect_uri)

      params = %{
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "response_type" => "code",
        "scope" => "openid email profile",
        "state" => state,
        "code_challenge" => code_challenge,
        "code_challenge_method" => "S256",
        "prompt" => "select_account",
        "access_type" => "online"
      }

      authorize_url = authorize_endpoint() <> "?" <> URI.encode_query(params)
      {:ok, authorize_url}
    end
  end

  @spec fetch_userinfo(String.t(), String.t(), String.t()) ::
          {:ok, %{email: String.t(), email_verified: boolean(), sub: String.t()}}
          | {:error, atom()}
  def fetch_userinfo(code, code_verifier, redirect_uri)
      when is_binary(code) and is_binary(code_verifier) and is_binary(redirect_uri) do
    with {:ok, access_token} <- exchange_code_for_access_token(code, code_verifier, redirect_uri) do
      request_userinfo(access_token)
    end
  end

  defp exchange_code_for_access_token(code, code_verifier, redirect_uri) do
    with {:ok, client_id} <- fetch_config(:client_id),
         {:ok, client_secret} <- fetch_config(:client_secret),
         {:ok, response} <-
           Req.post(token_endpoint(),
             form: %{
               "grant_type" => "authorization_code",
               "client_id" => client_id,
               "client_secret" => client_secret,
               "code" => code,
               "code_verifier" => code_verifier,
               "redirect_uri" => redirect_uri
             }
           ),
         {:ok, body} <- decode_success_body(response, :token_exchange_failed),
         access_token when is_binary(access_token) <- body["access_token"] do
      {:ok, access_token}
    else
      nil ->
        {:error, :token_exchange_failed}

      {:error, :missing_configuration} ->
        {:error, :missing_configuration}

      {:error, reason} ->
        Logger.warning("Google token exchange failed: #{inspect(reason)}")
        {:error, :token_exchange_failed}
    end
  end

  defp request_userinfo(access_token) do
    with {:ok, response} <-
           Req.get(userinfo_endpoint(),
             headers: [{"authorization", "Bearer " <> access_token}]
           ),
         {:ok, body} <- decode_success_body(response, :userinfo_failed),
         {:ok, profile} <- extract_profile(body) do
      {:ok, profile}
    else
      {:error, reason} ->
        Logger.warning("Google userinfo request failed: #{inspect(reason)}")
        {:error, :userinfo_failed}
    end
  end

  defp decode_success_body(%Req.Response{status: status, body: body}, _)
       when status in 200..299 do
    if is_map(body), do: {:ok, body}, else: {:error, :invalid_body}
  end

  defp decode_success_body(%Req.Response{status: status, body: body}, fallback_error) do
    {:error, {:http_status, status, body, fallback_error}}
  end

  defp extract_profile(%{} = body) do
    email = normalize_binary(Map.get(body, "email"))
    sub = normalize_binary(Map.get(body, "sub"))
    email_verified? = truthy?(Map.get(body, "email_verified"))

    if email != "" and sub != "" do
      {:ok, %{email: email, email_verified: email_verified?, sub: sub}}
    else
      {:error, :invalid_profile}
    end
  end

  defp truthy?(value), do: value in [true, "true", 1, "1"]

  defp normalize_binary(value) when is_binary(value), do: String.trim(value)
  defp normalize_binary(_value), do: ""

  defp fetch_config(key) do
    case Application.get_env(:organizer, __MODULE__, []) |> Keyword.get(key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :missing_configuration}
    end
  end

  defp authorize_endpoint do
    Application.get_env(:organizer, __MODULE__, [])
    |> Keyword.get(:authorize_endpoint, @default_authorize_endpoint)
  end

  defp token_endpoint do
    Application.get_env(:organizer, __MODULE__, [])
    |> Keyword.get(:token_endpoint, @default_token_endpoint)
  end

  defp userinfo_endpoint do
    Application.get_env(:organizer, __MODULE__, [])
    |> Keyword.get(:userinfo_endpoint, @default_userinfo_endpoint)
  end
end
