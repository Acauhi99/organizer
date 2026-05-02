defmodule Organizer.SharedFinance do
  @moduledoc """
  Context for shared finance features: invites, account links, shared entries,
  metrics, and settlement cycles.
  """

  import Ecto.Query

  alias Organizer.DateSupport
  alias Organizer.Repo
  alias Organizer.Planning.AmountParser
  alias Organizer.SharedFinance.{AccountLink, Invite}
  alias Organizer.Planning.FinanceEntry

  alias Organizer.SharedFinance.{
    SharedEntryView,
    SharedSplitSnapshot,
    SplitCalculator,
    LinkMetricsCalculator,
    SettlementCycle,
    SettlementRecord,
    SharedEntryDebt,
    SettlementRecordAllocation,
    MonthlyDebtSummary
  }

  # ---------------------------------------------------------------------------
  # Convites e vínculos
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new invite for the authenticated user.
  Generates a unique token, sets expiration to 72 hours from now, status: :pending.
  """
  def create_invite(scope) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    expires_at =
      DateTime.utc_now() |> DateTime.add(72 * 3600, :second) |> DateTime.truncate(:second)

    %Invite{}
    |> Ecto.Changeset.change(%{
      token: token,
      status: :pending,
      expires_at: expires_at,
      inviter_id: scope.user.id
    })
    |> Repo.insert()
  end

  @doc """
  Accepts an invite by token for the authenticated user.

  Returns:
  - `{:ok, account_link}` on success
  - `{:error, :invite_invalid}` if token not found, status != :pending, or expired
  - `{:error, :self_invite_not_allowed}` if user tries to accept their own invite
  - `{:error, :link_already_exists}` if an active link already exists between the two users
  """
  def accept_invite(scope, token) do
    now = DateTime.utc_now()

    case Repo.get_by(Invite, token: token) do
      nil ->
        {:error, :invite_invalid}

      invite ->
        cond do
          invite.status != :pending ->
            {:error, :invite_invalid}

          DateTime.compare(invite.expires_at, now) == :lt ->
            {:error, :invite_invalid}

          invite.inviter_id == scope.user.id ->
            {:error, :self_invite_not_allowed}

          active_link_exists?(invite.inviter_id, scope.user.id) ->
            {:error, :link_already_exists}

          true ->
            do_accept_invite(invite, scope.user.id)
        end
    end
  end

  @doc """
  Deactivates an account link that the authenticated user participates in.
  Returns `{:error, :not_found}` if the link doesn't exist or user is not a participant.
  """
  def deactivate_account_link(scope, link_id) do
    user_id = scope.user.id

    query =
      from l in AccountLink,
        where:
          l.id == ^link_id and
            l.status == :active and
            (l.user_a_id == ^user_id or l.user_b_id == ^user_id)

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      link ->
        link
        |> Ecto.Changeset.change(%{status: :inactive})
        |> Repo.update()
    end
  end

  @doc """
  Lists all active account links for the authenticated user, preloading user_a and user_b.
  """
  def list_account_links(scope) do
    with {:ok, {links, _meta}} <- list_account_links_with_meta(scope, %{limit: 10_000, offset: 0}) do
      {:ok, links}
    end
  end

  def list_account_links_with_meta(scope, params \\ %{}) do
    user_id = scope.user.id

    query =
      from(l in AccountLink,
        where:
          l.status == :active and
            (l.user_a_id == ^user_id or l.user_b_id == ^user_id),
        preload: [:user_a, :user_b]
      )
      |> maybe_filter_account_links_query(params)

    case Flop.validate_and_run(query, shared_flop_params(params), for: AccountLink, repo: Repo) do
      {:ok, {links, meta}} ->
        {:ok, {links, meta}}

      {:error, %Flop.Meta{} = meta} ->
        {:error, {:validation, %{pagination: flop_error_messages(meta)}}}
    end
  end

  @doc """
  Gets a single account link by id, ensuring the authenticated user is a participant.
  Preloads user_a and user_b.
  Returns `{:error, :not_found}` if not found or user is not a participant.
  """
  def get_account_link(scope, link_id) do
    user_id = scope.user.id

    query =
      from l in AccountLink,
        where:
          l.id == ^link_id and
            l.status == :active and
            (l.user_a_id == ^user_id or l.user_b_id == ^user_id),
        preload: [:user_a, :user_b]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      link -> {:ok, link}
    end
  end

  @doc """
  Returns true when the shared entry already has payment allocations and should not be edited.
  """
  def shared_entry_allocation_locked?(entry_id) when is_integer(entry_id) do
    shared_entry_has_allocations?(entry_id)
  end

  # ---------------------------------------------------------------------------
  # Lançamentos compartilhados
  # ---------------------------------------------------------------------------

  @doc """
  Marks a FinanceEntry as shared with an AccountLink.
  Verifies the entry belongs to the user and the user is a participant of the link.
  Broadcasts a PubSub event after successful update.
  """
  def share_finance_entry(scope, entry_id, link_id, attrs \\ %{})

  def share_finance_entry(scope, entry_id, link_id, attrs) do
    share_finance_entry(scope, entry_id, link_id, attrs, [])
  end

  def share_finance_entry(scope, entry_id, link_id, attrs, opts)
      when is_map(attrs) and is_list(opts) do
    user_id = scope.user.id
    broadcast? = Keyword.get(opts, :broadcast?, true)

    entry_query =
      from fe in FinanceEntry,
        where: fe.id == ^entry_id and fe.user_id == ^user_id

    case Repo.one(entry_query) do
      nil ->
        {:error, :not_found}

      entry ->
        case get_account_link(scope, link_id) do
          {:error, :not_found} ->
            {:error, :not_found}

          {:ok, link} ->
            with {:ok, share_attrs} <- normalize_share_attrs(entry, attrs),
                 {:ok, updated_entry} <-
                   entry
                   |> Ecto.Changeset.change(Map.put(share_attrs, :shared_with_link_id, link_id))
                   |> Repo.update(),
                 :ok <- sync_shared_entry_debt(updated_entry, link) do
              if broadcast? do
                broadcast_shared_entry_updated(updated_entry)
              end

              {:ok, updated_entry}
            else
              {:error, :shared_entry_has_allocations} ->
                {:error,
                 {:validation, %{shared_entry: ["cannot be changed after payment allocation"]}}}

              {:error, _reason} = error ->
                error
            end
        end
    end
  end

  @doc """
  Broadcasts a shared entry update event to its account link topic.
  """
  def broadcast_shared_entry_updated(%FinanceEntry{} = entry) do
    if is_integer(entry.shared_with_link_id) do
      Phoenix.PubSub.broadcast(
        Organizer.PubSub,
        "account_link:#{entry.shared_with_link_id}",
        {:shared_entry_updated, entry}
      )
    end

    :ok
  end

  @doc """
  Returns a shared FinanceEntry owned by the authenticated user for a given account link.
  """
  def get_shared_entry_owned_by_user(scope, link_id, entry_id) do
    user_id = scope.user.id

    with {:ok, _link} <- get_account_link(scope, link_id),
         %FinanceEntry{} = entry <- shared_entry_owned_by_user(user_id, link_id, entry_id) do
      {:ok, entry}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Removes the shared association from a FinanceEntry.
  Verifies the entry belongs to the user.
  Broadcasts a PubSub event after successful update.
  """
  def unshare_finance_entry(scope, entry_id) do
    user_id = scope.user.id

    entry_query =
      from fe in FinanceEntry,
        where: fe.id == ^entry_id and fe.user_id == ^user_id

    case Repo.one(entry_query) do
      nil ->
        {:error, :not_found}

      entry ->
        if shared_entry_has_allocations?(entry.id) do
          {:error, {:validation, %{shared_entry: ["cannot be changed after payment allocation"]}}}
        else
          link_id = entry.shared_with_link_id

          case entry
               |> Ecto.Changeset.change(%{
                 shared_with_link_id: nil,
                 shared_split_mode: nil,
                 shared_manual_mine_cents: nil
               })
               |> Repo.update() do
            {:ok, updated_entry} = result ->
              :ok = remove_shared_entry_debt(entry.id)

              if link_id do
                Phoenix.PubSub.broadcast(
                  Organizer.PubSub,
                  "account_link:#{link_id}",
                  {:shared_entry_removed, updated_entry}
                )
              end

              result

            error ->
              error
          end
        end
    end
  end

  @doc """
  Updates a shared FinanceEntry owned by the authenticated user.

  Supports editing core transaction fields and split type:
  - `income_ratio` (automatic by reference income)
  - `percentage` (fixed percentage for owner side)
  - `fixed_amount` (fixed amount for owner side)

  Returns `{:error, :not_found}` when entry/link is not accessible by the user.
  """
  def update_shared_finance_entry(scope, link_id, entry_id, attrs) when is_map(attrs) do
    user_id = scope.user.id

    with {:ok, _link} <- get_account_link(scope, link_id),
         %FinanceEntry{} = entry <- shared_entry_owned_by_user(user_id, link_id, entry_id),
         false <- shared_entry_has_allocations?(entry.id),
         {:ok, updated_attrs} <- normalize_shared_entry_update_attrs(entry, attrs),
         {:ok, updated_entry} <- entry |> FinanceEntry.changeset(updated_attrs) |> Repo.update() do
      {:ok, link} = get_account_link(scope, link_id)
      :ok = sync_shared_entry_debt(updated_entry, link)
      rebalance_user_links(scope)
      :ok = broadcast_shared_entry_updated(updated_entry)
      {:ok, updated_entry}
    else
      nil ->
        {:error, :not_found}

      true ->
        {:error, {:validation, %{shared_entry: ["cannot be changed after payment allocation"]}}}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Lists all FinanceEntries shared with a given AccountLink, with split ratios calculated
  from each user's reference income in the month of each entry (`occurred_on`),
  using carryover rules when needed.
  `reference_date` controls period filtering and snapshot boundaries, not the per-entry month basis.
  Returns `{:error, :not_found}` if the user is not a participant of the link.
  """
  def list_shared_entries(scope, link_id, params \\ %{}) do
    legacy_params =
      params
      |> Map.put_new(:limit, 10_000)
      |> Map.put_new(:offset, 0)

    with {:ok, {views, _meta}} <- list_shared_entries_with_meta(scope, link_id, legacy_params) do
      {:ok, views}
    end
  end

  def list_shared_entries_with_meta(scope, link_id, params \\ %{}) do
    case get_account_link(scope, link_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, link} ->
        period = normalize_shared_period(params)

        reference_date =
          normalize_reference_date(
            Map.get(params, :reference_date) || Map.get(params, "reference_date")
          )

        persist_snapshots? = normalize_persist_snapshots_flag(params)

        query =
          from(fe in FinanceEntry, where: fe.shared_with_link_id == ^link_id)
          |> maybe_filter_shared_entries_query(params)
          |> apply_shared_period_filter_query(period, reference_date)

        with {:ok, {entries, meta}} <-
               Flop.validate_and_run(query, shared_flop_params(params),
                 for: FinanceEntry,
                 repo: Repo
               ) do
          user_id = scope.user.id

          {views, _income_context_cache} =
            Enum.map_reduce(entries, %{}, fn entry, income_context_cache ->
              {entry_reference_date, income_context} =
                income_context_for_entry(entry, link, income_context_cache)

              updated_cache =
                Map.put(
                  income_context_cache,
                  {entry_reference_date.year, entry_reference_date.month},
                  income_context
                )

              split = resolve_entry_split(entry, link, income_context)

              maybe_persist_split_snapshot(
                persist_snapshots?,
                entry,
                link,
                entry_reference_date,
                split,
                income_context
              )

              scoped_split = scope_split_for_user(split, user_id, link)

              view = %SharedEntryView{
                entry: entry,
                split_ratio_mine: scoped_split.ratio_mine,
                split_ratio_theirs: scoped_split.ratio_theirs,
                amount_mine_cents: scoped_split.amount_mine_cents,
                amount_theirs_cents: scoped_split.amount_theirs_cents
              }

              {view, updated_cache}
            end)

          {:ok, {views, meta}}
        else
          {:error, %Flop.Meta{} = meta} ->
            {:error, {:validation, %{pagination: flop_error_messages(meta)}}}
        end
    end
  end

  @doc """
  Recalculates and persists temporal split snapshots for all active links from the given user.
  """
  def rebalance_user_links(scope, opts \\ %{}) do
    reference_date =
      normalize_reference_date(Map.get(opts, :reference_date) || Map.get(opts, "reference_date"))

    with {:ok, links} <- list_account_links(scope) do
      Enum.each(links, fn link ->
        _ = sync_link_debts(scope, link)

        _ =
          list_shared_entries(scope, link.id, %{
            period: "all",
            reference_date: reference_date,
            persist_snapshots: true
          })
      end)
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Métricas
  # ---------------------------------------------------------------------------

  @doc """
  Calculates LinkMetrics for a given AccountLink and reference month.
  `reference_month` is a `%Date{}` struct.
  Returns `{:ok, %LinkMetrics{}}` or `{:error, :not_found}`.
  """
  def get_link_metrics(scope, link_id, reference_month, params \\ %{}) do
    case get_account_link(scope, link_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, link} ->
        period = normalize_shared_period(params)

        {:ok, filtered_views} =
          list_shared_entries(scope, link_id, %{
            period: period,
            reference_date: reference_month
          })

        income_a =
          SplitCalculator.calculate_reference_income_with_carryover(
            link.user_a_id,
            reference_month.month,
            reference_month.year
          )

        income_b =
          SplitCalculator.calculate_reference_income_with_carryover(
            link.user_b_id,
            reference_month.month,
            reference_month.year
          )

        {ratio_a, ratio_b} =
          resolve_metrics_ratios(
            income_a,
            income_b,
            filtered_views,
            link
          )

        {split_ratio_a, split_ratio_b} = scoped_ratios(scope.user.id, link, ratio_a, ratio_b)

        metrics =
          LinkMetricsCalculator.calculate_link_metrics(
            filtered_views,
            split_ratio_a,
            split_ratio_b,
            reference_date: reference_month
          )

        {:ok, metrics}
    end
  end

  @doc """
  Returns the monthly trend of recurring_variable shared entries for the last 6 months.
  Returns `{:ok, [%MonthlyTotal{}]}`.
  """
  def get_recurring_variable_trend(scope, link_id) do
    case get_account_link(scope, link_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, _link} ->
        {:ok, all_views} = list_shared_entries(scope, link_id)
        trend = LinkMetricsCalculator.calculate_recurring_variable_trend(all_views, 6)
        {:ok, trend}
    end
  end

  # ---------------------------------------------------------------------------
  # Acerto de contas
  # ---------------------------------------------------------------------------

  @doc """
  Gets or creates a SettlementCycle for a given AccountLink and reference month.
  Idempotent: multiple calls with the same arguments return the same cycle.
  `reference_month` is a `%Date{}` struct.
  """
  def get_or_create_settlement_cycle(scope, link_id, reference_month) do
    case get_account_link(scope, link_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, _link} ->
        attrs = %{
          reference_month: reference_month.month,
          reference_year: reference_month.year,
          status: :open
        }

        changeset =
          %SettlementCycle{}
          |> SettlementCycle.changeset(attrs)
          |> Ecto.Changeset.put_change(:account_link_id, link_id)

        case Repo.insert(changeset, on_conflict: :nothing, returning: true) do
          {:ok, %SettlementCycle{id: nil}} ->
            cycle =
              Repo.one!(
                from sc in SettlementCycle,
                  where:
                    sc.account_link_id == ^link_id and
                      sc.reference_month == ^reference_month.month and
                      sc.reference_year == ^reference_month.year
              )

            _ = refresh_cycle_status(cycle)
            {:ok, Repo.get!(SettlementCycle, cycle.id)}

          {:ok, cycle} ->
            _ = refresh_cycle_status(cycle)
            {:ok, Repo.get!(SettlementCycle, cycle.id)}

          {:error, _changeset} ->
            cycle =
              Repo.one!(
                from sc in SettlementCycle,
                  where:
                    sc.account_link_id == ^link_id and
                      sc.reference_month == ^reference_month.month and
                      sc.reference_year == ^reference_month.year
              )

            _ = refresh_cycle_status(cycle)
            {:ok, Repo.get!(SettlementCycle, cycle.id)}
        end
    end
  end

  @doc """
  Creates a SettlementRecord for a given SettlementCycle.
  Validates that amount_cents > 0.
  Broadcasts a PubSub event after successful creation.
  """
  def create_settlement_record(scope, cycle_id, attrs) do
    amount_cents = Map.get(attrs, :amount_cents) || Map.get(attrs, "amount_cents")

    if is_nil(amount_cents) or amount_cents <= 0 do
      {:error, {:validation, %{amount_cents: ["must be greater than 0"]}}}
    else
      case find_cycle_with_link(scope, cycle_id) do
        {:error, reason} ->
          {:error, reason}

        {:ok, cycle, link} ->
          receiver_id =
            if scope.user.id == link.user_a_id, do: link.user_b_id, else: link.user_a_id

          case list_open_debts_for_payment(link.id, scope.user.id, receiver_id) do
            [] ->
              {:error,
               {:validation,
                %{amount_cents: ["no outstanding amount for this payment direction"]}}}

            debts ->
              outstanding_total = Enum.reduce(debts, 0, &(&1.outstanding_amount_cents + &2))

              if amount_cents > outstanding_total do
                {:error, {:validation, %{amount_cents: ["cannot exceed outstanding amount"]}}}
              else
                record_attrs = %{
                  settlement_cycle_id: cycle.id,
                  payer_id: scope.user.id,
                  receiver_id: receiver_id,
                  amount_cents: amount_cents,
                  method: Map.get(attrs, :method) || Map.get(attrs, "method"),
                  status: :active,
                  transferred_at:
                    Map.get(attrs, :transferred_at) || Map.get(attrs, "transferred_at")
                }

                Repo.transaction(fn ->
                  with {:ok, record} <-
                         %SettlementRecord{}
                         |> Ecto.Changeset.change(record_attrs)
                         |> Repo.insert(),
                       :ok <- allocate_record_fifo(record, debts),
                       :ok <- refresh_cycle_status(cycle) do
                    record
                  else
                    {:error, reason} -> Repo.rollback(reason)
                  end
                end)
                |> case do
                  {:ok, record} ->
                    Phoenix.PubSub.broadcast(
                      Organizer.PubSub,
                      "account_link:#{link.id}",
                      {:settlement_record_created, record}
                    )

                    {:ok, record}

                  {:error, {:validation, _} = validation} ->
                    {:error, validation}

                  {:error, reason} when is_atom(reason) ->
                    {:error, reason}

                  {:error, _reason} ->
                    {:error, {:validation, %{amount_cents: ["could not allocate payment"]}}}
                end
              end
          end
      end
    end
  end

  @doc """
  Creates a SettlementRecord allocated to a specific SharedEntryDebt.
  Validates the debt belongs to the same link and that the authenticated user is the debtor.
  """
  def create_settlement_record_for_debt(scope, cycle_id, shared_entry_debt_id, attrs) do
    amount_cents = Map.get(attrs, :amount_cents) || Map.get(attrs, "amount_cents")

    if is_nil(amount_cents) or amount_cents <= 0 do
      {:error, {:validation, %{amount_cents: ["must be greater than 0"]}}}
    else
      case find_cycle_with_link(scope, cycle_id) do
        {:error, reason} ->
          {:error, reason}

        {:ok, cycle, link} ->
          case find_open_debt_for_payment(link.id, shared_entry_debt_id, scope.user.id) do
            {:error, :not_found} ->
              {:error, :not_found}

            {:ok, debt} ->
              if amount_cents > debt.outstanding_amount_cents do
                {:error,
                 {:validation,
                  %{amount_cents: ["cannot exceed selected debt outstanding amount"]}}}
              else
                record_attrs = %{
                  settlement_cycle_id: cycle.id,
                  payer_id: scope.user.id,
                  receiver_id: debt.creditor_id,
                  amount_cents: amount_cents,
                  method: Map.get(attrs, :method) || Map.get(attrs, "method"),
                  status: :active,
                  transferred_at:
                    Map.get(attrs, :transferred_at) || Map.get(attrs, "transferred_at")
                }

                Repo.transaction(fn ->
                  with {:ok, record} <-
                         %SettlementRecord{}
                         |> Ecto.Changeset.change(record_attrs)
                         |> Repo.insert(),
                       :ok <- allocate_record_to_debt(record, debt, amount_cents),
                       :ok <- refresh_cycle_status(cycle) do
                    record
                  else
                    {:error, reason} -> Repo.rollback(reason)
                  end
                end)
                |> case do
                  {:ok, record} ->
                    Phoenix.PubSub.broadcast(
                      Organizer.PubSub,
                      "account_link:#{link.id}",
                      {:settlement_record_created, record}
                    )

                    {:ok, record}

                  {:error, {:validation, _} = validation} ->
                    {:error, validation}

                  {:error, reason} when is_atom(reason) ->
                    {:error, reason}

                  {:error, _reason} ->
                    {:error,
                     {:validation, %{amount_cents: ["could not allocate payment for debt"]}}}
                end
              end
          end
      end
    end
  end

  @doc """
  Reverts a previously created settlement record and restores debt outstanding balances.
  The caller must be a participant of the link and the record must be active.
  """
  def reverse_settlement_record(scope, settlement_record_id, attrs \\ %{}) do
    reason =
      attrs
      |> Map.get(:reason, Map.get(attrs, "reason", ""))
      |> to_string()
      |> String.trim()

    case find_record_with_link(scope, settlement_record_id) do
      {:error, reason_code} ->
        {:error, reason_code}

      {:ok, record, cycle, link} ->
        if record.status != :active do
          {:error, :already_reversed}
        else
          Repo.transaction(fn ->
            allocations =
              from(a in SettlementRecordAllocation,
                where: a.settlement_record_id == ^record.id,
                preload: [:shared_entry_debt],
                order_by: [asc: a.id]
              )
              |> Repo.all()

            with :ok <- restore_allocated_debts(allocations),
                 {:ok, _record} <-
                   record
                   |> Ecto.Changeset.change(%{
                     status: :reversed,
                     reversed_at: DateTime.utc_now() |> DateTime.truncate(:second),
                     reversed_by_id: scope.user.id,
                     reversal_reason: if(reason == "", do: nil, else: reason)
                   })
                   |> Repo.update(),
                 :ok <- refresh_cycle_status(cycle) do
              record.id
            else
              {:error, reason_code} -> Repo.rollback(reason_code)
            end
          end)
          |> case do
            {:ok, _record_id} ->
              Phoenix.PubSub.broadcast(
                Organizer.PubSub,
                "account_link:#{link.id}",
                {:settlement_record_reversed, settlement_record_id}
              )

              {:ok, :reversed}

            {:error, reason_code} when is_atom(reason_code) ->
              {:error, reason_code}

            {:error, _reason_code} ->
              {:error, :could_not_reverse_record}
          end
        end
    end
  end

  @doc """
  Confirms a user's acknowledgment of a SettlementCycle.
  When both users confirm, the cycle is marked as settled.
  Returns `{:error, :awaiting_counterpart_confirmation}` if only one user has confirmed.
  """
  def confirm_settlement(scope, cycle_id) do
    case find_cycle_with_link(scope, cycle_id) do
      {:error, reason} ->
        {:error, reason}

      {:ok, cycle, link} ->
        if pending_debts_for_cycle?(cycle) do
          {:error, :cycle_has_pending_debts}
        else
          user_id = scope.user.id

          {confirmed_a, confirmed_b} =
            if user_id == link.user_a_id do
              {true, cycle.confirmed_by_b}
            else
              {cycle.confirmed_by_a, true}
            end

          both_confirmed = confirmed_a and confirmed_b

          update_attrs =
            if user_id == link.user_a_id do
              %{confirmed_by_a: true}
            else
              %{confirmed_by_b: true}
            end

          update_attrs =
            if both_confirmed do
              Map.merge(update_attrs, %{
                status: :settled,
                settled_at: DateTime.utc_now() |> DateTime.truncate(:second)
              })
            else
              update_attrs
            end

          case cycle |> Ecto.Changeset.change(update_attrs) |> Repo.update() do
            {:ok, updated_cycle} ->
              if both_confirmed do
                Phoenix.PubSub.broadcast(
                  Organizer.PubSub,
                  "account_link:#{link.id}",
                  {:settlement_cycle_settled, updated_cycle}
                )

                {:ok, updated_cycle}
              else
                {:error, :awaiting_counterpart_confirmation}
              end

            error ->
              error
          end
        end
    end
  end

  @doc """
  Lists all SettlementRecords for a given SettlementCycle, ordered by transferred_at ASC.
  """
  def list_settlement_records(scope, cycle_id) do
    case find_cycle_with_link(scope, cycle_id) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _cycle, _link} ->
        records =
          from(sr in SettlementRecord,
            where: sr.settlement_cycle_id == ^cycle_id,
            preload: [:reversed_by, allocations: [shared_entry_debt: :finance_entry]],
            order_by: [asc: sr.transferred_at, asc: sr.inserted_at]
          )
          |> Repo.all()

        {:ok, records}
    end
  end

  def list_settlement_records_with_meta(scope, cycle_id, params \\ %{}) do
    case find_cycle_with_link(scope, cycle_id) do
      {:error, reason} ->
        {:error, reason}

      {:ok, _cycle, _link} ->
        query =
          from(sr in SettlementRecord,
            where: sr.settlement_cycle_id == ^cycle_id,
            preload: [:reversed_by, allocations: [shared_entry_debt: :finance_entry]]
          )
          |> maybe_filter_settlement_records_query(params)

        case Flop.validate_and_run(query, shared_flop_params(params),
               for: SettlementRecord,
               repo: Repo
             ) do
          {:ok, {records, meta}} ->
            {:ok, {records, meta}}

          {:error, %Flop.Meta{} = meta} ->
            {:error, {:validation, %{pagination: flop_error_messages(meta)}}}
        end
    end
  end

  @doc """
  Lists all SettlementCycles for a given AccountLink, ordered by (reference_year DESC, reference_month DESC).
  """
  def list_settlement_cycles(scope, link_id) do
    case get_account_link(scope, link_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, _link} ->
        cycles =
          from(sc in SettlementCycle,
            where: sc.account_link_id == ^link_id,
            order_by: [desc: sc.reference_year, desc: sc.reference_month]
          )
          |> Repo.all()

        {:ok, cycles}
    end
  end

  @doc """
  Lists shared entry debts for an account link.
  """
  def list_shared_entry_debts(scope, link_id, opts \\ %{}) do
    with {:ok, _link} <- get_account_link(scope, link_id) do
      statuses =
        opts
        |> extract_statuses_option(SharedEntryDebt.statuses())

      from(d in SharedEntryDebt,
        where: d.account_link_id == ^link_id and d.status in ^statuses,
        preload: [:finance_entry],
        order_by: [asc: d.reference_year, asc: d.reference_month, asc: d.id]
      )
      |> Repo.all()
      |> then(&{:ok, &1})
    end
  end

  def list_shared_entry_debts_with_meta(scope, link_id, opts \\ %{}) do
    with {:ok, _link} <- get_account_link(scope, link_id) do
      statuses =
        opts
        |> extract_statuses_option(SharedEntryDebt.statuses())

      query =
        from(d in SharedEntryDebt,
          where: d.account_link_id == ^link_id and d.status in ^statuses,
          join: fe in assoc(d, :finance_entry),
          preload: [finance_entry: fe],
          order_by: [asc: d.reference_year, asc: d.reference_month, asc: d.id]
        )
        |> maybe_filter_shared_entry_debts_query(opts)

      case Flop.validate_and_run(query, shared_flop_params(opts),
             for: SharedEntryDebt,
             repo: Repo
           ) do
        {:ok, {debts, meta}} ->
          {:ok, {debts, meta}}

        {:error, %Flop.Meta{} = meta} ->
          {:error, {:validation, %{pagination: flop_error_messages(meta)}}}
      end
    end
  end

  @doc """
  Lists settlement records for a link, preloading allocation breakdown.
  """
  def list_settlement_records_with_allocations(scope, link_id) do
    with {:ok, _link} <- get_account_link(scope, link_id) do
      records =
        from(sr in SettlementRecord,
          join: sc in SettlementCycle,
          on: sc.id == sr.settlement_cycle_id,
          where: sc.account_link_id == ^link_id,
          preload: [:reversed_by, allocations: [shared_entry_debt: :finance_entry]],
          order_by: [asc: sr.transferred_at, asc: sr.inserted_at]
        )
        |> Repo.all()

      {:ok, records}
    end
  end

  @doc """
  Builds current month + next months debt summary for the given link.
  """
  def monthly_debt_summaries(scope, link_id, opts \\ %{}) do
    with {:ok, _link} <- get_account_link(scope, link_id) do
      months_ahead =
        opts
        |> Map.get(:months_ahead, Map.get(opts, "months_ahead", 3))
        |> parse_positive_integer_or_default(3)

      start = Date.beginning_of_month(Date.utc_today())

      summaries =
        Enum.map(0..months_ahead, fn offset ->
          date = shift_months(start, offset)
          build_monthly_debt_summary(link_id, date)
        end)

      {:ok, summaries}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp active_link_exists?(user_a_id, user_b_id) do
    Repo.exists?(
      from l in AccountLink,
        where:
          l.status == :active and
            ((l.user_a_id == ^user_a_id and l.user_b_id == ^user_b_id) or
               (l.user_a_id == ^user_b_id and l.user_b_id == ^user_a_id))
    )
  end

  defp do_accept_invite(invite, acceptor_id) do
    Repo.transaction(fn ->
      case Repo.update(Ecto.Changeset.change(invite, %{status: :accepted})) do
        {:ok, _updated_invite} ->
          %AccountLink{}
          |> Ecto.Changeset.change(%{
            user_a_id: invite.inviter_id,
            user_b_id: acceptor_id,
            status: :active,
            invite_id: invite.id
          })
          |> Repo.insert()
          |> case do
            {:ok, account_link} -> account_link
            {:error, changeset} -> Repo.rollback(changeset)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, account_link} -> {:ok, account_link}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp sync_shared_entry_debt(%FinanceEntry{} = entry, %AccountLink{} = link) do
    cond do
      entry.kind != :expense or entry.shared_with_link_id != link.id ->
        remove_shared_entry_debt(entry.id)

      true ->
        snapshot = debt_snapshot_for_entry(entry, link)

        if snapshot.original_amount_cents <= 0 do
          remove_shared_entry_debt(entry.id)
        else
          case Repo.get_by(SharedEntryDebt, finance_entry_id: entry.id) do
            nil ->
              %SharedEntryDebt{}
              |> SharedEntryDebt.changeset(snapshot)
              |> Repo.insert()
              |> case do
                {:ok, _} -> :ok
                {:error, _} = error -> error
              end

            %SharedEntryDebt{} = debt ->
              if shared_entry_has_allocations?(entry.id) and
                   debt.original_amount_cents != snapshot.original_amount_cents do
                {:error, :shared_entry_has_allocations}
              else
                debt
                |> SharedEntryDebt.changeset(%{
                  account_link_id: snapshot.account_link_id,
                  debtor_id: snapshot.debtor_id,
                  creditor_id: snapshot.creditor_id,
                  reference_month: snapshot.reference_month,
                  reference_year: snapshot.reference_year,
                  original_amount_cents: snapshot.original_amount_cents,
                  outstanding_amount_cents:
                    if(shared_entry_has_allocations?(entry.id),
                      do: debt.outstanding_amount_cents,
                      else: snapshot.original_amount_cents
                    ),
                  status:
                    if(shared_entry_has_allocations?(entry.id),
                      do: debt.status,
                      else: :open
                    )
                })
                |> Repo.update()
                |> case do
                  {:ok, _} -> :ok
                  {:error, _} = error -> error
                end
              end
          end
        end
    end
  end

  defp remove_shared_entry_debt(entry_id) do
    case Repo.get_by(SharedEntryDebt, finance_entry_id: entry_id) do
      nil ->
        :ok

      debt ->
        if active_allocation_exists_for_debt?(debt.id) do
          {:error, :shared_entry_has_allocations}
        else
          _ = Repo.delete(debt)
          :ok
        end
    end
  end

  defp shared_entry_has_allocations?(entry_id) do
    Repo.exists?(
      from a in SettlementRecordAllocation,
        join: d in SharedEntryDebt,
        on: d.id == a.shared_entry_debt_id,
        join: sr in SettlementRecord,
        on: sr.id == a.settlement_record_id,
        where: d.finance_entry_id == ^entry_id and sr.status == :active
    )
  end

  defp debt_snapshot_for_entry(entry, link) do
    split = resolve_entry_split(entry, link, build_income_split_context(link, entry.occurred_on))

    {debtor_id, creditor_id, original_amount_cents} =
      cond do
        entry.user_id == link.user_a_id ->
          {link.user_b_id, link.user_a_id, split.amount_b_cents}

        entry.user_id == link.user_b_id ->
          {link.user_a_id, link.user_b_id, split.amount_a_cents}

        true ->
          {link.user_b_id, link.user_a_id, split.amount_b_cents}
      end

    %{
      account_link_id: link.id,
      finance_entry_id: entry.id,
      debtor_id: debtor_id,
      creditor_id: creditor_id,
      reference_month: entry.occurred_on.month,
      reference_year: entry.occurred_on.year,
      original_amount_cents: original_amount_cents,
      outstanding_amount_cents: original_amount_cents,
      status: :open
    }
  end

  defp list_open_debts_for_payment(link_id, debtor_id, creditor_id) do
    from(d in SharedEntryDebt,
      where:
        d.account_link_id == ^link_id and
          d.debtor_id == ^debtor_id and
          d.creditor_id == ^creditor_id and
          d.status in [:open, :partial],
      order_by: [asc: d.reference_year, asc: d.reference_month, asc: d.id]
    )
    |> Repo.all()
  end

  defp find_open_debt_for_payment(link_id, debt_id, debtor_id) do
    query =
      from(d in SharedEntryDebt,
        where:
          d.id == ^debt_id and
            d.account_link_id == ^link_id and
            d.debtor_id == ^debtor_id and
            d.status in [:open, :partial]
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      debt -> {:ok, debt}
    end
  end

  defp allocate_record_fifo(record, debts) do
    remaining =
      Enum.reduce_while(debts, record.amount_cents, fn debt, pending_amount ->
        if pending_amount <= 0 do
          {:halt, pending_amount}
        else
          allocated_amount = min(pending_amount, debt.outstanding_amount_cents)
          new_outstanding = debt.outstanding_amount_cents - allocated_amount

          with {:ok, _allocation} <-
                 %SettlementRecordAllocation{}
                 |> SettlementRecordAllocation.changeset(%{
                   settlement_record_id: record.id,
                   shared_entry_debt_id: debt.id,
                   amount_cents: allocated_amount
                 })
                 |> Repo.insert(),
               {:ok, _updated_debt} <-
                 debt
                 |> SharedEntryDebt.changeset(%{
                   outstanding_amount_cents: new_outstanding,
                   status:
                     debt_status_from_outstanding(new_outstanding, debt.original_amount_cents)
                 })
                 |> Repo.update() do
            {:cont, pending_amount - allocated_amount}
          else
            {:error, _reason} ->
              {:halt, -1}
          end
        end
      end)

    cond do
      remaining == 0 ->
        :ok

      remaining > 0 ->
        {:error, {:validation, %{amount_cents: ["could not allocate full payment"]}}}

      true ->
        {:error, {:validation, %{amount_cents: ["allocation failed"]}}}
    end
  end

  defp allocate_record_to_debt(record, debt, amount_cents)
       when is_integer(amount_cents) and amount_cents > 0 do
    if amount_cents > debt.outstanding_amount_cents do
      {:error, {:validation, %{amount_cents: ["cannot exceed selected debt outstanding amount"]}}}
    else
      new_outstanding = debt.outstanding_amount_cents - amount_cents

      with {:ok, _allocation} <-
             %SettlementRecordAllocation{}
             |> SettlementRecordAllocation.changeset(%{
               settlement_record_id: record.id,
               shared_entry_debt_id: debt.id,
               amount_cents: amount_cents
             })
             |> Repo.insert(),
           {:ok, _updated_debt} <-
             debt
             |> SharedEntryDebt.changeset(%{
               outstanding_amount_cents: new_outstanding,
               status: debt_status_from_outstanding(new_outstanding, debt.original_amount_cents)
             })
             |> Repo.update() do
        :ok
      else
        {:error, _reason} ->
          {:error, {:validation, %{amount_cents: ["allocation failed"]}}}
      end
    end
  end

  defp restore_allocated_debts(allocations) when is_list(allocations) do
    Enum.reduce_while(allocations, :ok, fn allocation, :ok ->
      debt = allocation.shared_entry_debt

      if is_nil(debt) do
        {:halt, {:error, :allocation_debt_not_found}}
      else
        updated_outstanding = debt.outstanding_amount_cents + allocation.amount_cents

        if updated_outstanding > debt.original_amount_cents do
          {:halt, {:error, :allocation_restore_out_of_bounds}}
        else
          case debt
               |> SharedEntryDebt.changeset(%{
                 outstanding_amount_cents: updated_outstanding,
                 status:
                   debt_status_from_outstanding(updated_outstanding, debt.original_amount_cents)
               })
               |> Repo.update() do
            {:ok, _updated_debt} -> {:cont, :ok}
            {:error, _changeset} -> {:halt, {:error, :allocation_restore_failed}}
          end
        end
      end
    end)
  end

  defp active_allocation_exists_for_debt?(debt_id) do
    Repo.exists?(
      from a in SettlementRecordAllocation,
        join: sr in SettlementRecord,
        on: sr.id == a.settlement_record_id,
        where: a.shared_entry_debt_id == ^debt_id and sr.status == :active
    )
  end

  defp debt_status_from_outstanding(0, _original), do: :settled

  defp debt_status_from_outstanding(outstanding, original)
       when is_integer(outstanding) and is_integer(original) and outstanding < original,
       do: :partial

  defp debt_status_from_outstanding(_outstanding, _original), do: :open

  defp refresh_cycle_status(cycle) do
    totals =
      from(d in SharedEntryDebt,
        where:
          d.account_link_id == ^cycle.account_link_id and
            d.reference_month == ^cycle.reference_month and
            d.reference_year == ^cycle.reference_year and d.status in [:open, :partial],
        select: %{outstanding_total: coalesce(sum(d.outstanding_amount_cents), 0)}
      )
      |> Repo.one()

    outstanding_total = (totals && totals.outstanding_total) || 0

    debtor_id =
      from(d in SharedEntryDebt,
        where:
          d.account_link_id == ^cycle.account_link_id and
            d.reference_month == ^cycle.reference_month and
            d.reference_year == ^cycle.reference_year and d.status in [:open, :partial],
        group_by: d.debtor_id,
        order_by: [desc: sum(d.outstanding_amount_cents)],
        limit: 1,
        select: d.debtor_id
      )
      |> Repo.one()

    attrs =
      if outstanding_total > 0 do
        %{
          balance_cents: outstanding_total,
          debtor_id: debtor_id,
          status: :open,
          settled_at: nil,
          confirmed_by_a: false,
          confirmed_by_b: false
        }
      else
        %{
          balance_cents: 0,
          debtor_id: nil
        }
      end

    cycle
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
    |> case do
      {:ok, _updated_cycle} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp pending_debts_for_cycle?(cycle) do
    Repo.exists?(
      from d in SharedEntryDebt,
        where:
          d.account_link_id == ^cycle.account_link_id and
            d.reference_month == ^cycle.reference_month and
            d.reference_year == ^cycle.reference_year and d.status in [:open, :partial]
    )
  end

  defp build_monthly_debt_summary(link_id, reference_date) do
    debts =
      from(d in SharedEntryDebt,
        where:
          d.account_link_id == ^link_id and d.reference_month == ^reference_date.month and
            d.reference_year == ^reference_date.year
      )
      |> Repo.all()

    original_amount_cents = Enum.reduce(debts, 0, &(&1.original_amount_cents + &2))
    outstanding_amount_cents = Enum.reduce(debts, 0, &(&1.outstanding_amount_cents + &2))

    status =
      cond do
        original_amount_cents == 0 -> :settled
        outstanding_amount_cents == 0 -> :settled
        outstanding_amount_cents < original_amount_cents -> :partial
        true -> :open
      end

    cycle =
      Repo.get_by(
        SettlementCycle,
        account_link_id: link_id,
        reference_month: reference_date.month,
        reference_year: reference_date.year
      )

    %MonthlyDebtSummary{
      reference_month: reference_date.month,
      reference_year: reference_date.year,
      original_amount_cents: original_amount_cents,
      outstanding_amount_cents: outstanding_amount_cents,
      status: status,
      confirmed_by_a: if(is_nil(cycle), do: false, else: cycle.confirmed_by_a),
      confirmed_by_b: if(is_nil(cycle), do: false, else: cycle.confirmed_by_b),
      settled: status == :settled
    }
  end

  defp parse_positive_integer_or_default(value, default) when is_integer(value) do
    if value > 0, do: value, else: default
  end

  defp parse_positive_integer_or_default(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp parse_positive_integer_or_default(_value, default), do: default

  defp sync_link_debts(scope, %AccountLink{} = link) do
    with {:ok, views} <- list_shared_entries(scope, link.id, %{period: "all"}) do
      Enum.each(views, fn view ->
        _ = sync_shared_entry_debt(view.entry, link)
      end)
    end

    :ok
  end

  defp build_income_split_context(link, reference_date) do
    income_a =
      SplitCalculator.calculate_reference_income_with_carryover(
        link.user_a_id,
        reference_date.month,
        reference_date.year
      )

    income_b =
      SplitCalculator.calculate_reference_income_with_carryover(
        link.user_b_id,
        reference_date.month,
        reference_date.year
      )

    %{
      income_a: income_a,
      income_b: income_b,
      ratios: SplitCalculator.calculate_split_ratio(income_a, income_b)
    }
  end

  defp income_context_for_entry(entry, link, income_context_cache) do
    entry_reference_date = entry.occurred_on
    cache_key = {entry_reference_date.year, entry_reference_date.month}

    case Map.get(income_context_cache, cache_key) do
      nil ->
        income_context = build_income_split_context(link, entry_reference_date)
        {entry_reference_date, income_context}

      cached_income_context ->
        {entry_reference_date, cached_income_context}
    end
  end

  defp resolve_entry_split(entry, link, income_context) do
    if entry.shared_split_mode == :manual and is_integer(entry.shared_manual_mine_cents) do
      resolve_manual_entry_split(entry, link)
    else
      {ratio_a, ratio_b, mode} =
        case income_context do
          %{income_a: 0, income_b: 0} ->
            {fallback_ratio_a, fallback_ratio_b} = owner_fallback_ratios(entry, link)
            {fallback_ratio_a, fallback_ratio_b, :owner_fallback}

          %{ratios: {context_ratio_a, context_ratio_b}} ->
            {context_ratio_a, context_ratio_b, :income_ratio}
        end

      {amount_a, amount_b} = SplitCalculator.split_amount(entry.amount_cents, ratio_a)

      %{
        mode: mode,
        ratio_a: ratio_a,
        ratio_b: ratio_b,
        amount_a_cents: amount_a,
        amount_b_cents: amount_b
      }
    end
  end

  defp resolve_manual_entry_split(entry, link) do
    total_cents = entry.amount_cents
    owner_amount_mine_cents = min(max(entry.shared_manual_mine_cents, 0), total_cents)
    owner_amount_theirs_cents = total_cents - owner_amount_mine_cents

    {amount_a, amount_b} =
      cond do
        entry.user_id == link.user_a_id ->
          {owner_amount_mine_cents, owner_amount_theirs_cents}

        entry.user_id == link.user_b_id ->
          {owner_amount_theirs_cents, owner_amount_mine_cents}

        true ->
          {owner_amount_mine_cents, owner_amount_theirs_cents}
      end

    ratio_a = if total_cents > 0, do: amount_a / total_cents, else: 0.0
    ratio_b = if total_cents > 0, do: amount_b / total_cents, else: 0.0

    %{
      mode: :manual,
      ratio_a: ratio_a,
      ratio_b: ratio_b,
      amount_a_cents: amount_a,
      amount_b_cents: amount_b
    }
  end

  defp scope_split_for_user(split, user_id, link) do
    if user_id == link.user_a_id do
      %{
        ratio_mine: split.ratio_a,
        ratio_theirs: split.ratio_b,
        amount_mine_cents: split.amount_a_cents,
        amount_theirs_cents: split.amount_b_cents
      }
    else
      %{
        ratio_mine: split.ratio_b,
        ratio_theirs: split.ratio_a,
        amount_mine_cents: split.amount_b_cents,
        amount_theirs_cents: split.amount_a_cents
      }
    end
  end

  defp resolve_metrics_ratios(income_a, income_b, filtered_views, link) do
    if income_a == 0 and income_b == 0 do
      fallback_ratios_from_entry_ownership(filtered_views, link)
    else
      SplitCalculator.calculate_split_ratio(income_a, income_b)
    end
  end

  defp fallback_ratios_from_entry_ownership(filtered_views, link) do
    totals =
      Enum.reduce(filtered_views, %{a: 0, b: 0}, fn view, acc ->
        cond do
          view.entry.user_id == link.user_a_id ->
            %{acc | a: acc.a + view.entry.amount_cents}

          view.entry.user_id == link.user_b_id ->
            %{acc | b: acc.b + view.entry.amount_cents}

          true ->
            acc
        end
      end)

    total = totals.a + totals.b

    if total > 0 do
      {totals.a / total, totals.b / total}
    else
      {1.0, 0.0}
    end
  end

  defp owner_fallback_ratios(entry, link) do
    if entry.user_id == link.user_b_id do
      {0.0, 1.0}
    else
      {1.0, 0.0}
    end
  end

  defp maybe_persist_split_snapshot(
         false,
         _entry,
         _link,
         _reference_date,
         _split,
         _income_context
       ),
       do: :ok

  defp maybe_persist_split_snapshot(
         true,
         entry,
         link,
         reference_date,
         split,
         income_context
       ) do
    latest_snapshot =
      Repo.one(
        from ss in SharedSplitSnapshot,
          where:
            ss.finance_entry_id == ^entry.id and
              ss.reference_month == ^reference_date.month and
              ss.reference_year == ^reference_date.year,
          order_by: [desc: ss.calculated_at],
          limit: 1
      )

    if snapshot_changed?(latest_snapshot, split, income_context) do
      attrs = %{
        account_link_id: link.id,
        finance_entry_id: entry.id,
        reference_month: reference_date.month,
        reference_year: reference_date.year,
        split_mode: split.mode,
        ratio_a: split.ratio_a,
        ratio_b: split.ratio_b,
        amount_a_cents: split.amount_a_cents,
        amount_b_cents: split.amount_b_cents,
        income_a_cents: income_context.income_a,
        income_b_cents: income_context.income_b,
        calculated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      %SharedSplitSnapshot{}
      |> SharedSplitSnapshot.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, _snapshot} -> :ok
        _ -> :error
      end
    else
      :ok
    end
  end

  defp snapshot_changed?(nil, _split, _income_context), do: true

  defp snapshot_changed?(snapshot, split, income_context) do
    snapshot.split_mode != split.mode or
      ratio_changed?(snapshot.ratio_a, split.ratio_a) or
      ratio_changed?(snapshot.ratio_b, split.ratio_b) or
      snapshot.amount_a_cents != split.amount_a_cents or
      snapshot.amount_b_cents != split.amount_b_cents or
      snapshot.income_a_cents != income_context.income_a or
      snapshot.income_b_cents != income_context.income_b
  end

  defp ratio_changed?(left, right) when is_number(left) and is_number(right) do
    abs(left - right) > 1.0e-9
  end

  defp ratio_changed?(left, right), do: left != right

  defp normalize_share_attrs(entry, attrs) when is_map(attrs) do
    mode =
      attrs
      |> Map.get("shared_split_mode", Map.get(attrs, :shared_split_mode, "income_ratio"))
      |> to_string()
      |> String.trim()
      |> case do
        "manual" -> :manual
        _ -> :income_ratio
      end

    case mode do
      :income_ratio ->
        {:ok, %{shared_split_mode: :income_ratio, shared_manual_mine_cents: nil}}

      :manual ->
        parse_manual_share_mine_cents(attrs)
        |> case do
          {:ok, mine_cents} ->
            cond do
              mine_cents < 0 ->
                {:error,
                 {:validation,
                  %{shared_manual_mine_cents: ["must be greater than or equal to 0"]}}}

              mine_cents > entry.amount_cents ->
                {:error,
                 {:validation,
                  %{shared_manual_mine_cents: ["must be less than or equal to total amount"]}}}

              true ->
                {:ok, %{shared_split_mode: :manual, shared_manual_mine_cents: mine_cents}}
            end

          :error ->
            {:error,
             {:validation,
              %{shared_manual_mine_cents: ["must be a valid non-negative monetary value"]}}}
        end
    end
  end

  defp parse_manual_share_mine_cents(attrs) when is_map(attrs) do
    cond do
      is_integer(Map.get(attrs, :shared_manual_mine_cents)) ->
        {:ok, Map.get(attrs, :shared_manual_mine_cents)}

      is_integer(Map.get(attrs, "shared_manual_mine_cents")) ->
        {:ok, Map.get(attrs, "shared_manual_mine_cents")}

      true ->
        attrs
        |> Map.get("shared_manual_mine_amount", Map.get(attrs, :shared_manual_mine_amount))
        |> case do
          value when is_binary(value) ->
            case AmountParser.parse(String.trim(value)) do
              {:ok, cents} -> {:ok, cents}
              _ -> :error
            end

          nil ->
            :error

          value ->
            case AmountParser.parse(value) do
              {:ok, cents} -> {:ok, cents}
              _ -> :error
            end
        end
    end
  end

  defp shared_entry_owned_by_user(user_id, link_id, entry_id) do
    Repo.one(
      from fe in FinanceEntry,
        where:
          fe.id == ^entry_id and
            fe.user_id == ^user_id and
            fe.shared_with_link_id == ^link_id
    )
  end

  defp normalize_shared_entry_update_attrs(entry, attrs) when is_map(attrs) do
    with {:ok, amount_cents} <- parse_shared_entry_update_amount(attrs, entry),
         {:ok, occurred_on} <- parse_shared_entry_update_occurred_on(attrs, entry),
         {:ok, split_attrs} <- normalize_shared_entry_update_split_attrs(attrs, amount_cents) do
      category =
        attrs
        |> Map.get("category", Map.get(attrs, :category, entry.category))
        |> to_string()
        |> String.trim()

      description =
        attrs
        |> Map.get("description", Map.get(attrs, :description, entry.description))
        |> normalize_optional_description()

      {:ok,
       %{
         kind: entry.kind,
         expense_profile: entry.expense_profile,
         payment_method: entry.payment_method,
         installment_number: entry.installment_number,
         installments_count: entry.installments_count,
         amount_cents: amount_cents,
         category: category,
         description: description,
         occurred_on: occurred_on,
         shared_with_link_id: entry.shared_with_link_id,
         shared_split_mode: split_attrs.shared_split_mode,
         shared_manual_mine_cents: split_attrs.shared_manual_mine_cents
       }}
    end
  end

  defp normalize_optional_description(nil), do: nil

  defp normalize_optional_description(value) when is_binary(value) do
    cleaned = String.trim(value)
    if cleaned == "", do: nil, else: cleaned
  end

  defp normalize_optional_description(value), do: to_string(value)

  defp parse_shared_entry_update_amount(attrs, entry) do
    value = Map.get(attrs, "amount_cents", Map.get(attrs, :amount_cents, entry.amount_cents))

    case parse_non_negative_amount(value) do
      {:ok, cents} when cents > 0 ->
        {:ok, cents}

      _ ->
        {:error, {:validation, %{amount_cents: ["must be a valid positive monetary value"]}}}
    end
  end

  defp parse_shared_entry_update_occurred_on(attrs, entry) do
    value = Map.get(attrs, "occurred_on", Map.get(attrs, :occurred_on, entry.occurred_on))

    case DateSupport.parse_date(value) do
      {:ok, date} ->
        {:ok, date}

      :error ->
        {:error, {:validation, %{occurred_on: ["must be a valid date"]}}}
    end
  end

  defp normalize_shared_entry_update_split_attrs(attrs, total_cents) do
    split_type =
      attrs
      |> Map.get("split_type", Map.get(attrs, :split_type, "income_ratio"))
      |> to_string()
      |> String.trim()
      |> case do
        "percentage" -> "percentage"
        "fixed_amount" -> "fixed_amount"
        _ -> "income_ratio"
      end

    case split_type do
      "income_ratio" ->
        {:ok, %{shared_split_mode: :income_ratio, shared_manual_mine_cents: nil}}

      "percentage" ->
        attrs
        |> Map.get("split_mine_percentage", Map.get(attrs, :split_mine_percentage))
        |> parse_shared_split_percentage()
        |> case do
          {:ok, pct} ->
            if pct < 0.0 or pct > 100.0 do
              {:error, {:validation, %{split_mine_percentage: ["must be between 0 and 100"]}}}
            else
              mine_cents = round(total_cents * pct / 100)
              {:ok, %{shared_split_mode: :manual, shared_manual_mine_cents: mine_cents}}
            end

          :error ->
            {:error, {:validation, %{split_mine_percentage: ["must be a valid percentage"]}}}
        end

      "fixed_amount" ->
        attrs
        |> Map.get("split_mine_amount", Map.get(attrs, :split_mine_amount))
        |> parse_non_negative_amount()
        |> case do
          {:ok, mine_cents} when mine_cents >= 0 and mine_cents <= total_cents ->
            {:ok, %{shared_split_mode: :manual, shared_manual_mine_cents: mine_cents}}

          {:ok, _mine_cents} ->
            {:error,
             {:validation,
              %{split_mine_amount: ["must be greater than or equal to 0 and up to total amount"]}}}

          _ ->
            {:error,
             {:validation, %{split_mine_amount: ["must be a valid non-negative monetary value"]}}}
        end
    end
  end

  defp parse_non_negative_amount(value) when is_integer(value), do: AmountParser.parse(value)

  defp parse_non_negative_amount(value) when is_binary(value),
    do: AmountParser.parse(String.trim(value))

  defp parse_non_negative_amount(_value), do: :error

  defp parse_shared_split_percentage(value) when is_binary(value) do
    cleaned =
      value
      |> String.trim()
      |> String.replace("%", "")

    if cleaned == "" do
      :error
    else
      normalized =
        cond do
          String.contains?(cleaned, ",") and String.contains?(cleaned, ".") ->
            if last_char_index(cleaned, ",") > last_char_index(cleaned, ".") do
              cleaned |> String.replace(".", "") |> String.replace(",", ".")
            else
              String.replace(cleaned, ",", "")
            end

          String.contains?(cleaned, ",") ->
            String.replace(cleaned, ",", ".")

          true ->
            cleaned
        end

      case Float.parse(normalized) do
        {pct, ""} -> {:ok, pct}
        _ -> :error
      end
    end
  end

  defp parse_shared_split_percentage(value) when is_integer(value), do: {:ok, value * 1.0}
  defp parse_shared_split_percentage(value) when is_float(value), do: {:ok, value}
  defp parse_shared_split_percentage(_value), do: :error

  defp last_char_index(string, char) do
    string
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.filter(fn {value, _index} -> value == char end)
    |> List.last()
    |> case do
      {_, index} -> index
      nil -> -1
    end
  end

  defp normalize_shared_period(params) when is_map(params) do
    period = Map.get(params, :period) || Map.get(params, "period")

    case to_string(period) do
      "current_month" -> "current_month"
      "last_3_months" -> "last_3_months"
      "all" -> "all"
      _ -> "all"
    end
  end

  defp normalize_shared_period(_params), do: "all"

  defp normalize_persist_snapshots_flag(params) when is_map(params) do
    value = Map.get(params, :persist_snapshots, Map.get(params, "persist_snapshots", true))

    case value do
      false -> false
      "false" -> false
      "0" -> false
      0 -> false
      _ -> true
    end
  end

  defp normalize_reference_date(%Date{} = date), do: date
  defp normalize_reference_date(_), do: Date.utc_today()

  defp apply_shared_period_filter_query(query, "all", reference_date) do
    end_on = Date.end_of_month(reference_date)
    from f in query, where: f.occurred_on <= ^end_on
  end

  defp apply_shared_period_filter_query(query, period, reference_date) do
    end_on = Date.end_of_month(reference_date)

    start_on =
      case period do
        "current_month" ->
          Date.beginning_of_month(reference_date)

        "last_3_months" ->
          reference_date
          |> shift_months(-2)
          |> Date.beginning_of_month()

        _ ->
          Date.beginning_of_month(reference_date)
      end

    from f in query, where: f.occurred_on >= ^start_on and f.occurred_on <= ^end_on
  end

  defp maybe_filter_account_links_query(query, params) do
    case extract_filter_q(params) do
      nil ->
        query

      q ->
        like_q = "%#{q}%"

        from l in query,
          join: ua in assoc(l, :user_a),
          join: ub in assoc(l, :user_b),
          where: ilike(ua.email, ^like_q) or ilike(ub.email, ^like_q)
    end
  end

  defp maybe_filter_shared_entries_query(query, params) do
    case extract_filter_q(params) do
      nil ->
        query

      q ->
        like_q = "%#{q}%"

        from fe in query,
          where: ilike(fe.description, ^like_q) or ilike(fe.category, ^like_q)
    end
  end

  defp maybe_filter_shared_entry_debts_query(query, params) do
    case extract_filter_q(params) do
      nil ->
        query

      q ->
        like_q = "%#{q}%"

        from [d, fe] in query,
          where: ilike(fe.description, ^like_q) or ilike(fe.category, ^like_q)
    end
  end

  defp maybe_filter_settlement_records_query(query, params) do
    case extract_filter_q(params) do
      nil ->
        query

      q ->
        like_q = "%#{q}%"

        from sr in query,
          where:
            ilike(fragment("CAST(? AS TEXT)", sr.method), ^like_q) or
              ilike(fragment("strftime('%d/%m/%Y', ?)", sr.transferred_at), ^like_q) or
              ilike(fragment("CAST(? AS TEXT)", sr.amount_cents), ^like_q) or
              ilike(fragment("CAST(? AS TEXT)", sr.status), ^like_q) or
              ilike(fragment("strftime('%d/%m/%Y', ?)", sr.reversed_at), ^like_q) or
              ilike(sr.reversal_reason, ^like_q)
    end
  end

  defp extract_filter_q(params) when is_map(params) do
    params
    |> Map.get(:q, Map.get(params, "q"))
    |> normalize_filter_q()
  end

  defp extract_filter_q(_params), do: nil

  defp extract_statuses_option(opts, default_statuses) when is_map(opts) do
    opts
    |> Map.get(:statuses, Map.get(opts, "statuses", default_statuses))
    |> List.wrap()
    |> Enum.map(fn
      status when is_atom(status) -> status
      status when is_binary(status) -> parse_status_atom(status)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&(&1 in SharedEntryDebt.statuses()))
  end

  defp extract_statuses_option(_opts, default_statuses), do: default_statuses

  defp parse_status_atom(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" ->
        nil

      normalized ->
        case normalized do
          "open" -> :open
          "partial" -> :partial
          "settled" -> :settled
          _ -> nil
        end
    end
  end

  defp normalize_filter_q(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      q -> q
    end
  end

  defp normalize_filter_q(_value), do: nil

  defp shared_flop_params(params) when is_map(params) do
    params
    |> Map.take([
      "page",
      :page,
      "page_size",
      :page_size,
      "limit",
      :limit,
      "offset",
      :offset,
      "order_by",
      :order_by,
      "order_directions",
      :order_directions
    ])
    |> Enum.reduce(%{}, fn
      {"page", value}, acc -> Map.put(acc, :page, value)
      {:page, value}, acc -> Map.put(acc, :page, value)
      {"page_size", value}, acc -> Map.put(acc, :page_size, value)
      {:page_size, value}, acc -> Map.put(acc, :page_size, value)
      {"limit", value}, acc -> Map.put(acc, :limit, value)
      {:limit, value}, acc -> Map.put(acc, :limit, value)
      {"offset", value}, acc -> Map.put(acc, :offset, value)
      {:offset, value}, acc -> Map.put(acc, :offset, value)
      {"order_by", value}, acc -> Map.put(acc, :order_by, value)
      {:order_by, value}, acc -> Map.put(acc, :order_by, value)
      {"order_directions", value}, acc -> Map.put(acc, :order_directions, value)
      {:order_directions, value}, acc -> Map.put(acc, :order_directions, value)
      _, acc -> acc
    end)
  end

  defp shared_flop_params(_params), do: %{}

  defp flop_error_messages(%Flop.Meta{errors: errors}) when is_list(errors) do
    Enum.map(errors, fn {field, field_errors} ->
      messages =
        Enum.map(field_errors, fn {message, opts} ->
          Enum.reduce(opts, message, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)

      "#{field}: #{Enum.join(messages, ", ")}"
    end)
  end

  defp shift_months(%Date{} = date, delta_months) when is_integer(delta_months) do
    month_index = date.year * 12 + (date.month - 1) + delta_months
    new_year = div(month_index, 12)
    new_month = rem(month_index, 12) + 1

    Date.new!(new_year, new_month, 1)
  end

  defp scoped_ratios(user_id, link, ratio_a, ratio_b) do
    if user_id == link.user_a_id do
      {ratio_a, ratio_b}
    else
      {ratio_b, ratio_a}
    end
  end

  defp find_cycle_with_link(scope, cycle_id) do
    user_id = scope.user.id

    query =
      from sc in SettlementCycle,
        join: l in AccountLink,
        on: l.id == sc.account_link_id,
        where:
          sc.id == ^cycle_id and
            l.status == :active and
            (l.user_a_id == ^user_id or l.user_b_id == ^user_id),
        preload: [account_link: l]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      cycle -> {:ok, cycle, cycle.account_link}
    end
  end

  defp find_record_with_link(scope, settlement_record_id) do
    user_id = scope.user.id

    query =
      from sr in SettlementRecord,
        join: sc in SettlementCycle,
        on: sc.id == sr.settlement_cycle_id,
        join: l in AccountLink,
        on: l.id == sc.account_link_id,
        where:
          sr.id == ^settlement_record_id and
            l.status == :active and
            (l.user_a_id == ^user_id or l.user_b_id == ^user_id),
        select: {sr, sc, l}

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      {record, cycle, link} ->
        {:ok, record, cycle, link}
    end
  end
end
