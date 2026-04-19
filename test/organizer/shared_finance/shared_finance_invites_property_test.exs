defmodule Organizer.SharedFinance.SharedFinanceInvitesPropertyTest do
  use Organizer.DataCase, async: false
  use ExUnitProperties

  import Organizer.AccountsFixtures

  alias Organizer.Accounts.Scope
  alias Organizer.SharedFinance

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp make_scope(user), do: Scope.for_user(user)

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 4: Tokens de convite são únicos
  # Validates: Requirements 2.1
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 4
  property "Property 4: N convites criados por usuários distintos têm tokens únicos" do
    check all(
            n <- StreamData.integer(2..10),
            min_runs: 50
          ) do
      users = Enum.map(1..n, fn _ -> user_fixture() end)

      tokens =
        Enum.map(users, fn user ->
          scope = make_scope(user)
          {:ok, invite} = SharedFinance.create_invite(scope)
          invite.token
        end)

      assert length(tokens) == length(Enum.uniq(tokens)),
             "tokens de convite não são únicos: #{inspect(tokens)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 5: Bidirecionalidade do AccountLink
  # Validates: Requirements 2.3, 2.8
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 5
  property "Property 5: após aceite, ambos os usuários veem o vínculo em list_account_links" do
    check all(
            _ <- StreamData.constant(:ok),
            min_runs: 20
          ) do
      user_a = user_fixture()
      user_b = user_fixture()
      scope_a = make_scope(user_a)
      scope_b = make_scope(user_b)

      {:ok, invite} = SharedFinance.create_invite(scope_a)
      {:ok, link} = SharedFinance.accept_invite(scope_b, invite.token)

      {:ok, links_a} = SharedFinance.list_account_links(scope_a)
      {:ok, links_b} = SharedFinance.list_account_links(scope_b)

      link_ids_a = Enum.map(links_a, & &1.id)
      link_ids_b = Enum.map(links_b, & &1.id)

      assert link.id in link_ids_a,
             "vínculo #{link.id} não encontrado em list_account_links do user_a"

      assert link.id in link_ids_b,
             "vínculo #{link.id} não encontrado em list_account_links do user_b"
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 6: Rejeição de convites inválidos
  # Validates: Requirements 2.4
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 6
  property "Property 6: convites com status != :pending ou expirados retornam {:error, :invite_invalid}" do
    check all(
            scenario <-
              StreamData.member_of([
                :expired_status_accepted,
                :expired_status_expired,
                :expired_time
              ]),
            min_runs: 50
          ) do
      inviter = user_fixture()
      acceptor = user_fixture()
      scope_inviter = make_scope(inviter)
      scope_acceptor = make_scope(acceptor)

      {:ok, invite} = SharedFinance.create_invite(scope_inviter)

      # Manipulate the invite to make it invalid
      invalid_invite =
        case scenario do
          :expired_status_accepted ->
            invite
            |> Ecto.Changeset.change(%{status: :accepted})
            |> Organizer.Repo.update!()

          :expired_status_expired ->
            invite
            |> Ecto.Changeset.change(%{status: :expired})
            |> Organizer.Repo.update!()

          :expired_time ->
            past = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)

            invite
            |> Ecto.Changeset.change(%{expires_at: past})
            |> Organizer.Repo.update!()
        end

      result = SharedFinance.accept_invite(scope_acceptor, invalid_invite.token)

      assert result == {:error, :invite_invalid},
             "esperado {:error, :invite_invalid} para cenário #{scenario}, mas obteve #{inspect(result)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 7: Unicidade de vínculo ativo
  # Validates: Requirements 2.6
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 7
  property "Property 7: tentar criar segundo vínculo entre mesmo par retorna {:error, :link_already_exists}" do
    check all(
            _ <- StreamData.constant(:ok),
            min_runs: 20
          ) do
      user_a = user_fixture()
      user_b = user_fixture()
      scope_a = make_scope(user_a)
      scope_b = make_scope(user_b)

      # Create first link
      {:ok, invite1} = SharedFinance.create_invite(scope_a)
      {:ok, _link} = SharedFinance.accept_invite(scope_b, invite1.token)

      # Try to create a second link between the same users
      {:ok, invite2} = SharedFinance.create_invite(scope_a)
      result = SharedFinance.accept_invite(scope_b, invite2.token)

      assert result == {:error, :link_already_exists},
             "esperado {:error, :link_already_exists}, mas obteve #{inspect(result)}"
    end
  end
end
