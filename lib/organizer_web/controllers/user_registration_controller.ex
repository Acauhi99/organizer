defmodule OrganizerWeb.UserRegistrationController do
  use OrganizerWeb, :controller

  alias Organizer.Accounts
  alias Organizer.Accounts.User
  alias OrganizerWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user_with_password(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Conta criada com sucesso. Bem-vindo!")
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
