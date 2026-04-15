defmodule OrganizerWeb.API.V1.FixedCostControllerTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures

  describe "unauthenticated access" do
    test "returns 401 on list", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/fixed-costs")

      assert conn.status == 401

      assert json_response(conn, 401) == %{
               "error" => %{"code" => "unauthorized", "message" => "authentication required"}
             }
    end
  end

  describe "authenticated access" do
    setup :register_and_log_in_user

    test "creates and lists fixed costs", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/fixed-costs", %{
          "fixed_cost" => %{
            "name" => "Internet",
            "amount_cents" => 9990,
            "billing_day" => 10,
            "starts_on" => Date.to_iso8601(Date.utc_today())
          }
        })

      assert %{"data" => %{"id" => id, "name" => "Internet"}} = json_response(conn, 201)

      conn = get(recycle(conn), ~p"/api/v1/fixed-costs")
      assert %{"data" => costs} = json_response(conn, 200)
      assert Enum.any?(costs, &(&1["id"] == id))
    end

    test "returns validation error when payload is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/fixed-costs", %{
          "fixed_cost" => %{
            "name" => "x",
            "amount_cents" => 0,
            "billing_day" => 45
          }
        })

      assert %{"error" => %{"code" => "validation_error", "details" => details}} =
               json_response(conn, 422)

      assert Map.has_key?(details, "name")
      assert Map.has_key?(details, "amount_cents")
      assert Map.has_key?(details, "billing_day")
    end

    test "enforces user data isolation for show update and delete", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/fixed-costs", %{
          "fixed_cost" => %{
            "name" => "Plano saude",
            "amount_cents" => 15000,
            "billing_day" => 5
          }
        })

      %{"data" => %{"id" => id}} = json_response(conn, 201)

      other_user_conn =
        build_conn()
        |> log_in_user(user_fixture())

      show_conn = get(other_user_conn, ~p"/api/v1/fixed-costs/#{id}")
      assert json_response(show_conn, 404)["error"]["code"] == "not_found"

      update_conn =
        put(other_user_conn, ~p"/api/v1/fixed-costs/#{id}", %{
          "fixed_cost" => %{"name" => "invadir", "amount_cents" => 100, "billing_day" => 1}
        })

      assert json_response(update_conn, 404)["error"]["code"] == "not_found"

      delete_conn = delete(other_user_conn, ~p"/api/v1/fixed-costs/#{id}")
      assert json_response(delete_conn, 404)["error"]["code"] == "not_found"
    end
  end
end
