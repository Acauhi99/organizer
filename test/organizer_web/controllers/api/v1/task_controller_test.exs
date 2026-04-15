defmodule OrganizerWeb.API.V1.TaskControllerTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures

  describe "unauthenticated access" do
    test "returns 401 on list", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/tasks")

      assert conn.status == 401

      assert json_response(conn, 401) == %{
               "error" => %{"code" => "unauthorized", "message" => "authentication required"}
             }
    end
  end

  describe "authenticated access" do
    setup :register_and_log_in_user

    test "creates and lists tasks", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/tasks", %{
          "task" => %{
            "title" => "Fechar planejamento",
            "priority" => "high",
            "due_on" => Date.to_iso8601(Date.utc_today())
          }
        })

      assert %{"data" => %{"id" => id, "title" => "Fechar planejamento"}} =
               json_response(conn, 201)

      conn = get(recycle(conn), ~p"/api/v1/tasks")
      assert %{"data" => tasks} = json_response(conn, 200)
      assert Enum.any?(tasks, &(&1["id"] == id))
    end

    test "enforces user data isolation for show update and delete", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/tasks", %{
          "task" => %{"title" => "Task do usuario A", "priority" => "medium"}
        })

      %{"data" => %{"id" => id}} = json_response(conn, 201)

      other_user_conn =
        build_conn()
        |> log_in_user(user_fixture())

      show_conn = get(other_user_conn, ~p"/api/v1/tasks/#{id}")
      assert json_response(show_conn, 404)["error"]["code"] == "not_found"

      update_conn =
        put(other_user_conn, ~p"/api/v1/tasks/#{id}", %{"task" => %{"title" => "invasao"}})

      assert json_response(update_conn, 404)["error"]["code"] == "not_found"

      delete_conn = delete(other_user_conn, ~p"/api/v1/tasks/#{id}")
      assert json_response(delete_conn, 404)["error"]["code"] == "not_found"
    end
  end
end
