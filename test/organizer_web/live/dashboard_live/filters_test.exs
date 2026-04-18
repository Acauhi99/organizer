defmodule OrganizerWeb.DashboardLive.FiltersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias OrganizerWeb.DashboardLive.Filters

  # ---------------------------------------------------------------------------
  # default_*_filters/0
  # ---------------------------------------------------------------------------

  describe "default_task_filters/0" do
    test "returns expected map" do
      assert Filters.default_task_filters() == %{
               status: "all",
               priority: "all",
               days: "14",
               q: ""
             }
    end
  end

  describe "default_finance_filters/0" do
    test "returns expected map" do
      assert Filters.default_finance_filters() == %{
               days: "30",
               kind: "all",
               expense_profile: "all",
               payment_method: "all",
               category: "",
               q: "",
               min_amount_cents: "",
               max_amount_cents: ""
             }
    end
  end

  describe "default_goal_filters/0" do
    test "returns expected map" do
      assert Filters.default_goal_filters() == %{
               status: "all",
               horizon: "all",
               days: "365",
               progress_min: "",
               progress_max: "",
               q: ""
             }
    end
  end

  describe "default_analytics_filters/0" do
    test "returns expected map" do
      assert Filters.default_analytics_filters() == %{
               days: "30",
               planned_capacity: "10"
             }
    end
  end

  # ---------------------------------------------------------------------------
  # normalize_*_filters/1
  # ---------------------------------------------------------------------------

  describe "normalize_task_filters/1" do
    test "keeps present string-keyed values" do
      result =
        Filters.normalize_task_filters(%{
          "status" => "todo",
          "priority" => "high",
          "days" => "7",
          "q" => "test"
        })

      assert result == %{status: "todo", priority: "high", days: "7", q: "test"}
    end

    test "drops nil values" do
      result = Filters.normalize_task_filters(%{"status" => nil, "priority" => "low"})
      assert result == %{priority: "low"}
    end

    test "drops empty string values" do
      result = Filters.normalize_task_filters(%{"status" => "all", "q" => ""})
      assert result == %{status: "all"}
    end

    test "returns empty map when all values are nil or empty" do
      result = Filters.normalize_task_filters(%{"status" => nil, "q" => ""})
      assert result == %{}
    end

    test "returns empty map for empty input" do
      assert Filters.normalize_task_filters(%{}) == %{}
    end
  end

  describe "normalize_finance_filters/1" do
    test "keeps present string-keyed values" do
      result =
        Filters.normalize_finance_filters(%{
          "days" => "7",
          "kind" => "income",
          "expense_profile" => "fixed",
          "payment_method" => "credit",
          "category" => "food",
          "q" => "market",
          "min_amount_cents" => "100",
          "max_amount_cents" => "5000"
        })

      assert result == %{
               days: "7",
               kind: "income",
               expense_profile: "fixed",
               payment_method: "credit",
               category: "food",
               q: "market",
               min_amount_cents: "100",
               max_amount_cents: "5000"
             }
    end

    test "drops nil and empty string values" do
      result = Filters.normalize_finance_filters(%{"days" => "30", "kind" => nil, "q" => ""})
      assert result == %{days: "30"}
    end

    test "returns empty map for empty input" do
      assert Filters.normalize_finance_filters(%{}) == %{}
    end
  end

  describe "normalize_goal_filters/1" do
    test "keeps present string-keyed values" do
      result =
        Filters.normalize_goal_filters(%{
          "status" => "active",
          "horizon" => "short",
          "days" => "30",
          "progress_min" => "10",
          "progress_max" => "90",
          "q" => "health"
        })

      assert result == %{
               status: "active",
               horizon: "short",
               days: "30",
               progress_min: "10",
               progress_max: "90",
               q: "health"
             }
    end

    test "drops nil and empty string values" do
      result = Filters.normalize_goal_filters(%{"status" => "all", "q" => nil})
      assert result == %{status: "all"}
    end

    test "returns empty map for empty input" do
      assert Filters.normalize_goal_filters(%{}) == %{}
    end
  end

  describe "normalize_analytics_filters/1" do
    test "keeps present string-keyed values" do
      result = Filters.normalize_analytics_filters(%{"days" => "90", "planned_capacity" => "20"})
      assert result == %{days: "90", planned_capacity: "20"}
    end

    test "drops nil and empty string values" do
      result = Filters.normalize_analytics_filters(%{"days" => nil, "planned_capacity" => ""})
      assert result == %{}
    end

    test "returns empty map for empty input" do
      assert Filters.normalize_analytics_filters(%{}) == %{}
    end
  end

  # ---------------------------------------------------------------------------
  # sanitize_task_filters/1
  # ---------------------------------------------------------------------------

  describe "sanitize_task_filters/1" do
    test "keeps valid status values" do
      for status <- ["all", "todo", "in_progress", "done"] do
        result = Filters.sanitize_task_filters(%{status: status})
        assert result.status == status
      end
    end

    test "resets invalid status to 'all'" do
      result = Filters.sanitize_task_filters(%{status: "invalid"})
      assert result.status == "all"
    end

    test "keeps valid priority values" do
      for priority <- ["all", "low", "medium", "high"] do
        result = Filters.sanitize_task_filters(%{priority: priority})
        assert result.priority == priority
      end
    end

    test "resets invalid priority to 'all'" do
      result = Filters.sanitize_task_filters(%{priority: "urgent"})
      assert result.priority == "all"
    end

    test "keeps valid days values" do
      for days <- ["7", "14", "30"] do
        result = Filters.sanitize_task_filters(%{days: days})
        assert result.days == days
      end
    end

    test "resets invalid days to '14'" do
      result = Filters.sanitize_task_filters(%{days: "999"})
      assert result.days == "14"
    end

    test "uses defaults when keys are absent" do
      result = Filters.sanitize_task_filters(%{})
      assert result.status == "all"
      assert result.priority == "all"
      assert result.days == "14"
      assert result.q == ""
    end

    test "trims q string" do
      result = Filters.sanitize_task_filters(%{q: "  hello  "})
      assert result.q == "hello"
    end

    test "resets non-binary q to empty string" do
      result = Filters.sanitize_task_filters(%{q: 123})
      assert result.q == ""
    end
  end

  # ---------------------------------------------------------------------------
  # sanitize_finance_filters/1
  # ---------------------------------------------------------------------------

  describe "sanitize_finance_filters/1" do
    test "keeps valid days values" do
      for days <- ["7", "30", "90"] do
        result = Filters.sanitize_finance_filters(%{days: days})
        assert result.days == days
      end
    end

    test "resets invalid days to '30'" do
      result = Filters.sanitize_finance_filters(%{days: "60"})
      assert result.days == "30"
    end

    test "keeps valid kind values" do
      for kind <- ["all", "income", "expense"] do
        result = Filters.sanitize_finance_filters(%{kind: kind})
        assert result.kind == kind
      end
    end

    test "resets invalid kind to 'all'" do
      result = Filters.sanitize_finance_filters(%{kind: "transfer"})
      assert result.kind == "all"
    end

    test "keeps valid expense_profile values" do
      for ep <- ["all", "fixed", "variable"] do
        result = Filters.sanitize_finance_filters(%{expense_profile: ep})
        assert result.expense_profile == ep
      end
    end

    test "resets invalid expense_profile to 'all'" do
      result = Filters.sanitize_finance_filters(%{expense_profile: "recurring"})
      assert result.expense_profile == "all"
    end

    test "keeps valid payment_method values" do
      for pm <- ["all", "credit", "debit"] do
        result = Filters.sanitize_finance_filters(%{payment_method: pm})
        assert result.payment_method == pm
      end
    end

    test "resets invalid payment_method to 'all'" do
      result = Filters.sanitize_finance_filters(%{payment_method: "pix"})
      assert result.payment_method == "all"
    end

    test "uses defaults when keys are absent" do
      result = Filters.sanitize_finance_filters(%{})
      assert result.days == "30"
      assert result.kind == "all"
      assert result.expense_profile == "all"
      assert result.payment_method == "all"
      assert result.category == ""
      assert result.q == ""
      assert result.min_amount_cents == ""
      assert result.max_amount_cents == ""
    end

    test "accepts valid integer string for min_amount_cents" do
      result = Filters.sanitize_finance_filters(%{min_amount_cents: "500"})
      assert result.min_amount_cents == "500"
    end

    test "resets negative min_amount_cents to empty string" do
      result = Filters.sanitize_finance_filters(%{min_amount_cents: "-10"})
      assert result.min_amount_cents == ""
    end

    test "resets non-numeric min_amount_cents to empty string" do
      result = Filters.sanitize_finance_filters(%{min_amount_cents: "abc"})
      assert result.min_amount_cents == ""
    end
  end

  # ---------------------------------------------------------------------------
  # sanitize_goal_filters/1
  # ---------------------------------------------------------------------------

  describe "sanitize_goal_filters/1" do
    test "keeps valid status values" do
      for status <- ["all", "active", "paused", "done"] do
        result = Filters.sanitize_goal_filters(%{status: status})
        assert result.status == status
      end
    end

    test "resets invalid status to 'all'" do
      result = Filters.sanitize_goal_filters(%{status: "archived"})
      assert result.status == "all"
    end

    test "keeps valid horizon values" do
      for horizon <- ["all", "short", "medium", "long"] do
        result = Filters.sanitize_goal_filters(%{horizon: horizon})
        assert result.horizon == horizon
      end
    end

    test "resets invalid horizon to 'all'" do
      result = Filters.sanitize_goal_filters(%{horizon: "forever"})
      assert result.horizon == "all"
    end

    test "uses defaults when keys are absent" do
      result = Filters.sanitize_goal_filters(%{})
      assert result.status == "all"
      assert result.horizon == "all"
      assert result.days == "365"
      assert result.progress_min == ""
      assert result.progress_max == ""
      assert result.q == ""
    end
  end

  # ---------------------------------------------------------------------------
  # sanitize_analytics_filters/1
  # ---------------------------------------------------------------------------

  describe "sanitize_analytics_filters/1" do
    test "keeps valid days values" do
      for days <- ["7", "15", "30", "90", "365"] do
        result = Filters.sanitize_analytics_filters(%{days: days})
        assert result.days == days
      end
    end

    test "resets invalid days to '30'" do
      result = Filters.sanitize_analytics_filters(%{days: "60"})
      assert result.days == "30"
    end

    test "keeps valid planned_capacity values" do
      for cap <- ["5", "10", "15", "20", "30"] do
        result = Filters.sanitize_analytics_filters(%{planned_capacity: cap})
        assert result.planned_capacity == cap
      end
    end

    test "resets invalid planned_capacity to '10'" do
      result = Filters.sanitize_analytics_filters(%{planned_capacity: "99"})
      assert result.planned_capacity == "10"
    end

    test "uses defaults when keys are absent" do
      result = Filters.sanitize_analytics_filters(%{})
      assert result.days == "30"
      assert result.planned_capacity == "10"
    end
  end

  # ---------------------------------------------------------------------------
  # Property 1: Sanitização de filtros sempre produz valores válidos
  # Feature: dashboard-live-refactor, Property 1
  # ---------------------------------------------------------------------------

  @valid_task_statuses ["all", "todo", "in_progress", "done"]
  @valid_task_priorities ["all", "low", "medium", "high"]
  @valid_task_days ["7", "14", "30"]

  property "sanitize_task_filters always produces valid values for any arbitrary input" do
    # Feature: dashboard-live-refactor, Property 1
    check all(
            status <- StreamData.string(:alphanumeric),
            priority <- StreamData.string(:alphanumeric),
            days <- StreamData.string(:alphanumeric),
            q <- StreamData.string(:alphanumeric)
          ) do
      result =
        Filters.sanitize_task_filters(%{
          status: status,
          priority: priority,
          days: days,
          q: q
        })

      assert result.status in @valid_task_statuses
      assert result.priority in @valid_task_priorities
      assert result.days in @valid_task_days
      assert is_binary(result.q)
    end
  end

  # ---------------------------------------------------------------------------
  # Property 2: Sanitização de filtros financeiros sempre produz valores válidos
  # Feature: dashboard-live-refactor, Property 2
  # ---------------------------------------------------------------------------

  @valid_finance_days ["7", "30", "90"]
  @valid_finance_kinds ["all", "income", "expense"]
  @valid_expense_profiles ["all", "fixed", "variable"]
  @valid_payment_methods ["all", "credit", "debit"]

  property "sanitize_finance_filters always produces valid values for any arbitrary input" do
    # Feature: dashboard-live-refactor, Property 2
    check all(
            days <- StreamData.string(:alphanumeric),
            kind <- StreamData.string(:alphanumeric),
            expense_profile <- StreamData.string(:alphanumeric),
            payment_method <- StreamData.string(:alphanumeric)
          ) do
      result =
        Filters.sanitize_finance_filters(%{
          days: days,
          kind: kind,
          expense_profile: expense_profile,
          payment_method: payment_method
        })

      assert result.days in @valid_finance_days
      assert result.kind in @valid_finance_kinds
      assert result.expense_profile in @valid_expense_profiles
      assert result.payment_method in @valid_payment_methods
    end
  end
end
