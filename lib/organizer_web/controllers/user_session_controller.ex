defmodule OrganizerWeb.UserSessionController do
  use OrganizerWeb, :controller

  alias Organizer.Accounts
  alias OrganizerWeb.FlashFeedback
  alias OrganizerWeb.UserAuth

  def new(conn, _params) do
    email = get_in(conn.assigns, [:current_scope, Access.key(:user), Access.key(:email)])
    form = Phoenix.Component.to_form(%{"email" => email}, as: "user")
    invite_pending? = invite_pending?(conn)

    render(conn, :new, form: form, invite_pending?: invite_pending?)
  end

  def create(conn, %{"user" => user_params}) do
    email = Map.get(user_params, "email", "")
    password = Map.get(user_params, "password", "")

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> info_feedback(
        "Que bom ter você de volta",
        "Siga para o painel e retome sua rotina"
      )
      |> UserAuth.log_in_user(user, user_params)
    else
      form = Phoenix.Component.to_form(user_params, as: "user")

      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> error_feedback(
        "E-mail ou senha inválidos",
        "Revise os dados e tente novamente"
      )
      |> render(:new, form: form, invite_pending?: invite_pending?(conn))
    end
  end

  def delete(conn, _params) do
    conn
    |> info_feedback("Você saiu com sucesso", "Volte quando quiser continuar sua organização")
    |> UserAuth.log_out_user()
  end

  defp invite_pending?(conn) do
    case get_session(conn, :user_return_to) do
      "/account-links/accept/" <> _token -> true
      _ -> false
    end
  end

  defp info_feedback(conn, happened, next_step) do
    put_flash(conn, :info, FlashFeedback.compose(happened, next_step))
  end

  defp error_feedback(conn, happened, next_step) do
    put_flash(conn, :error, FlashFeedback.compose(happened, next_step))
  end
end
