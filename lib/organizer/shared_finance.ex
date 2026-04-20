defmodule Organizer.SharedFinance do
  @moduledoc """
  Context for shared finance features: invites, account links, shared entries,
  metrics, and settlement cycles.
  """

  import Ecto.Query

  alias Organizer.Repo
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
  def share_finance_entry(scope, entry_id, link_id) do
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
            case entry
                 |> Ecto.Changeset.change(%{shared_with_link_id: link_id})
                 |> Repo.update() do
              {:ok, updated_entry} = result ->
                Phoenix.PubSub.broadcast(
                  Organizer.PubSub,
                  "account_link:#{link_id}",
                  {:shared_entry_updated, updated_entry}
                )

                result

              error ->
                error
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

        case entry |> Ecto.Changeset.change(%{shared_with_link_id: nil}) |> Repo.update() do
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
  def list_shared_entries(scope, link_id, _params \\ %{}) do
    case get_account_link(scope, link_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, link} ->
        entries =
          from(fe in FinanceEntry, where: fe.shared_with_link_id == ^link_id)
          |> Repo.all()

        user_id = scope.user.id
        ratio_by_period = build_ratio_by_period(entries, link)

        views =
          Enum.map(entries, fn entry ->
            {ratio_a, ratio_b} =
              Map.fetch!(ratio_by_period, {entry.occurred_on.year, entry.occurred_on.month})

            {ratio_mine, ratio_theirs} = scoped_ratios(user_id, link, ratio_a, ratio_b)

            {amount_mine, amount_theirs} =
              SplitCalculator.split_amount(entry.amount_cents, ratio_mine)

            %SharedEntryView{
              entry: entry,
              split_ratio_mine: ratio_mine,
              split_ratio_theirs: ratio_theirs,
              amount_mine_cents: amount_mine,
              amount_theirs_cents: amount_theirs
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
  def get_link_metrics(scope, link_id, reference_month) do
    case get_account_link(scope, link_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, link} ->
        {:ok, all_views} = list_shared_entries(scope, link_id)

        filtered_views =
          Enum.filter(all_views, fn view ->
            view.entry.occurred_on.month == reference_month.month and
              view.entry.occurred_on.year == reference_month.year
          end)

        income_a =
          SplitCalculator.calculate_reference_income(
            link.user_a_id,
            reference_month.month,
            reference_month.year
          )

        income_b =
          SplitCalculator.calculate_reference_income(
            link.user_b_id,
            reference_month.month,
            reference_month.year
          )

        {ratio_a, ratio_b} = SplitCalculator.calculate_split_ratio(income_a, income_b)

        {split_ratio_a, split_ratio_b} = scoped_ratios(scope.user.id, link, ratio_a, ratio_b)

        metrics =
          LinkMetricsCalculator.calculate_link_metrics(
            filtered_views,
            split_ratio_a,
            split_ratio_b
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
      income_a = SplitCalculator.calculate_reference_income(link.user_a_id, month, year)
      income_b = SplitCalculator.calculate_reference_income(link.user_b_id, month, year)
      ratios = SplitCalculator.calculate_split_ratio(income_a, income_b)

      Map.put(acc, {year, month}, ratios)
    end)
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
