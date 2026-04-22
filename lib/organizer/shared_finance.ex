defmodule Organizer.SharedFinance do
  @moduledoc """
  Context for shared finance features: invites, account links, shared entries,
  metrics, and settlement cycles.
  """

  import Ecto.Query

  alias Organizer.Repo
  alias Organizer.Planning.AmountParser
  alias Organizer.SharedFinance.{AccountLink, Invite}
  alias Organizer.Planning.FinanceEntry

  alias Organizer.SharedFinance.{
    SharedEntryView,
    SplitCalculator,
    LinkMetricsCalculator,
    SettlementCycle,
    SettlementRecord
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
    user_id = scope.user.id

    links =
      from(l in AccountLink,
        where:
          l.status == :active and
            (l.user_a_id == ^user_id or l.user_b_id == ^user_id),
        preload: [:user_a, :user_b]
      )
      |> Repo.all()

    {:ok, links}
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
            (l.user_a_id == ^user_id or l.user_b_id == ^user_id),
        preload: [:user_a, :user_b]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      link -> {:ok, link}
    end
  end

  # ---------------------------------------------------------------------------
  # Lançamentos compartilhados
  # ---------------------------------------------------------------------------

  @doc """
  Marks a FinanceEntry as shared with an AccountLink.
  Verifies the entry belongs to the user and the user is a participant of the link.
  Broadcasts a PubSub event after successful update.
  """
  def share_finance_entry(scope, entry_id, link_id, attrs \\ %{}) do
    user_id = scope.user.id

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

          {:ok, _link} ->
            with {:ok, share_attrs} <- normalize_share_attrs(entry, attrs),
                 {:ok, updated_entry} <-
                   entry
                   |> Ecto.Changeset.change(Map.put(share_attrs, :shared_with_link_id, link_id))
                   |> Repo.update() do
              Phoenix.PubSub.broadcast(
                Organizer.PubSub,
                "account_link:#{link_id}",
                {:shared_entry_updated, updated_entry}
              )

              {:ok, updated_entry}
            else
              {:error, _reason} = error -> error
            end
        end
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
        link_id = entry.shared_with_link_id

        case entry
             |> Ecto.Changeset.change(%{
               shared_with_link_id: nil,
               shared_split_mode: nil,
               shared_manual_mine_cents: nil
             })
             |> Repo.update() do
          {:ok, updated_entry} = result ->
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

  @doc """
  Lists all FinanceEntries shared with a given AccountLink, with split ratios calculated
  for each entry month based on each user's reference income.
  Returns `{:error, :not_found}` if the user is not a participant of the link.
  """
  def list_shared_entries(scope, link_id, params \\ %{}) do
    case get_account_link(scope, link_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, link} ->
        period = normalize_shared_period(params)
        reference_date = normalize_reference_date(Map.get(params, :reference_date))

        entries =
          from(fe in FinanceEntry, where: fe.shared_with_link_id == ^link_id)
          |> Repo.all()
          |> apply_shared_period_filter(period, reference_date)

        user_id = scope.user.id
        ratio_by_period = build_ratio_by_period(entries, link)

        views =
          Enum.map(entries, fn entry ->
            period_info =
              Map.fetch!(ratio_by_period, {entry.occurred_on.year, entry.occurred_on.month})

            split = resolve_entry_split(entry, link, user_id, period_info)

            %SharedEntryView{
              entry: entry,
              split_ratio_mine: split.ratio_mine,
              split_ratio_theirs: split.ratio_theirs,
              amount_mine_cents: split.amount_mine_cents,
              amount_theirs_cents: split.amount_theirs_cents
            }
          end)

        {:ok, views}
    end
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

            {:ok, cycle}

          {:ok, cycle} ->
            {:ok, cycle}

          {:error, _changeset} ->
            cycle =
              Repo.one!(
                from sc in SettlementCycle,
                  where:
                    sc.account_link_id == ^link_id and
                      sc.reference_month == ^reference_month.month and
                      sc.reference_year == ^reference_month.year
              )

            {:ok, cycle}
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

          record_attrs = %{
            settlement_cycle_id: cycle.id,
            payer_id: scope.user.id,
            receiver_id: receiver_id,
            amount_cents: amount_cents,
            method: Map.get(attrs, :method) || Map.get(attrs, "method"),
            transferred_at: Map.get(attrs, :transferred_at) || Map.get(attrs, "transferred_at")
          }

          changeset =
            %SettlementRecord{}
            |> Ecto.Changeset.change(record_attrs)

          case Repo.insert(changeset) do
            {:ok, record} = result ->
              Phoenix.PubSub.broadcast(
                Organizer.PubSub,
                "account_link:#{link.id}",
                {:settlement_record_created, record}
              )

              result

            error ->
              error
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
            order_by: [asc: sr.transferred_at]
          )
          |> Repo.all()

        {:ok, records}
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
    Ecto.Multi.new()
    |> Ecto.Multi.update(
      :invite,
      Ecto.Changeset.change(invite, %{status: :accepted})
    )
    |> Ecto.Multi.insert(:account_link, fn _changes ->
      %AccountLink{}
      |> Ecto.Changeset.change(%{
        user_a_id: invite.inviter_id,
        user_b_id: acceptor_id,
        status: :active,
        invite_id: invite.id
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{account_link: account_link}} -> {:ok, account_link}
      {:error, _op, changeset, _changes} -> {:error, changeset}
    end
  end

  defp build_ratio_by_period(entries, link) do
    entries
    |> Enum.map(fn entry -> {entry.occurred_on.year, entry.occurred_on.month} end)
    |> MapSet.new()
    |> Enum.reduce(%{}, fn {year, month}, acc ->
      income_a =
        SplitCalculator.calculate_reference_income_with_carryover(link.user_a_id, month, year)

      income_b =
        SplitCalculator.calculate_reference_income_with_carryover(link.user_b_id, month, year)

      ratios = SplitCalculator.calculate_split_ratio(income_a, income_b)

      Map.put(acc, {year, month}, %{
        income_a: income_a,
        income_b: income_b,
        ratios: ratios
      })
    end)
  end

  defp resolve_entry_split(entry, link, current_user_id, period_info) do
    if entry.shared_split_mode == :manual and is_integer(entry.shared_manual_mine_cents) do
      resolve_manual_entry_split(entry, current_user_id)
    else
      {ratio_a, ratio_b} =
        case period_info do
          %{income_a: 0, income_b: 0} ->
            owner_fallback_ratios(entry, link)

          %{ratios: {period_ratio_a, period_ratio_b}} ->
            {period_ratio_a, period_ratio_b}
        end

      {ratio_mine, ratio_theirs} = scoped_ratios(current_user_id, link, ratio_a, ratio_b)
      {amount_mine, amount_theirs} = SplitCalculator.split_amount(entry.amount_cents, ratio_mine)

      %{
        ratio_mine: ratio_mine,
        ratio_theirs: ratio_theirs,
        amount_mine_cents: amount_mine,
        amount_theirs_cents: amount_theirs
      }
    end
  end

  defp resolve_manual_entry_split(entry, current_user_id) do
    total_cents = entry.amount_cents
    owner_amount_mine_cents = min(max(entry.shared_manual_mine_cents, 0), total_cents)
    owner_amount_theirs_cents = total_cents - owner_amount_mine_cents

    {amount_mine, amount_theirs} =
      if entry.user_id == current_user_id do
        {owner_amount_mine_cents, owner_amount_theirs_cents}
      else
        {owner_amount_theirs_cents, owner_amount_mine_cents}
      end

    ratio_mine = if total_cents > 0, do: amount_mine / total_cents, else: 0.0
    ratio_theirs = if total_cents > 0, do: amount_theirs / total_cents, else: 0.0

    %{
      ratio_mine: ratio_mine,
      ratio_theirs: ratio_theirs,
      amount_mine_cents: amount_mine,
      amount_theirs_cents: amount_theirs
    }
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

  defp normalize_share_attrs(_entry, _attrs) do
    {:ok, %{shared_split_mode: :income_ratio, shared_manual_mine_cents: nil}}
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

  defp normalize_reference_date(%Date{} = date), do: date
  defp normalize_reference_date(_), do: Date.utc_today()

  defp apply_shared_period_filter(entries, "all", reference_date) do
    end_on = Date.end_of_month(reference_date)

    Enum.filter(entries, fn entry ->
      Date.compare(entry.occurred_on, end_on) != :gt
    end)
  end

  defp apply_shared_period_filter(entries, period, reference_date) do
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

    Enum.filter(entries, fn entry ->
      Date.compare(entry.occurred_on, start_on) != :lt and
        Date.compare(entry.occurred_on, end_on) != :gt
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
            (l.user_a_id == ^user_id or l.user_b_id == ^user_id),
        preload: [account_link: l]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      cycle -> {:ok, cycle, cycle.account_link}
    end
  end
end
