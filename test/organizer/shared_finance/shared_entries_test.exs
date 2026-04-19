defmodule Organizer.SharedFinance.SharedEntriesTest do
  use Organizer.DataCase, async: false

  import Organizer.AccountsFixtures

  alias Organizer.Accounts.Scope
  alias Organizer.SharedFinance
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

  # ---------------------------------------------------------------------------
  # share_finance_entry/3
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
  end
end
