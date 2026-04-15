defmodule OrganizerWeb.API.V1.GoalControllerTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures

  describe "unauthenticated access" do
    test "returns 401 on list", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/goals")

      assert conn.status == 401

      assert json_response(conn, 401) == %{
               "error" => %{"code" => "unauthorized", "message" => "authentication required"}
             }
    end
  end

  describe "authenticated access" do
    setup :register_and_log_in_user

    test "creates and lists goals", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/goals", %{
          "goal" => %{
            "title" => "Reserva de emergencia",
            "horizon" => "long",
            "target_value" => 100_000
          }
        })

      assert %{"data" => %{"id" => id, "title" => "Reserva de emergencia"}} =
               json_response(conn, 201)

      conn = get(recycle(conn), ~p"/api/v1/goals")
      assert %{"data" => goals} = json_response(conn, 200)
      assert Enum.any?(goals, &(&1["id"] == id))
    end

    test "enforces user data isolation for show update and delete", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/goals", %{
          "goal" => %{
            "title" => "Meta privada",
            "horizon" => "medium",
            "target_value" => 5000
          }
        })

      %{"data" => %{"id" => id}} = json_response(conn, 201)

      other_user_conn =
        build_conn()
        |> log_in_user(user_fixture())

      show_conn = get(other_user_conn, ~p"/api/v1/goals/#{id}")
      assert json_response(show_conn, 404)["error"]["code"] == "not_found"

      update_conn =
        put(other_user_conn, ~p"/api/v1/goals/#{id}", %{
          "goal" => %{"title" => "invadir", "horizon" => "short"}
        })

      assert json_response(update_conn, 404)["error"]["code"] == "not_found"

      delete_conn = delete(other_user_conn, ~p"/api/v1/goals/#{id}")
      assert json_response(delete_conn, 404)["error"]["code"] == "not_found"
    end
  end
end
