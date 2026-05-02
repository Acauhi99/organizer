defmodule OrganizerWeb.UserSettingsController do
  use OrganizerWeb, :controller

  alias Organizer.Accounts
  alias OrganizerWeb.FlashFeedback
  alias OrganizerWeb.UserAuth

  import OrganizerWeb.UserAuth, only: [require_sudo_mode: 2]
  import Phoenix.Component, only: [to_form: 2]

  plug :require_sudo_mode when action in [:update]
  plug :assign_password_form

  def edit(conn, _params) do
    render(conn, :edit)
  end

  def update(conn, %{"action" => "update_password"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.update_user_password(user, user_params) do
      {:ok, {user, _}} ->
        conn
        |> info_feedback(
          "Senha atualizada com sucesso",
          "Use a nova senha no próximo acesso"
        )
        |> put_session(:user_return_to, ~p"/users/settings")
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, :edit, password_form: to_form(changeset, as: :user))
    end
  end

  defp assign_password_form(conn, _opts) do
    user = conn.assigns.current_scope.user

    assign(conn, :password_form, to_form(Accounts.change_user_password(user), as: :user))
  end

  defp info_feedback(conn, happened, next_step) do
    put_flash(conn, :info, FlashFeedback.compose(happened, next_step))
  end
end
