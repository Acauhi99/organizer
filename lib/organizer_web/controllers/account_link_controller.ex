defmodule OrganizerWeb.AccountLinkController do
  use OrganizerWeb, :controller

  alias Organizer.SharedFinance

  def accept(conn, %{"token" => token}) do
    case conn.assigns.current_scope do
      %{user: %{}} = scope ->
        accept_invite_for_authenticated_user(conn, scope, token)

      _ ->
        conn
        |> put_session(:user_return_to, current_path(conn))
        |> put_flash(:info, "Faça login ou crie sua conta para aceitar o convite.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  defp accept_invite_for_authenticated_user(conn, scope, token) do
    case SharedFinance.accept_invite(scope, token) do
      {:ok, link} ->
        conn
        |> put_flash(:info, "Compartilhamento estabelecido com sucesso.")
        |> redirect(to: ~p"/account-links/#{link.id}")

      {:error, :invite_invalid} ->
        conn
        |> put_flash(:error, "Convite inválido ou expirado.")
        |> redirect(to: ~p"/account-links/invite")

      {:error, :self_invite_not_allowed} ->
        conn
        |> put_flash(:error, "Você não pode aceitar o próprio convite.")
        |> redirect(to: ~p"/account-links/invite")

      {:error, :link_already_exists} ->
        conn
        |> put_flash(:info, "Este compartilhamento já está ativo.")
        |> redirect(to: ~p"/account-links")
    end
  end
end
