defmodule OrganizerWeb.DashboardLive.FiltersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias OrganizerWeb.DashboardLive.Filters

  @valid_task_statuses ["all", "todo", "in_progress", "done"]
  @valid_task_priorities ["all", "low", "medium", "high"]
  @valid_task_days ["7", "14", "30"]

  @valid_finance_period_modes ["rolling", "specific_date", "month", "range", "weekday"]
  @valid_finance_days ["7", "30", "90", "365"]
  @valid_finance_kinds ["all", "income", "expense"]
  @valid_expense_profiles ["all", "fixed", "variable", "recurring_fixed", "recurring_variable"]
  @valid_payment_methods ["all", "credit", "debit"]
  @valid_weekdays ["all", "0", "1", "2", "3", "4", "5", "6"]
  @valid_sortings ["date_desc", "date_asc", "amount_desc", "amount_asc", "category_asc"]

  describe "defaults" do
    test "default_task_filters/0 returns expected map" do
      assert Filters.default_task_filters() == %{
               status: "all",
               priority: "all",
               days: "14",
               q: ""
             }
    end

    test "default_finance_filters/0 returns expected map" do
      assert Filters.default_finance_filters() == %{
               period_mode: "rolling",
               days: "30",
               month: "",
               occurred_on: "",
               occurred_from: "",
               occurred_to: "",
               weekday: "all",
               sort_by: "date_desc",
               kind: "all",
               expense_profile: "all",
               payment_method: "all",
               category: "",
               q: "",
               min_amount_cents: "",
               max_amount_cents: ""
             }
    end

    test "default_analytics_filters/0 returns expected map" do
      assert Filters.default_analytics_filters() == %{days: "30", planned_capacity: "10"}
    end
  end

  describe "normalize_finance_filters/1" do
    test "keeps present values and drops nil/empty values" do
      result =
        Filters.normalize_finance_filters(%{
          "period_mode" => "month",
          "days" => "90",
          "month" => "04/2026",
          "occurred_on" => "",
          "weekday" => nil,
          "kind" => "expense",
          "category" => "food"
        })

      assert result == %{
               period_mode: "month",
               days: "90",
               month: "04/2026",
               kind: "expense",
               category: "food"
             }
    end
  end

  describe "sanitize_finance_filters/1" do
    test "sanitizes period values and dates" do
      result =
        Filters.sanitize_finance_filters(%{
          period_mode: "specific_date",
          occurred_on: "2026-04-24",
          occurred_from: "24/04/2026",
          occurred_to: "invalid",
          month: "4/2026",
          weekday: "4",
          sort_by: "amount_desc"
        })

      assert result.period_mode == "specific_date"
      assert result.occurred_on == "24/04/2026"
      assert result.occurred_from == "24/04/2026"
      assert result.occurred_to == ""
      assert result.month == ""
      assert result.weekday == "4"
      assert result.sort_by == "amount_desc"
    end

    test "resets invalid enums and numbers to defaults" do
      result =
        Filters.sanitize_finance_filters(%{
          period_mode: "wrong",
          days: "12",
          kind: "transfer",
          expense_profile: "monthly",
          payment_method: "pix",
          weekday: "10",
          sort_by: "custom",
          min_amount_cents: "-5",
          max_amount_cents: "abc"
        })

      assert result.period_mode == "rolling"
      assert result.days == "30"
      assert result.kind == "all"
      assert result.expense_profile == "all"
      assert result.payment_method == "all"
      assert result.weekday == "all"
      assert result.sort_by == "date_desc"
      assert result.min_amount_cents == ""
      assert result.max_amount_cents == ""
    end
  end

  property "sanitize_task_filters always produces valid values" do
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

  property "sanitize_finance_filters always produces valid enum values" do
    check all(
            period_mode <- StreamData.string(:alphanumeric),
            days <- StreamData.string(:alphanumeric),
            kind <- StreamData.string(:alphanumeric),
            expense_profile <- StreamData.string(:alphanumeric),
            payment_method <- StreamData.string(:alphanumeric),
            weekday <- StreamData.string(:alphanumeric),
            sort_by <- StreamData.string(:alphanumeric)
          ) do
      result =
        Filters.sanitize_finance_filters(%{
          period_mode: period_mode,
          days: days,
          kind: kind,
          expense_profile: expense_profile,
          payment_method: payment_method,
          weekday: weekday,
          sort_by: sort_by
        })

      assert result.period_mode in @valid_finance_period_modes
      assert result.days in @valid_finance_days
      assert result.kind in @valid_finance_kinds
      assert result.expense_profile in @valid_expense_profiles
      assert result.payment_method in @valid_payment_methods
      assert result.weekday in @valid_weekdays
      assert result.sort_by in @valid_sortings
    end
  end
end
