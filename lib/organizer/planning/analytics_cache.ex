defmodule Organizer.Planning.AnalyticsCache do
  @moduledoc """
  Cache layer for analytics calculations using GenServer + ETS.

  Provides fast read-through caching for expensive analytics calculations
  (progress_by_period, workload_capacity, burnout_risk) while maintaining
  consistency through mutation-based cache invalidation.

  The cache uses ETS for concurrent reads and a GenServer for lifecycle
  management and invalidation coordination.
  """

  use GenServer
  require Logger

  alias Organizer.Planning
  alias Organizer.Planning.Analytics

  # Cache TTL: 5 minutes. After this, cache expires and must be recalculated.
  # Mutations trigger immediate invalidation regardless of TTL.
  # 5 minutes in milliseconds
  @default_cache_ttl 5 * 60 * 1000

  # ===== Public API =====

  @doc """
  Start the cache GenServer and ETS table.

  Should be called from application supervision tree via:
  {Organizer.Planning.AnalyticsCache, []}
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get cached analytics for a user or recalculate if missing/expired.

  Returns analytics snapshot with keys:
  - :progress_by_period - tasks grouped by period
  - :workload_capacity - open/executed workload metrics
  - :burnout_risk_assessment - composite burnout assessment
  """
  def get_analytics(scope, opts \\ []) do
    days = normalize_days(Keyword.get(opts, :days, 365))
    planned_capacity = normalize_planned_capacity(Keyword.get(opts, :planned_capacity, 10))

    cache_key = cache_key(scope, days)

    case lookup_cache(cache_key) do
      {:hit, analytics, expires_at} ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:ok, analytics}
        else
          # Cache expired, recalculate
          calculate_and_cache(scope, days, planned_capacity)
        end

      :miss ->
        # Cache miss, calculate and store
        calculate_and_cache(scope, days, planned_capacity)

      :error ->
        # Cache lookup failed (unlikely, but graceful fallback)
        recalculate(scope, days, planned_capacity)
    end
  end

  defp normalize_days(value) when is_integer(value), do: value

  defp normalize_days(value) when is_binary(value) do
    String.to_integer(value)
  rescue
    _ -> 365
  end

  defp normalize_days(_), do: 365

  defp normalize_planned_capacity(value) when is_integer(value), do: value

  defp normalize_planned_capacity(value) when is_binary(value) do
    String.to_integer(value)
  rescue
    _ -> 10
  end

  defp normalize_planned_capacity(_), do: 10

  @doc """
  Invalidate all cache entries for a user.

  Called after mutations (create/update/delete of tasks and finances)
  to ensure next get_analytics call recalculates fresh results.
  """
  def invalidate_for_user(scope) do
    GenServer.cast(__MODULE__, {:invalidate_user, scope.user.id})
  end

  @doc """
  Invalidate cache for a specific analytics request.

  Useful for targeted invalidation after specific operation.
  """
  def invalidate(scope, opts \\ []) do
    days = Keyword.get(opts, :days, 90)
    cache_key = cache_key(scope, days)
    GenServer.cast(__MODULE__, {:invalidate_key, cache_key})
  end

  # ===== GenServer Callbacks =====

  @impl true
  def init(_opts) do
    # Create ETS table for concurrent reads, non-blocking access
    :ets.new(
      :analytics_cache,
      [:set, :named_table, :public, {:read_concurrency, true}]
    )

    Logger.info("Analytics cache initialized")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:invalidate_user, user_id}, state) do
    # Invalidate all cache keys for this user (all day windows)
    [7, 14, 15, 30, 90, 365]
    |> Enum.each(fn days ->
      key = "analytics:user:#{user_id}:days:#{days}"
      :ets.delete(:analytics_cache, key)
    end)

    Logger.debug("Invalidated analytics cache for user #{user_id}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:invalidate_key, key}, state) do
    :ets.delete(:analytics_cache, key)
    Logger.debug("Invalidated analytics cache key: #{key}")
    {:noreply, state}
  end

  # ===== Private Functions =====

  defp cache_key(scope, days) do
    "analytics:user:#{scope.user.id}:days:#{days}"
  end

  defp lookup_cache(key) do
    case :ets.lookup(:analytics_cache, key) do
      [{^key, {analytics, expires_at}}] ->
        {:hit, analytics, expires_at}

      [] ->
        :miss

      _error ->
        :error
    end
  rescue
    _e ->
      # Graceful handling if ETS table is unavailable
      :error
  end

  defp calculate_and_cache(scope, days, planned_capacity) do
    case recalculate(scope, days, planned_capacity) do
      {:ok, analytics} ->
        cache_key = cache_key(scope, days)
        expires_at = DateTime.add(DateTime.utc_now(), @default_cache_ttl, :millisecond)

        :ets.insert(:analytics_cache, {cache_key, {analytics, expires_at}})
        Logger.debug("Cached analytics for user #{scope.user.id} (#{days}d)")

        {:ok, analytics}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Error calculating analytics: #{inspect(e)}")
      {:error, "Analytics calculation failed"}
  end

  defp recalculate(scope, days, planned_capacity) do
    {:ok, tasks} = Planning.list_tasks(scope, %{days: days})
    # Note: finances are fetched but not used in current analytics calculations
    # This ensures cache consistency across mutation types (task/finance changes)
    {:ok, _finances} = Planning.list_finance_entries(scope, %{days: days})

    analytics = %{
      progress_by_period: Analytics.progress_by_period(tasks),
      workload_capacity: Analytics.workload_capacity_snapshot(tasks, planned_capacity),
      burnout_risk_assessment: Analytics.burnout_risk_assessment(tasks)
    }

    {:ok, analytics}
  rescue
    e ->
      Logger.error("Recalculation failed: #{inspect(e)}")
      {:error, "Recalculation failed"}
  end
end
