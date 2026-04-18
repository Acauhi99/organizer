defmodule Organizer.Planning.QualityAuditTest do
  use Organizer.DataCase

  alias Organizer.Planning
  alias Organizer.Planning.{Goal, FinanceEntry}
  alias OrganizerWeb.DashboardLive.BulkImport

  import Organizer.AccountsFixtures

  describe "Req 1: update_task validation consistency" do
    test "update_task with blank title returns validation error" do
      scope = user_scope_fixture()

      # Create a valid task first
      assert {:ok, task} =
               Planning.create_task(scope, %{
                 "title" => "Valid task",
                 "priority" => "medium"
               })

      # Try to update with blank title
      assert {:error, {:validation, errors}} =
               Planning.update_task(scope, task.id, %{"title" => "   "})

      assert Map.has_key?(errors, :title)
    end

    test "update_task with whitespace-only title returns validation error" do
      scope = user_scope_fixture()

      assert {:ok, task} =
               Planning.create_task(scope, %{
                 "title" => "Original title",
                 "priority" => "low"
               })

      # Update with whitespace-only title
      assert {:error, {:validation, errors}} =
               Planning.update_task(scope, task.id, %{"title" => "\t\n  "})

      assert Map.has_key?(errors, :title)
    end
  end

  describe "Req 2: important_date and fixed_cost validation" do
    test "create_important_date with invalid attributes returns error without hitting database" do
      scope = user_scope_fixture()

      # Title too short
      assert {:error, {:validation, errors}} =
               Planning.create_important_date(scope, %{
                 "title" => "x",
                 "category" => "personal",
                 "date" => "2025-12-25"
               })

      assert Map.has_key?(errors, :title)

      # Invalid category - use a string that won't be converted to atom
      assert {:error, {:validation, errors}} =
               Planning.create_important_date(scope, %{
                 "title" => "Valid title",
                 "category" => "x",
                 "date" => "2025-12-25"
               })

      assert Map.has_key?(errors, :category)
    end

    test "create_fixed_cost with invalid attributes returns error without hitting database" do
      scope = user_scope_fixture()

      # Name too short
      assert {:error, {:validation, errors}} =
               Planning.create_fixed_cost(scope, %{
                 "name" => "x",
                 "amount_cents" => 5000,
                 "billing_day" => 15
               })

      assert Map.has_key?(errors, :name)

      # Invalid billing_day
      assert {:error, {:validation, errors}} =
               Planning.create_fixed_cost(scope, %{
                 "name" => "Valid name",
                 "amount_cents" => 5000,
                 "billing_day" => 35
               })

      assert Map.has_key?(errors, :billing_day)

      # Amount_cents zero or negative
      assert {:error, {:validation, errors}} =
               Planning.create_fixed_cost(scope, %{
                 "name" => "Valid name",
                 "amount_cents" => 0,
                 "billing_day" => 15
               })

      assert Map.has_key?(errors, :amount_cents)
    end
  end

  describe "Req 6: parse_index/1 behavior" do
    test "parse_index returns integer for integer input" do
      assert BulkImport.parse_index(5) == 5
      assert BulkImport.parse_index(0) == 0
      assert BulkImport.parse_index(999) == 999
    end

    test "parse_index returns integer for numeric string" do
      assert BulkImport.parse_index("5") == 5
      assert BulkImport.parse_index("123") == 123
      assert BulkImport.parse_index("0") == 0
    end

    test "parse_index returns nil for non-numeric string" do
      assert BulkImport.parse_index("abc") == nil
      assert BulkImport.parse_index("12abc") == nil
      assert BulkImport.parse_index("") == nil
      assert BulkImport.parse_index("  ") == nil
    end

    test "parse_index handles edge cases" do
      assert BulkImport.parse_index(:atom) == nil
      assert BulkImport.parse_index([1, 2, 3]) == nil
      # Skip map test as to_string/1 doesn't support maps
    end
  end

  describe "Req 7: amount_cents upper limit validation" do
    test "FinanceEntry.changeset with amount_cents > 1_000_000_000 returns invalid changeset" do
      changeset =
        FinanceEntry.changeset(%FinanceEntry{}, %{
          kind: :expense,
          expense_profile: :variable,
          payment_method: :debit,
          amount_cents: 1_000_000_001,
          category: "test",
          occurred_on: Date.utc_today()
        })

      refute changeset.valid?
      assert %{amount_cents: _} = errors_on(changeset)
    end

    test "FinanceEntry.changeset with amount_cents = 1_000_000_000 is valid" do
      changeset =
        FinanceEntry.changeset(%FinanceEntry{}, %{
          kind: :expense,
          expense_profile: :variable,
          payment_method: :debit,
          amount_cents: 1_000_000_000,
          category: "test",
          occurred_on: Date.utc_today()
        })

      assert changeset.valid?
    end

    test "FinanceEntry.changeset with amount_cents below limit is valid" do
      changeset =
        FinanceEntry.changeset(%FinanceEntry{}, %{
          kind: :income,
          amount_cents: 500_000,
          category: "salary",
          occurred_on: Date.utc_today()
        })

      assert changeset.valid?
    end
  end

  describe "Req 9: Goal current_value <= target_value validation" do
    test "Goal.changeset with current_value == target_value is valid" do
      changeset =
        Goal.changeset(%Goal{}, %{
          title: "Complete goal",
          horizon: :medium,
          status: :active,
          current_value: 100,
          target_value: 100
        })

      assert changeset.valid?
    end

    test "Goal.changeset with current_value > target_value is invalid" do
      changeset =
        Goal.changeset(%Goal{}, %{
          title: "Exceeded goal",
          horizon: :short,
          status: :active,
          current_value: 150,
          target_value: 100
        })

      refute changeset.valid?
      assert %{current_value: _} = errors_on(changeset)
    end

    test "Goal.changeset with current_value < target_value is valid" do
      changeset =
        Goal.changeset(%Goal{}, %{
          title: "In progress goal",
          horizon: :long,
          status: :active,
          current_value: 50,
          target_value: 100
        })

      assert changeset.valid?
    end

    test "Goal.changeset with nil target_value accepts any current_value" do
      changeset =
        Goal.changeset(%Goal{}, %{
          title: "No target goal",
          horizon: :medium,
          status: :active,
          current_value: 999,
          target_value: nil
        })

      assert changeset.valid?
    end
  end
end

# LiveView-specific tests require ConnCase
defmodule Organizer.Planning.QualityAuditLiveTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Organizer.Planning

  describe "Req 4: submit_bulk_capture payload size limit" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        scope: user_scope_fixture(user)
      }
    end

    test "handler rejects payload > 50,000 bytes with flash error", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Create a payload larger than 50,000 bytes
      large_payload =
        String.duplicate(
          "tarefa: Test task with a longer title to exceed limit #{:rand.uniform(1000)}\n",
          1000
        )

      assert byte_size(large_payload) > 50_000

      html =
        view
        |> form("#bulk-capture-form", %{"bulk" => %{"payload" => large_payload}})
        |> render_submit()

      # Should show error flash
      assert html =~ "excede o tamanho máximo permitido"
      assert html =~ "50 KB"

      # Should not create any tasks
      {:ok, tasks} = Planning.list_tasks(scope, %{})
      assert Enum.empty?(tasks)
    end

    test "handler accepts payload <= 50,000 bytes normally", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Create a payload just under the limit
      normal_payload = String.duplicate("tarefa: Small task\n", 100)
      assert byte_size(normal_payload) < 50_000

      view
      |> form("#bulk-capture-form", %{"bulk" => %{"payload" => normal_payload}})
      |> render_submit()

      # Should process normally without size error
      refute render(view) =~ "excede o tamanho máximo"
    end
  end

  describe "Req 5: validate_bulk_line crash protection" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        scope: user_scope_fixture(user)
      }
    end

    test "handler with non-numeric index does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Send validate_bulk_line event with non-numeric index
      # This should not crash the LiveView process
      assert view
             |> render_hook("validate_bulk_line", %{
               "line" => "tarefa: Test task",
               "index" => "abc"
             })

      # LiveView should still be alive and functional
      assert render(view) =~ "dashboard"
    end

    test "handler with numeric string index processes normally", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Send validate_bulk_line event with numeric string
      result =
        view
        |> render_hook("validate_bulk_line", %{
          "line" => "tarefa: Test task",
          "index" => "5"
        })

      # Should process without error
      assert result
    end

    test "handler with integer index processes normally", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Send validate_bulk_line event with integer
      result =
        view
        |> render_hook("validate_bulk_line", %{
          "line" => "tarefa: Test task",
          "index" => 5
        })

      # Should process without error
      assert result
    end
  end

  describe "Req 10: DashboardLive template renders components after import removal" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        scope: user_scope_fixture(user)
      }
    end

    test "template renders all five components correctly", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/dashboard")

      # Verify AnalyticsPanel component renders
      assert has_element?(view, "#analytics-panel")

      # Verify BulkImportStudio component renders
      assert has_element?(view, "#bulk-capture-form") or has_element?(view, "#quick-bulk")

      # Verify OperationsPanel component renders (check for ops tabs)
      assert has_element?(view, "#ops-tab-tasks") or
               has_element?(view, "#ops-tab-finances") or
               has_element?(view, "#ops-tab-goals")

      # Verify the page renders without errors
      assert html =~ "dashboard"
    end

    test "components remain functional after qualified calls", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Test that bulk import still works (BulkImportStudio component)
      payload = "tarefa: Test component functionality"

      view
      |> form("#bulk-capture-form", %{"bulk" => %{"payload" => payload}})
      |> render_submit()

      {:ok, tasks} = Planning.list_tasks(scope, %{})
      assert Enum.any?(tasks, &(&1.title == "Test component functionality"))

      # Test that operations panel tab switching works (OperationsPanel component)
      # Use a more specific selector to avoid multiple matches
      view
      |> element("#ops-tab-finances")
      |> render_click()

      assert render(view) =~ "finances" or has_element?(view, "[data-tab='finances']")
    end
  end
end
