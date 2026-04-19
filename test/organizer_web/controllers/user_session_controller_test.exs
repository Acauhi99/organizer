defmodule OrganizerWeb.UserSessionControllerTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/log-in" do
    test "renders login page", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in")
      response = html_response(conn, 200)
      assert response =~ "Entrar"
      assert response =~ ~p"/users/register"
      assert response =~ "Acesse seu painel para revisar tarefas da semana"
    end

    test "renders login page with email filled in (sudo mode)", %{conn: conn, user: user} do
      html =
        conn
        |> log_in_user(user)
        |> get(~p"/users/log-in")
        |> html_response(200)

      assert html =~ "Reautentique para continuar com segurança"
      refute html =~ "Cadastrar"
      assert html =~ ~s(name="user[email]")
      assert html =~ ~s(value="#{user.email}")
    end

    test "renders invite context when there is a pending account-link accept", %{conn: conn} do
      html =
        conn
        |> init_test_session(user_return_to: "/account-links/accept/invite-token-123")
        |> get(~p"/users/log-in")
        |> html_response(200)

      assert html =~ "Entre para concluir o vínculo"
      assert html =~ "redirecionado automaticamente"
    end
  end

  describe "POST /users/log-in" do
    test "logs the user in", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/dashboard"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/dashboard")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_organizer_user_remember_me"]
      assert redirected_to(conn) == ~p"/dashboard"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Que bom ter você de volta!"
    end

    test "emits error message with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      response = html_response(conn, 200)
      assert response =~ "Entrar"
      assert response =~ "E-mail ou senha inválidos"
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Você saiu com sucesso"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Você saiu com sucesso"
    end
  end
end
