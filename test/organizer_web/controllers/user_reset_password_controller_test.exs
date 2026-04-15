defmodule OrganizerWeb.UserResetPasswordControllerTest do
  use OrganizerWeb.ConnCase

  alias Organizer.Accounts
  alias Organizer.Repo
  alias Organizer.Accounts.UserToken
  import Organizer.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/reset-password" do
    test "renders forgot password page", %{conn: conn} do
      conn = get(conn, ~p"/users/reset-password")
      response = html_response(conn, 200)
      assert response =~ "Esqueceu sua senha?"
      assert response =~ ~p"/users/log-in"
    end

    test "redirects if already logged in", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> get(~p"/users/reset-password")
      assert redirected_to(conn) == ~p"/dashboard"
    end
  end

  describe "POST /users/reset-password" do
    @tag :capture_log
    test "sends reset password token", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/reset-password", %{
          "user" => %{"email" => user.email}
        })

      response = html_response(conn, 200)
      assert response =~ "Instrucoes enviadas"
      assert response =~ "Verifique sua caixa de entrada"
      assert response =~ "Se o e-mail estiver cadastrado"
      assert response =~ ~p"/users/log-in"

      assert Repo.get_by(UserToken, user_id: user.id, context: "reset_password")
    end

    @tag :capture_log
    test "does not send token if email is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/reset-password", %{
          "user" => %{"email" => "unknown@example.com"}
        })

      response = html_response(conn, 200)
      assert response =~ "Instrucoes enviadas"
      assert response =~ "Verifique sua caixa de entrada"
      assert response =~ "Se o e-mail estiver cadastrado"
      assert response =~ ~p"/users/log-in"

      refute Repo.get_by(UserToken, context: "reset_password")
    end
  end

  describe "GET /users/reset-password/:token" do
    setup %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{token: token}
    end

    test "renders reset password page", %{conn: conn, token: token} do
      conn = get(conn, ~p"/users/reset-password/#{token}")
      response = html_response(conn, 200)
      assert response =~ "Defina sua nova senha"
      assert response =~ "Salvar nova senha"
    end

    test "does not render reset password page with invalid token", %{conn: conn} do
      conn = get(conn, ~p"/users/reset-password/oops")
      assert redirected_to(conn) == ~p"/users/reset-password"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "O link para redefinir senha é inválido ou expirou"
    end
  end

  describe "PUT /users/reset-password/:token" do
    setup %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{token: token, user: user}
    end

    test "resets password once", %{conn: conn, token: token, user: user} do
      conn =
        put(conn, ~p"/users/reset-password/#{token}", %{
          "user" => %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Senha redefinida com sucesso"

      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")

      conn =
        put(conn, ~p"/users/reset-password/#{token}", %{
          "user" => %{
            "password" => "another valid password",
            "password_confirmation" => "another valid password"
          }
        })

      assert redirected_to(conn) == ~p"/users/reset-password"
      refute Accounts.get_user_by_email_and_password(user.email, "another valid password")
    end

    test "does not reset password on invalid data", %{conn: conn, token: token} do
      conn =
        put(conn, ~p"/users/reset-password/#{token}", %{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      response = html_response(conn, 200)
      assert response =~ "Defina sua nova senha"
      assert response =~ "should be at least 12 character(s)"
      assert response =~ "does not match password"
    end

    test "does not reset password with invalid token", %{conn: conn} do
      conn =
        put(conn, ~p"/users/reset-password/oops", %{
          "user" => %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(conn) == ~p"/users/reset-password"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "O link para redefinir senha é inválido ou expirou"
    end
  end
end
