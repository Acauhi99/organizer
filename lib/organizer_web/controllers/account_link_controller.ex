defmodule OrganizerWeb.AccountLinkController do
  use OrganizerWeb, :controller

  alias Organizer.SharedFinance
  alias OrganizerWeb.FlashFeedback

  def accept(conn, %{"token" => token}) do
    case conn.assigns.current_scope do
      %{user: %{}} = scope ->
        accept_invite_for_authenticated_user(conn, scope, token)

      _ ->
        conn
        |> put_session(:user_return_to, current_path(conn))
        |> info_feedback(
          "Faça login ou crie sua conta para aceitar o convite",
          "Entre e você será redirecionado automaticamente para concluir o aceite"
        )
        |> redirect(to: ~p"/users/log-in")
    end
  end

  defp accept_invite_for_authenticated_user(conn, scope, token) do
    case SharedFinance.accept_invite(scope, token) do
      {:ok, link} ->
        conn
        |> info_feedback(
          "Compartilhamento estabelecido com sucesso",
          "Revise os detalhes do vínculo e siga para os lançamentos compartilhados"
        )
        |> redirect(to: ~p"/account-links/#{link.id}")

      {:error, :invite_invalid} ->
        conn
        |> error_feedback(
          "Convite inválido ou expirado",
          "Solicite um novo convite e tente novamente"
        )
        |> redirect(to: ~p"/account-links/invite")

      {:error, :self_invite_not_allowed} ->
        conn
        |> error_feedback(
          "Você não pode aceitar o próprio convite",
          "Gere um novo convite para a outra conta"
        )
        |> redirect(to: ~p"/account-links/invite")

      {:error, :link_already_exists} ->
        conn
        |> info_feedback(
          "Este compartilhamento já está ativo",
          "Acesse a lista de vínculos para continuar o gerenciamento"
        )
        |> redirect(to: ~p"/account-links")
    end
  end

  defp info_feedback(conn, happened, next_step) do
    put_flash(conn, :info, FlashFeedback.compose(happened, next_step))
  end

  defp error_feedback(conn, happened, next_step) do
    put_flash(conn, :error, FlashFeedback.compose(happened, next_step))
  end
end
