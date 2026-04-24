defmodule OrganizerWeb.UserRegistrationControllerTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures

  describe "GET /users/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      response = html_response(conn, 200)
      assert response =~ "Criar conta"
      assert response =~ ~p"/users/log-in"
      assert response =~ ~p"/users/register"
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register")

      assert redirected_to(conn) == ~p"/finances"
    end

    test "renders invite context when there is a pending account-link accept", %{conn: conn} do
      html =
        conn
        |> init_test_session(user_return_to: "/account-links/accept/invite-token-123")
        |> get(~p"/users/register")
        |> html_response(200)

      assert html =~ "Crie sua conta para aceitar o convite"
      assert html =~ "compartilhamento ativo"
    end
  end

  describe "POST /users/register" do
    @tag :capture_log
    test "creates account and logs in immediately", %{conn: conn} do
      email = unique_user_email()
      password = valid_user_password()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{
            "email" => email,
            "password" => password,
            "password_confirmation" => password
          }
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/finances"

      assert conn.assigns.flash["info"] =~
               "Conta criada com sucesso"
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "Criar conta"
      assert response =~ "must have the @ sign and no spaces"
    end
  end
end
