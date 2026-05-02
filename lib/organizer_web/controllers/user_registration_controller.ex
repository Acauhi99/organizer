defmodule OrganizerWeb.UserRegistrationController do
  use OrganizerWeb, :controller

  alias Organizer.Accounts
  alias Organizer.Accounts.User
  alias OrganizerWeb.FlashFeedback
  alias OrganizerWeb.UserAuth

  import Phoenix.Component, only: [to_form: 2]

  def new(conn, _params) do
    form =
      %User{}
      |> Accounts.change_user_registration()
      |> to_form(as: :user)

    render(conn, :new, form: form, invite_pending?: invite_pending?(conn))
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user_with_password(user_params) do
      {:ok, user} ->
        conn
        |> info_feedback(
          "Conta criada com sucesso",
          "Você já pode começar a registrar seus lançamentos"
        )
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new,
          form: to_form(changeset, as: :user),
          invite_pending?: invite_pending?(conn)
        )
    end
  end

  defp invite_pending?(conn) do
    case Plug.Conn.get_session(conn, :user_return_to) do
      "/account-links/accept/" <> _token -> true
      _ -> false
    end
  end

  defp info_feedback(conn, happened, next_step) do
    put_flash(conn, :info, FlashFeedback.compose(happened, next_step))
  end
end
