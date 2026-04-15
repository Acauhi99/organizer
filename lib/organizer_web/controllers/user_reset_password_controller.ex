defmodule OrganizerWeb.UserResetPasswordController do
  use OrganizerWeb, :controller

  alias Organizer.Accounts

  def new(conn, _params) do
    form = Phoenix.Component.to_form(%{}, as: "user")
    render(conn, :new, form: form, reset_email_sent?: false)
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(user, fn token ->
        url(~p"/users/reset-password/#{token}")
      end)
    end

    form = Phoenix.Component.to_form(%{}, as: "user")

    render(conn, :new,
      form: form,
      reset_email_sent?: true
    )
  end

  def edit(conn, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      form = Phoenix.Component.to_form(Accounts.change_user_password(user), as: "user")
      render(conn, :edit, form: form, token: token)
    else
      conn
      |> put_flash(:error, "O link para redefinir senha é inválido ou expirou.")
      |> redirect(to: ~p"/users/reset-password")
    end
  end

  def update(conn, %{"token" => token, "user" => user_params}) do
    case Accounts.get_user_by_reset_password_token(token) do
      nil ->
        conn
        |> put_flash(:error, "O link para redefinir senha é inválido ou expirou.")
        |> redirect(to: ~p"/users/reset-password")

      user ->
        case Accounts.reset_user_password(user, user_params) do
          {:ok, _user} ->
            conn
            |> put_flash(:info, "Senha redefinida com sucesso. Faça login para continuar.")
            |> redirect(to: ~p"/users/log-in")

          {:error, changeset} ->
            form = Phoenix.Component.to_form(changeset, as: "user")
            render(conn, :edit, form: form, token: token)
        end
    end
  end
end
