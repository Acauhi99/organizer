defmodule OrganizerWeb.API.V1.FinanceEntryControllerTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures

  describe "unauthenticated access" do
    test "returns 401 on list", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/finance-entries")

      assert conn.status == 401

      assert json_response(conn, 401) == %{
               "error" => %{"code" => "unauthorized", "message" => "authentication required"}
             }
    end
  end

  describe "authenticated access" do
    setup :register_and_log_in_user

    test "creates and lists finance entries", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/finance-entries", %{
          "finance_entry" => %{
            "kind" => "expense",
            "amount_cents" => 12_500,
            "category" => "mercado",
            "occurred_on" => Date.to_iso8601(Date.utc_today())
          }
        })

      assert %{"data" => %{"id" => id, "category" => "mercado"}} =
               json_response(conn, 201)

      conn = get(recycle(conn), ~p"/api/v1/finance-entries")
      assert %{"data" => entries} = json_response(conn, 200)
      assert Enum.any?(entries, &(&1["id"] == id))
    end

    test "returns validation error when payload is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/finance-entries", %{
          "finance_entry" => %{
            "kind" => "expense",
            "amount_cents" => 0,
            "category" => "x",
            "occurred_on" => Date.to_iso8601(Date.utc_today())
          }
        })

      assert %{"error" => %{"code" => "validation_error", "details" => details}} =
               json_response(conn, 422)

      assert Map.has_key?(details, "amount_cents")
      assert Map.has_key?(details, "category")
    end

    test "enforces user data isolation for show update and delete", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/finance-entries", %{
          "finance_entry" => %{
            "kind" => "income",
            "amount_cents" => 20_000,
            "category" => "freela",
            "occurred_on" => Date.to_iso8601(Date.utc_today())
          }
        })

      %{"data" => %{"id" => id}} = json_response(conn, 201)

      other_user_conn =
        build_conn()
        |> log_in_user(user_fixture())

      show_conn = get(other_user_conn, ~p"/api/v1/finance-entries/#{id}")
      assert json_response(show_conn, 404)["error"]["code"] == "not_found"

      update_conn =
        put(other_user_conn, ~p"/api/v1/finance-entries/#{id}", %{
          "finance_entry" => %{
            "category" => "invadir",
            "kind" => "income",
            "amount_cents" => 1000
          }
        })

      assert json_response(update_conn, 404)["error"]["code"] == "not_found"

      delete_conn = delete(other_user_conn, ~p"/api/v1/finance-entries/#{id}")
      assert json_response(delete_conn, 404)["error"]["code"] == "not_found"
    end
  end
end
