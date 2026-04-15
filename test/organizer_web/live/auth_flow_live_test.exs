defmodule OrganizerWeb.AuthFlowLiveTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Organizer.Accounts

  describe "auth end-to-end" do
    test "registers with password, reaches dashboard live, and logs out", %{conn: conn} do
      email = unique_user_email()
      password = valid_user_password()

      registration_conn =
        post(conn, ~p"/users/register", %{
          "user" =>
            valid_user_attributes(%{
              email: email,
              password: password,
              password_confirmation: password
            })
        })

      assert get_session(registration_conn, :user_token)
      assert redirected_to(registration_conn) == ~p"/dashboard"

      user = Accounts.get_user_by_email(email)
      refute is_nil(user)
      assert user.confirmed_at

      assert {:ok, _view, html} = live(recycle(registration_conn), ~p"/dashboard")
      assert html =~ "Painel Diário"

      logout_conn = delete(recycle(registration_conn), ~p"/users/log-out")
      assert redirected_to(logout_conn) == ~p"/"
      refute get_session(logout_conn, :user_token)

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(recycle(logout_conn), ~p"/dashboard")
    end

    test "forces reauthentication and restores intended path", %{conn: conn} do
      user = user_fixture() |> set_password()

      stale_conn =
        log_in_user(conn, user, token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute))

      redirected_conn = get(stale_conn, ~p"/users/settings")
      assert redirected_to(redirected_conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(redirected_conn.assigns.flash, :error) ==
               "Você precisa se reautenticar para acessar esta página."

      reauth_conn =
        post(recycle(redirected_conn), ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(reauth_conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(reauth_conn.assigns.flash, :info) =~ "Que bom ter você de volta!"

      settings_conn = get(recycle(reauth_conn), ~p"/users/settings")
      assert html_response(settings_conn, 200) =~ "Configurações da conta"
    end

    test "rejects invalid credentials and keeps user logged out", %{conn: conn} do
      user = user_fixture() |> set_password()

      login_conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => "senha-errada"}
        })

      refute get_session(login_conn, :user_token)
      assert html_response(login_conn, 200) =~ "E-mail ou senha inválidos"

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(recycle(login_conn), ~p"/dashboard")
    end
  end
end
