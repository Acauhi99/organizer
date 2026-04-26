defmodule Organizer.SharedFinance.SharedEntriesTest do
  use Organizer.DataCase, async: false

  import Organizer.AccountsFixtures

  alias Organizer.Accounts.Scope
  alias Organizer.SharedFinance
  alias Organizer.SharedFinance.SharedSplitSnapshot
  alias Organizer.Planning.FinanceEntry
  alias Organizer.Repo

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp make_scope(user), do: Scope.for_user(user)

  defp create_link(user_a, user_b) do
    scope_a = make_scope(user_a)
    scope_b = make_scope(user_b)
    {:ok, invite} = SharedFinance.create_invite(scope_a)
    {:ok, link} = SharedFinance.accept_invite(scope_b, invite.token)
    link
  end

  defp create_entry(user, attrs \\ %{}) do
    defaults = %{
      kind: :expense,
      expense_profile: :fixed,
      payment_method: :debit,
      amount_cents: 10_000,
      category: "Moradia",
      occurred_on: ~D[2024-01-15]
    }

    %FinanceEntry{}
    |> Ecto.Changeset.change(Map.merge(defaults, Map.put(attrs, :user_id, user.id)))
    |> Repo.insert!()
  end

  defp snapshots_for(entry_id, month, year) do
    import Ecto.Query

    from(ss in SharedSplitSnapshot,
      where:
        ss.finance_entry_id == ^entry_id and
          ss.reference_month == ^month and
          ss.reference_year == ^year,
      order_by: [asc: ss.calculated_at, asc: ss.id]
    )
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # share_finance_entry/3-4
  # ---------------------------------------------------------------------------

  describe "share_finance_entry/3" do
    test "shares an entry with a link the user participates in" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      entry = create_entry(user_a)
      scope_a = make_scope(user_a)

      assert {:ok, updated} = SharedFinance.share_finance_entry(scope_a, entry.id, link.id)
      assert updated.shared_with_link_id == link.id
    end

    test "returns {:error, :not_found} when entry does not belong to user" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      entry = create_entry(user_b)
      scope_a = make_scope(user_a)

      assert {:error, :not_found} = SharedFinance.share_finance_entry(scope_a, entry.id, link.id)
    end

    test "returns {:error, :not_found} when user is not a participant of the link" do
      user_a = user_fixture()
      user_b = user_fixture()
      user_c = user_fixture()
      link = create_link(user_a, user_b)
      entry = create_entry(user_c)
      scope_c = make_scope(user_c)

      assert {:error, :not_found} = SharedFinance.share_finance_entry(scope_c, entry.id, link.id)
    end

    test "broadcasts PubSub event after sharing" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      entry = create_entry(user_a)
      scope_a = make_scope(user_a)

      Phoenix.PubSub.subscribe(Organizer.PubSub, "account_link:#{link.id}")

      {:ok, updated} = SharedFinance.share_finance_entry(scope_a, entry.id, link.id)

      assert_receive {:shared_entry_updated, ^updated}
    end

    test "supports manual split mode when sharing" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      entry = create_entry(user_a, %{amount_cents: 50_000})
      scope_a = make_scope(user_a)

      assert {:ok, updated} =
               SharedFinance.share_finance_entry(scope_a, entry.id, link.id, %{
                 "shared_split_mode" => "manual",
                 "shared_manual_mine_amount" => "200"
               })

      assert updated.shared_with_link_id == link.id
      assert updated.shared_split_mode == :manual
      assert updated.shared_manual_mine_cents == 20_000
    end

    test "returns validation error when manual split exceeds total" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      entry = create_entry(user_a, %{amount_cents: 10_000})
      scope_a = make_scope(user_a)

      assert {:error, {:validation, %{shared_manual_mine_cents: _}}} =
               SharedFinance.share_finance_entry(scope_a, entry.id, link.id, %{
                 "shared_split_mode" => "manual",
                 "shared_manual_mine_amount" => "200"
               })
    end
  end

  # ---------------------------------------------------------------------------
  # unshare_finance_entry/2
  # ---------------------------------------------------------------------------

  describe "unshare_finance_entry/2" do
    test "removes shared_with_link_id from an entry" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      entry = create_entry(user_a, %{shared_with_link_id: link.id})
      scope_a = make_scope(user_a)

      assert {:ok, updated} = SharedFinance.unshare_finance_entry(scope_a, entry.id)
      assert is_nil(updated.shared_with_link_id)
    end

    test "returns {:error, :not_found} when entry does not belong to user" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      entry = create_entry(user_b, %{shared_with_link_id: link.id})
      scope_a = make_scope(user_a)

      assert {:error, :not_found} = SharedFinance.unshare_finance_entry(scope_a, entry.id)
    end

    test "broadcasts PubSub event after unsharing" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      entry = create_entry(user_a, %{shared_with_link_id: link.id})
      scope_a = make_scope(user_a)

      Phoenix.PubSub.subscribe(Organizer.PubSub, "account_link:#{link.id}")

      {:ok, updated} = SharedFinance.unshare_finance_entry(scope_a, entry.id)

      assert_receive {:shared_entry_removed, ^updated}
    end

    test "does not broadcast when entry was not shared" do
      user_a = user_fixture()
      user_b = user_fixture()
      _link = create_link(user_a, user_b)
      entry = create_entry(user_a)
      scope_a = make_scope(user_a)

      # Subscribe to a generic topic to ensure no message is sent
      Phoenix.PubSub.subscribe(Organizer.PubSub, "account_link:none")

      assert {:ok, updated} = SharedFinance.unshare_finance_entry(scope_a, entry.id)
      assert is_nil(updated.shared_with_link_id)
      refute_receive {:shared_entry_removed, _}
    end
  end

  # ---------------------------------------------------------------------------
  # list_shared_entries/3
  # ---------------------------------------------------------------------------

  describe "list_shared_entries/3" do
    test "returns shared entries with split view for participant" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      _entry = create_entry(user_a, %{shared_with_link_id: link.id})
      scope_a = make_scope(user_a)

      assert {:ok, views} = SharedFinance.list_shared_entries(scope_a, link.id)
      assert length(views) == 1
      [view] = views
      assert view.entry.shared_with_link_id == link.id
      assert view.split_ratio_mine + view.split_ratio_theirs == 1.0
      assert view.amount_mine_cents + view.amount_theirs_cents == view.entry.amount_cents
    end

    test "returns {:error, :not_found} for non-participant" do
      user_a = user_fixture()
      user_b = user_fixture()
      user_c = user_fixture()
      link = create_link(user_a, user_b)
      _entry = create_entry(user_a, %{shared_with_link_id: link.id})
      scope_c = make_scope(user_c)

      assert {:error, :not_found} = SharedFinance.list_shared_entries(scope_c, link.id)
    end

    test "returns empty list when no entries are shared" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)

      assert {:ok, []} = SharedFinance.list_shared_entries(scope_a, link.id)
    end

    test "both participants see the same shared entries" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      _entry = create_entry(user_a, %{shared_with_link_id: link.id})
      scope_a = make_scope(user_a)
      scope_b = make_scope(user_b)

      {:ok, views_a} = SharedFinance.list_shared_entries(scope_a, link.id)
      {:ok, views_b} = SharedFinance.list_shared_entries(scope_b, link.id)

      assert length(views_a) == 1
      assert length(views_b) == 1
      assert hd(views_a).entry.id == hd(views_b).entry.id
    end

    test "split ratios are swapped between the two participants" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      _entry = create_entry(user_a, %{shared_with_link_id: link.id})
      scope_a = make_scope(user_a)
      scope_b = make_scope(user_b)

      {:ok, [view_a]} = SharedFinance.list_shared_entries(scope_a, link.id)
      {:ok, [view_b]} = SharedFinance.list_shared_entries(scope_b, link.id)

      assert view_a.split_ratio_mine == view_b.split_ratio_theirs
      assert view_a.split_ratio_theirs == view_b.split_ratio_mine
    end

    test "when only one account has income in the month, shared expense is 100/0" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)

      _income_a =
        create_entry(user_a, %{
          kind: :income,
          amount_cents: 500_000,
          category: "Salario",
          occurred_on: ~D[2024-01-10]
        })

      expense =
        create_entry(user_a, %{
          kind: :expense,
          amount_cents: 12_345,
          occurred_on: ~D[2024-01-15],
          shared_with_link_id: link.id
        })

      scope_a = make_scope(user_a)
      scope_b = make_scope(user_b)

      {:ok, [view_a]} = SharedFinance.list_shared_entries(scope_a, link.id)
      {:ok, [view_b]} = SharedFinance.list_shared_entries(scope_b, link.id)

      assert view_a.entry.id == expense.id
      assert view_b.entry.id == expense.id

      assert view_a.split_ratio_mine == 1.0
      assert view_a.split_ratio_theirs == 0.0
      assert view_a.amount_mine_cents == expense.amount_cents
      assert view_a.amount_theirs_cents == 0

      assert view_b.split_ratio_mine == 0.0
      assert view_b.split_ratio_theirs == 1.0
      assert view_b.amount_mine_cents == 0
      assert view_b.amount_theirs_cents == expense.amount_cents
    end

    test "fixed income from prior month is projected into the reference month" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)
      reference_date = ~D[2026-04-20]

      _income_b_fixed =
        create_entry(user_b, %{
          kind: :income,
          expense_profile: :fixed,
          amount_cents: 400_000,
          category: "Salario fixo",
          occurred_on: ~D[2026-01-05]
        })

      expense =
        create_entry(user_a, %{
          kind: :expense,
          amount_cents: 10_000,
          occurred_on: ~D[2026-04-10],
          shared_with_link_id: link.id
        })

      {:ok, [view_a]} =
        SharedFinance.list_shared_entries(scope_a, link.id, %{reference_date: reference_date})

      assert view_a.entry.id == expense.id
      assert view_a.split_ratio_mine == 0.0
      assert view_a.split_ratio_theirs == 1.0
      assert view_a.amount_mine_cents == 0
      assert view_a.amount_theirs_cents == 10_000
    end

    test "when both accounts have zero income in month, split is 100% for entry owner" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)

      expense_by_b =
        create_entry(user_b, %{
          kind: :expense,
          amount_cents: 12_000,
          occurred_on: ~D[2024-03-15],
          shared_with_link_id: link.id
        })

      scope_a = make_scope(user_a)
      scope_b = make_scope(user_b)

      {:ok, [view_a]} = SharedFinance.list_shared_entries(scope_a, link.id)
      {:ok, [view_b]} = SharedFinance.list_shared_entries(scope_b, link.id)

      assert view_a.entry.id == expense_by_b.id
      assert view_b.entry.id == expense_by_b.id

      assert view_a.split_ratio_mine == 0.0
      assert view_a.split_ratio_theirs == 1.0
      assert view_a.amount_mine_cents == 0
      assert view_a.amount_theirs_cents == expense_by_b.amount_cents

      assert view_b.split_ratio_mine == 1.0
      assert view_b.split_ratio_theirs == 0.0
      assert view_b.amount_mine_cents == expense_by_b.amount_cents
      assert view_b.amount_theirs_cents == 0
    end

    test "split ratio uses the same reference month for all shared entries with carryover" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)

      _income_a_jan =
        create_entry(user_a, %{
          kind: :income,
          amount_cents: 500_000,
          category: "Salario",
          occurred_on: ~D[2024-01-03]
        })

      _income_b_feb =
        create_entry(user_b, %{
          kind: :income,
          amount_cents: 400_000,
          category: "Freelance",
          occurred_on: ~D[2024-02-05]
        })

      jan_expense =
        create_entry(user_a, %{
          amount_cents: 10_000,
          occurred_on: ~D[2024-01-15],
          shared_with_link_id: link.id
        })

      feb_expense =
        create_entry(user_a, %{
          amount_cents: 20_000,
          occurred_on: ~D[2024-02-15],
          shared_with_link_id: link.id
        })

      {:ok, views} =
        SharedFinance.list_shared_entries(scope_a, link.id, %{reference_date: ~D[2024-02-20]})

      views_by_entry = Map.new(views, fn view -> {view.entry.id, view} end)

      jan_view = Map.fetch!(views_by_entry, jan_expense.id)
      feb_view = Map.fetch!(views_by_entry, feb_expense.id)

      assert_in_delta jan_view.split_ratio_mine, 0.5555555555, 0.000001
      assert jan_view.amount_mine_cents == 5_556
      assert jan_view.amount_theirs_cents == 4_444

      assert_in_delta feb_view.split_ratio_mine, 0.5555555555, 0.000001
      assert feb_view.amount_mine_cents == 11_111
      assert feb_view.amount_theirs_cents == 8_889
    end

    test "rebalances income-ratio split when linked income is added or removed" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)

      _income_a =
        create_entry(user_a, %{
          kind: :income,
          amount_cents: 600_000,
          category: "Salario",
          occurred_on: ~D[2026-04-03]
        })

      expense =
        create_entry(user_a, %{
          kind: :expense,
          amount_cents: 10_000,
          occurred_on: ~D[2026-04-10],
          shared_with_link_id: link.id
        })

      {:ok, [view_only_a_income]} =
        SharedFinance.list_shared_entries(scope_a, link.id, %{reference_date: ~D[2026-04-20]})

      assert view_only_a_income.entry.id == expense.id
      assert view_only_a_income.split_ratio_mine == 1.0
      assert view_only_a_income.amount_mine_cents == 10_000
      assert view_only_a_income.amount_theirs_cents == 0

      income_b =
        create_entry(user_b, %{
          kind: :income,
          amount_cents: 400_000,
          category: "Salario",
          occurred_on: ~D[2026-04-05]
        })

      {:ok, [view_rebalanced]} =
        SharedFinance.list_shared_entries(scope_a, link.id, %{reference_date: ~D[2026-04-20]})

      assert view_rebalanced.entry.id == expense.id
      assert_in_delta view_rebalanced.split_ratio_mine, 0.6, 0.000001
      assert view_rebalanced.amount_mine_cents == 6_000
      assert view_rebalanced.amount_theirs_cents == 4_000

      Repo.delete!(income_b)

      {:ok, [view_after_removal]} =
        SharedFinance.list_shared_entries(scope_a, link.id, %{reference_date: ~D[2026-04-20]})

      assert view_after_removal.entry.id == expense.id
      assert view_after_removal.split_ratio_mine == 1.0
      assert view_after_removal.amount_mine_cents == 10_000
      assert view_after_removal.amount_theirs_cents == 0
    end

    test "persists temporal split snapshots when income changes rebalance a shared entry" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)
      reference_date = ~D[2026-04-20]

      _income_a =
        create_entry(user_a, %{
          kind: :income,
          expense_profile: :variable,
          amount_cents: 600_000,
          category: "Salario",
          occurred_on: ~D[2026-04-03]
        })

      expense =
        create_entry(user_a, %{
          kind: :expense,
          amount_cents: 10_000,
          occurred_on: ~D[2026-04-10],
          shared_with_link_id: link.id
        })

      assert {:ok, [_]} =
               SharedFinance.list_shared_entries(scope_a, link.id, %{
                 reference_date: reference_date
               })

      snapshots_initial = snapshots_for(expense.id, reference_date.month, reference_date.year)
      assert length(snapshots_initial) == 1
      [initial_snapshot] = snapshots_initial
      assert initial_snapshot.split_mode == :income_ratio
      assert initial_snapshot.amount_a_cents == 10_000
      assert initial_snapshot.amount_b_cents == 0
      assert initial_snapshot.income_a_cents == 600_000
      assert initial_snapshot.income_b_cents == 0

      _income_b =
        create_entry(user_b, %{
          kind: :income,
          expense_profile: :variable,
          amount_cents: 400_000,
          category: "Salario",
          occurred_on: ~D[2026-04-05]
        })

      assert {:ok, [_]} =
               SharedFinance.list_shared_entries(scope_a, link.id, %{
                 reference_date: reference_date
               })

      snapshots_rebalanced = snapshots_for(expense.id, reference_date.month, reference_date.year)
      assert length(snapshots_rebalanced) == 2

      [_first, second] = snapshots_rebalanced
      assert_in_delta second.ratio_a, 0.6, 0.000001
      assert second.amount_a_cents == 6_000
      assert second.amount_b_cents == 4_000
      assert second.income_a_cents == 600_000
      assert second.income_b_cents == 400_000
    end

    test "persists manual split snapshots as manual mode" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)
      reference_date = ~D[2026-04-20]

      entry = create_entry(user_a, %{amount_cents: 50_000})

      {:ok, _shared} =
        SharedFinance.share_finance_entry(scope_a, entry.id, link.id, %{
          "shared_split_mode" => "manual",
          "shared_manual_mine_amount" => "200"
        })

      assert {:ok, [_]} =
               SharedFinance.list_shared_entries(scope_a, link.id, %{
                 reference_date: reference_date
               })

      snapshots = snapshots_for(entry.id, reference_date.month, reference_date.year)
      assert length(snapshots) == 1
      [snapshot] = snapshots
      assert snapshot.split_mode == :manual
      assert snapshot.amount_a_cents == 20_000
      assert snapshot.amount_b_cents == 30_000
    end

    test "manual split overrides income ratio for shared entry amounts" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)
      scope_b = make_scope(user_b)

      _income_a =
        create_entry(user_a, %{
          kind: :income,
          amount_cents: 500_000,
          category: "Salario",
          occurred_on: ~D[2024-04-05]
        })

      _income_b =
        create_entry(user_b, %{
          kind: :income,
          amount_cents: 500_000,
          category: "Salario",
          occurred_on: ~D[2024-04-06]
        })

      entry = create_entry(user_a, %{amount_cents: 50_000})

      {:ok, _shared} =
        SharedFinance.share_finance_entry(scope_a, entry.id, link.id, %{
          "shared_split_mode" => "manual",
          "shared_manual_mine_amount" => "200"
        })

      {:ok, [view_a]} = SharedFinance.list_shared_entries(scope_a, link.id)
      {:ok, [view_b]} = SharedFinance.list_shared_entries(scope_b, link.id)

      assert view_a.amount_mine_cents == 20_000
      assert view_a.amount_theirs_cents == 30_000
      assert_in_delta view_a.split_ratio_mine, 0.4, 0.00001

      assert view_b.amount_mine_cents == 30_000
      assert view_b.amount_theirs_cents == 20_000
      assert_in_delta view_b.split_ratio_mine, 0.6, 0.00001
    end
  end

  describe "get_link_metrics/3" do
    test "returns accumulated totals up to reference month and keeps income-based split" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)

      _income_a_mar =
        create_entry(user_a, %{
          kind: :income,
          amount_cents: 60_000,
          category: "Salario",
          occurred_on: ~D[2026-03-05]
        })

      _income_b_mar =
        create_entry(user_b, %{
          kind: :income,
          amount_cents: 40_000,
          category: "Salario",
          occurred_on: ~D[2026-03-06]
        })

      _march_expense =
        create_entry(user_a, %{
          kind: :expense,
          amount_cents: 7_990,
          occurred_on: ~D[2026-03-10],
          shared_with_link_id: link.id
        })

      _april_expense =
        create_entry(user_a, %{
          kind: :expense,
          amount_cents: 210_000,
          occurred_on: ~D[2026-04-10],
          shared_with_link_id: link.id
        })

      assert {:ok, metrics} = SharedFinance.get_link_metrics(scope_a, link.id, ~D[2026-04-22])

      assert metrics.total_cents == 217_990
      assert metrics.paid_a_cents == 130_794
      assert metrics.paid_b_cents == 87_196
      assert_in_delta metrics.expected_pct_a, 60.0, 0.0001
      assert metrics.reference_month == 4
      assert metrics.reference_year == 2026
    end

    test "respects shared period filter current_month / last_3_months / all" do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)

      _income_a =
        create_entry(user_a, %{
          kind: :income,
          amount_cents: 60_000,
          category: "Salario",
          occurred_on: ~D[2026-02-05]
        })

      _income_b =
        create_entry(user_b, %{
          kind: :income,
          amount_cents: 40_000,
          category: "Salario",
          occurred_on: ~D[2026-02-06]
        })

      _entry_feb =
        create_entry(user_a, %{
          kind: :expense,
          amount_cents: 9_000,
          occurred_on: ~D[2026-02-10],
          shared_with_link_id: link.id
        })

      _entry_apr =
        create_entry(user_a, %{
          kind: :expense,
          amount_cents: 21_000,
          occurred_on: ~D[2026-04-10],
          shared_with_link_id: link.id
        })

      assert {:ok, metrics_current_month} =
               SharedFinance.get_link_metrics(scope_a, link.id, ~D[2026-04-22], %{
                 period: "current_month"
               })

      assert {:ok, metrics_last_3_months} =
               SharedFinance.get_link_metrics(scope_a, link.id, ~D[2026-04-22], %{
                 period: "last_3_months"
               })

      assert {:ok, metrics_all} =
               SharedFinance.get_link_metrics(scope_a, link.id, ~D[2026-04-22], %{period: "all"})

      assert metrics_current_month.total_cents == 21_000
      assert metrics_last_3_months.total_cents == 30_000
      assert metrics_all.total_cents == 30_000
    end
  end
end
