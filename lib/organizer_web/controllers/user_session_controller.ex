defmodule OrganizerWeb.UserSessionController do
  use OrganizerWeb, :controller

  alias Organizer.Accounts
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
      |> put_flash(:info, "Que bom ter você de volta!")
      |> UserAuth.log_in_user(user, user_params)
    else
      form = Phoenix.Component.to_form(user_params, as: "user")

      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "E-mail ou senha inválidos")
      |> render(:new, form: form, invite_pending?: invite_pending?(conn))
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Você saiu com sucesso.")
    |> UserAuth.log_out_user()
  end

  defp invite_pending?(conn) do
    case get_session(conn, :user_return_to) do
      "/account-links/accept/" <> _token -> true
      _ -> false
    end
  end
end
