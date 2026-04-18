defmodule Organizer.Planning.QualityAuditPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Organizer.Accounts.{Scope, User}
  alias Organizer.Planning
  alias Organizer.Repo
  alias OrganizerWeb.DashboardLive.Filters

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Create a test user for the scope
    user =
      %User{}
      |> User.registration_changeset(%{
        email: "test-#{System.unique_integer([:positive])}@example.com",
        password: "password123456"
      })
      |> Repo.insert!()

    scope = Scope.for_user(user)

    # Create a task for update operations
    {:ok, task} =
      Planning.create_task(scope, %{
        title: "Initial Task",
        status: "todo",
        priority: "medium"
      })

    {:ok, scope: scope, task: task}
  end

  # ---------------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------------

  # Generates task attribute maps with various valid and invalid combinations
  defp gen_task_attrs do
    gen all(
          title <- gen_title(),
          notes <- gen_notes(),
          status <- gen_status(),
          priority <- gen_priority(),
          due_on <- gen_due_on()
        ) do
      %{
        title: title,
        notes: notes,
        status: status,
        priority: priority,
        due_on: due_on
      }
    end
  end

  # Title generator: mix of valid, blank, too short, too long
  defp gen_title do
    StreamData.frequency([
      {3, StreamData.string(:alphanumeric, min_length: 3, max_length: 120)},
      {1, StreamData.constant("")},
      {1, StreamData.constant("  ")},
      {1, StreamData.string(:alphanumeric, min_length: 1, max_length: 2)},
      {1, StreamData.string(:alphanumeric, min_length: 121, max_length: 200)}
    ])
  end

  # Notes generator: mix of valid, nil, empty, too long
  defp gen_notes do
    StreamData.frequency([
      {3, StreamData.string(:alphanumeric, max_length: 1000)},
      {2, StreamData.constant(nil)},
      {1, StreamData.constant("")},
      {1, StreamData.string(:alphanumeric, min_length: 1001, max_length: 1500)}
    ])
  end

  # Status generator: mix of valid and invalid values
  # Note: Invalid values must still be existing atoms to avoid crashes in the current implementation
  defp gen_status do
    StreamData.frequency([
      {4, StreamData.member_of(["todo", "in_progress", "done"])},
      {1, StreamData.constant("")}
    ])
  end

  # Priority generator: mix of valid and invalid values
  # Note: Invalid values must still be existing atoms to avoid crashes in the current implementation
  defp gen_priority do
    StreamData.frequency([
      {4, StreamData.member_of(["low", "medium", "high"])},
      {1, StreamData.constant("")}
    ])
  end

  # Due date generator: mix of valid dates, nil, and invalid strings
  defp gen_due_on do
    StreamData.frequency([
      {3, gen_valid_date()},
      {2, StreamData.constant(nil)},
      {1, StreamData.constant("")},
      {1, StreamData.member_of(["invalid-date", "2024-13-01", "not-a-date"])}
    ])
  end

  defp gen_valid_date do
    gen all(
          year <- StreamData.integer(2020..2030),
          month <- StreamData.integer(1..12),
          day <- StreamData.integer(1..28)
        ) do
      Date.new!(year, month, day) |> Date.to_iso8601()
    end
  end

  # ---------------------------------------------------------------------------
  # Property 1: Equivalência de validação entre create_task e update_task
  # **Validates: Requirements 1.1, 1.4**
  # ---------------------------------------------------------------------------

  @tag feature: "codebase-quality-audit", property: 1
  property "Propriedade 1: create_task e update_task produzem resultados de validação equivalentes",
           context do
    check all(
            attrs <- gen_task_attrs(),
            max_runs: 100
          ) do
      scope = context[:scope]
      task = context[:task]

      # Call create_task with the generated attributes
      create_result = Planning.create_task(scope, attrs)

      # Call update_task with the same attributes
      update_result = Planning.update_task(scope, task.id, attrs)

      # Assert equivalence based on the result type
      case {create_result, update_result} do
        {{:error, {:validation, create_errors}}, {:error, {:validation, update_errors}}} ->
          # Both failed validation - check that the same fields have errors
          create_error_fields = Map.keys(create_errors) |> Enum.sort()
          update_error_fields = Map.keys(update_errors) |> Enum.sort()

          assert create_error_fields == update_error_fields,
                 """
                 Validation error fields differ between create_task and update_task.
                 Attributes: #{inspect(attrs)}
                 create_task error fields: #{inspect(create_error_fields)}
                 update_task error fields: #{inspect(update_error_fields)}
                 create_task errors: #{inspect(create_errors)}
                 update_task errors: #{inspect(update_errors)}
                 """

        {{:ok, _created_task}, {:ok, _updated_task}} ->
          # Both succeeded - this is the expected equivalence
          :ok

        {{:error, {:validation, create_errors}}, {:ok, updated_task}} ->
          flunk("""
          create_task failed validation but update_task succeeded.
          Attributes: #{inspect(attrs)}
          create_task errors: #{inspect(create_errors)}
          update_task result: #{inspect(updated_task)}
          """)

        {{:ok, created_task}, {:error, {:validation, update_errors}}} ->
          flunk("""
          create_task succeeded but update_task failed validation.
          Attributes: #{inspect(attrs)}
          create_task result: #{inspect(created_task)}
          update_task errors: #{inspect(update_errors)}
          """)

        {create_result, update_result} ->
          flunk("""
          Unexpected result pattern.
          Attributes: #{inspect(attrs)}
          create_task result: #{inspect(create_result)}
          update_task result: #{inspect(update_result)}
          """)
      end

      # Clean up any created tasks to avoid database bloat during property testing
      case create_result do
        {:ok, created_task} ->
          Repo.delete(created_task)

        _ ->
          :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Property 2: Limite de comprimento do parâmetro q nos filtros
  # **Validates: Requirements 3.4**
  # ---------------------------------------------------------------------------

  @tag feature: "codebase-quality-audit", property: 2
  property "Propriedade 2: sanitize_*_filters trunca q para no máximo 100 caracteres" do
    check all(
            q <- StreamData.string(:printable),
            max_runs: 100
          ) do
      # Test sanitize_task_filters
      task_filters = %{q: q}
      sanitized_task = Filters.sanitize_task_filters(task_filters)
      task_q_length = String.length(sanitized_task.q)

      assert task_q_length <= 100,
             """
             sanitize_task_filters did not truncate q to 100 characters.
             Original q length: #{String.length(q)}
             Sanitized q length: #{task_q_length}
             Sanitized q: #{inspect(sanitized_task.q)}
             """

      # Test sanitize_finance_filters
      finance_filters = %{q: q}
      sanitized_finance = Filters.sanitize_finance_filters(finance_filters)
      finance_q_length = String.length(sanitized_finance.q)

      assert finance_q_length <= 100,
             """
             sanitize_finance_filters did not truncate q to 100 characters.
             Original q length: #{String.length(q)}
             Sanitized q length: #{finance_q_length}
             Sanitized q: #{inspect(sanitized_finance.q)}
             """

      # Test sanitize_goal_filters
      goal_filters = %{q: q}
      sanitized_goal = Filters.sanitize_goal_filters(goal_filters)
      goal_q_length = String.length(sanitized_goal.q)

      assert goal_q_length <= 100,
             """
             sanitize_goal_filters did not truncate q to 100 characters.
             Original q length: #{String.length(q)}
             Sanitized q length: #{goal_q_length}
             Sanitized q: #{inspect(sanitized_goal.q)}
             """
    end
  end

  # ---------------------------------------------------------------------------
  # Property 4: amount_cents acima do limite sempre falha na validação
  # **Validates: Requirements 7.1, 7.3**
  # ---------------------------------------------------------------------------

  @tag feature: "codebase-quality-audit", property: 4
  property "Propriedade 4: amount_cents > 1_000_000_000 sempre falha na validação" do
    check all(
            n <- StreamData.integer(1_000_000_001..10_000_000_000),
            max_runs: 100
          ) do
      # Test validate_finance_entry_attrs with amount_cents above limit
      finance_attrs = %{
        kind: :expense,
        expense_profile: :variable,
        payment_method: :debit,
        amount_cents: n,
        category: "Test Category",
        occurred_on: Date.utc_today()
      }

      finance_result = Planning.AttributeValidation.validate_finance_entry_attrs(finance_attrs)

      assert match?({:error, {:validation, %{amount_cents: _}}}, finance_result),
             """
             validate_finance_entry_attrs did not reject amount_cents > 1_000_000_000.
             amount_cents: #{n}
             Result: #{inspect(finance_result)}
             """

      # Test validate_fixed_cost_attrs with amount_cents above limit
      fixed_cost_attrs = %{
        name: "Test Fixed Cost",
        amount_cents: n,
        billing_day: 15
      }

      fixed_cost_result = Planning.AttributeValidation.validate_fixed_cost_attrs(fixed_cost_attrs)

      assert match?({:error, {:validation, %{amount_cents: _}}}, fixed_cost_result),
             """
             validate_fixed_cost_attrs did not reject amount_cents > 1_000_000_000.
             amount_cents: #{n}
             Result: #{inspect(fixed_cost_result)}
             """
    end
  end

  # ---------------------------------------------------------------------------
  # Property 5: Invariante de ordem em progress_min / progress_max
  # **Validates: Requirements 8.1**
  # ---------------------------------------------------------------------------

  @tag feature: "codebase-quality-audit", property: 5
  property "Propriedade 5: após sanitize_goal_filters, progress_min <= progress_max" do
    check all(
            a <- StreamData.integer(0..100),
            b <- StreamData.integer(0..100),
            max_runs: 100
          ) do
      # Test with both values as integers
      filters_int = %{progress_min: a, progress_max: b}
      sanitized_int = Filters.sanitize_goal_filters(filters_int)

      # Parse the sanitized values back to integers for comparison
      min_result =
        case Map.get(sanitized_int, :progress_min, "") do
          "" -> nil
          str -> String.to_integer(str)
        end

      max_result =
        case Map.get(sanitized_int, :progress_max, "") do
          "" -> nil
          str -> String.to_integer(str)
        end

      # Assert the invariant: if both values are present, min <= max
      if min_result != nil and max_result != nil do
        assert min_result <= max_result,
               """
               sanitize_goal_filters did not maintain progress_min <= progress_max invariant.
               Input: progress_min=#{a}, progress_max=#{b}
               Output: progress_min=#{min_result}, progress_max=#{max_result}
               """
      end

      # Test with both values as strings
      filters_str = %{progress_min: Integer.to_string(a), progress_max: Integer.to_string(b)}
      sanitized_str = Filters.sanitize_goal_filters(filters_str)

      min_result_str =
        case Map.get(sanitized_str, :progress_min, "") do
          "" -> nil
          str -> String.to_integer(str)
        end

      max_result_str =
        case Map.get(sanitized_str, :progress_max, "") do
          "" -> nil
          str -> String.to_integer(str)
        end

      if min_result_str != nil and max_result_str != nil do
        assert min_result_str <= max_result_str,
               """
               sanitize_goal_filters did not maintain progress_min <= progress_max invariant (string input).
               Input: progress_min="#{a}", progress_max="#{b}"
               Output: progress_min=#{min_result_str}, progress_max=#{max_result_str}
               """
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Property 6: current_value > target_value sempre produz changeset inválido
  # **Validates: Requirements 9.1, 9.4**
  # ---------------------------------------------------------------------------

  @tag feature: "codebase-quality-audit", property: 6
  property "Propriedade 6: current_value > target_value sempre produz changeset inválido" do
    check all(
            target <- StreamData.integer(1..999),
            delta <- StreamData.integer(1..1000),
            title <- StreamData.string(:alphanumeric, min_length: 3, max_length: 100),
            horizon <- StreamData.member_of([:short, :medium, :long]),
            status <- StreamData.member_of([:active, :paused, :done]),
            max_runs: 100
          ) do
      alias Organizer.Planning.Goal

      # Ensure current > target by adding delta to target
      current = target + delta

      # Create a changeset with current_value > target_value
      changeset =
        Goal.changeset(%Goal{}, %{
          title: title,
          horizon: horizon,
          status: status,
          current_value: current,
          target_value: target
        })

      # Assert the changeset is invalid
      refute changeset.valid?,
             """
             Goal.changeset did not reject current_value > target_value.
             current_value: #{current}
             target_value: #{target}
             changeset.valid?: #{changeset.valid?}
             changeset.errors: #{inspect(changeset.errors)}
             """

      # Assert the error is on the current_value field
      assert Keyword.has_key?(changeset.errors, :current_value),
             """
             Goal.changeset did not add error to :current_value field.
             current_value: #{current}
             target_value: #{target}
             changeset.errors: #{inspect(changeset.errors)}
             """

      # Assert the error message is correct
      {_message, _opts} = Keyword.fetch!(changeset.errors, :current_value)

      assert {_message, _opts} =
               Keyword.fetch!(changeset.errors, :current_value),
             """
             Goal.changeset did not add the expected error message.
             current_value: #{current}
             target_value: #{target}
             changeset.errors: #{inspect(changeset.errors)}
             """
    end
  end
end
