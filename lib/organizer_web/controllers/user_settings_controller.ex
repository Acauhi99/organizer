defmodule OrganizerWeb.UserSettingsController do
  use OrganizerWeb, :controller

  alias Organizer.Accounts
  alias OrganizerWeb.UserAuth

  import OrganizerWeb.UserAuth, only: [require_sudo_mode: 2]
  import Phoenix.Component, only: [to_form: 2]

  plug :require_sudo_mode
  plug :assign_email_and_password_changesets

  def edit(conn, _params) do
    render(conn, :edit)
  end

  def update(conn, %{"action" => "update_email"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        conn
        |> put_flash(
          :info,
          "Enviamos para o novo endereço um link para confirmar a alteração de e-mail."
        )
        |> redirect(to: ~p"/users/settings")

      changeset ->
        render(conn, :edit,
          email_form: to_form(Map.put(changeset, :action, :validate), as: :user)
        )
    end
  end

  def update(conn, %{"action" => "update_password"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.update_user_password(user, user_params) do
      {:ok, {user, _}} ->
        conn
        |> put_flash(:info, "Senha atualizada com sucesso.")
        |> put_session(:user_return_to, ~p"/users/settings")
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, :edit, password_form: to_form(changeset, as: :user))
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_scope.user, token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "E-mail alterado com sucesso.")
        |> redirect(to: ~p"/users/settings")

      {:error, _} ->
        conn
        |> put_flash(:error, "O link de alteração de e-mail é inválido ou expirou.")
        |> redirect(to: ~p"/users/settings")
    end
  end

  defp assign_email_and_password_changesets(conn, _opts) do
    user = conn.assigns.current_scope.user

    conn
    |> assign(:email_form, to_form(Accounts.change_user_email(user), as: :user))
    |> assign(:password_form, to_form(Accounts.change_user_password(user), as: :user))
  end
end
