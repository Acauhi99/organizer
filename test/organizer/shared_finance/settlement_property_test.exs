defmodule Organizer.SharedFinance.SettlementPropertyTest do
  use Organizer.DataCase, async: false
  use ExUnitProperties

  import Organizer.AccountsFixtures
  import Ecto.Query

  alias Organizer.Accounts.Scope
  alias Organizer.Repo
  alias Organizer.SharedFinance
  alias Organizer.SharedFinance.{SettlementCycle, SettlementRecord}

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

  defp insert_cycle(link_id, month, year) do
    %SettlementCycle{}
    |> SettlementCycle.changeset(%{
      reference_month: month,
      reference_year: year,
      status: :open
    })
    |> Ecto.Changeset.put_change(:account_link_id, link_id)
    |> Repo.insert!()
  end

  defp insert_record(cycle_id, payer_id, receiver_id, transferred_at) do
    %SettlementRecord{}
    |> Ecto.Changeset.change(%{
      settlement_cycle_id: cycle_id,
      payer_id: payer_id,
      receiver_id: receiver_id,
      amount_cents: 1000,
      method: :pix,
      transferred_at: transferred_at
    })
    |> Repo.insert!()
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 14: Unicidade de SettlementCycle por vínculo e mês
  # Validates: Requirements 5.1
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 14
  property "Property 14: get_or_create_settlement_cycle é idempotente — retorna o mesmo ciclo" do
    check all(
            n <- StreamData.integer(2..5),
            month <- StreamData.integer(1..12),
            year <- StreamData.integer(2020..2030),
            min_runs: 30
          ) do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)
      reference_month = Date.new!(year, month, 1)

      ids =
        Enum.map(1..n, fn _ ->
          {:ok, cycle} =
            SharedFinance.get_or_create_settlement_cycle(scope_a, link.id, reference_month)

          cycle.id
        end)

      assert length(Enum.uniq(ids)) == 1,
             "esperado um único ciclo, mas obteve ids distintos: #{inspect(ids)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 15: Validação de valor positivo em SettlementRecord
  # Validates: Requirements 5.4
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 15
  property "Property 15: create_settlement_record com amount_cents <= 0 retorna {:error, {:validation, _}}" do
    check all(
            amount_cents <- StreamData.filter(StreamData.integer(), &(&1 <= 0)),
            min_runs: 100
          ) do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)
      reference_month = Date.utc_today()

      {:ok, cycle} =
        SharedFinance.get_or_create_settlement_cycle(scope_a, link.id, reference_month)

      attrs = %{
        amount_cents: amount_cents,
        method: :pix,
        transferred_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      result = SharedFinance.create_settlement_record(scope_a, cycle.id, attrs)

      assert match?({:error, {:validation, _}}, result),
             "esperado {:error, {:validation, _}} para amount_cents=#{amount_cents}, mas obteve #{inspect(result)}"

      count =
        Repo.one(
          from sr in SettlementRecord,
            where: sr.settlement_cycle_id == ^cycle.id,
            select: count(sr.id)
        )

      assert count == 0, "nenhum registro deve ter sido persistido"
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 16: Ordenação cronológica de SettlementRecords
  # Validates: Requirements 5.10
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 16
  property "Property 16: list_settlement_records retorna registros em ordem crescente de transferred_at" do
    check all(
            n <- StreamData.integer(2..6),
            min_runs: 30
          ) do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)
      reference_month = Date.utc_today()

      {:ok, cycle} =
        SharedFinance.get_or_create_settlement_cycle(scope_a, link.id, reference_month)

      base = ~U[2024-01-01 00:00:00Z]
      offsets = Enum.shuffle(0..(n - 1))

      Enum.each(offsets, fn offset ->
        transferred_at = DateTime.add(base, offset * 3600, :second)
        insert_record(cycle.id, user_a.id, user_b.id, transferred_at)
      end)

      {:ok, records} = SharedFinance.list_settlement_records(scope_a, cycle.id)
      timestamps = Enum.map(records, & &1.transferred_at)

      assert timestamps == Enum.sort(timestamps, DateTime),
             "registros não estão em ordem crescente de transferred_at: #{inspect(timestamps)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 17: Ordenação cronológica decrescente de SettlementCycles
  # Validates: Requirements 5.11
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 17
  property "Property 17: list_settlement_cycles retorna ciclos em ordem decrescente de (year, month)" do
    check all(
            pairs <-
              StreamData.list_of(
                StreamData.tuple({StreamData.integer(2020..2030), StreamData.integer(1..12)}),
                min_length: 2,
                max_length: 6
              )
              |> StreamData.map(&Enum.uniq/1)
              |> StreamData.filter(&(length(&1) >= 2)),
            min_runs: 30
          ) do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)

      Enum.each(pairs, fn {year, month} ->
        insert_cycle(link.id, month, year)
      end)

      {:ok, cycles} = SharedFinance.list_settlement_cycles(scope_a, link.id)
      year_months = Enum.map(cycles, fn c -> {c.reference_year, c.reference_month} end)

      assert year_months == Enum.sort(year_months, :desc),
             "ciclos não estão em ordem decrescente: #{inspect(year_months)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 18: Bloqueio de quitação sem confirmação bilateral
  # Validates: Requirements 5.8
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 18
  property "Property 18: confirm_settlement com apenas um usuário retorna :awaiting_counterpart_confirmation; com ambos, quita o ciclo" do
    check all(
            first_confirmer <- StreamData.member_of([:user_a, :user_b]),
            min_runs: 30
          ) do
      user_a = user_fixture()
      user_b = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)
      scope_b = make_scope(user_b)
      reference_month = Date.utc_today()

      {:ok, cycle} =
        SharedFinance.get_or_create_settlement_cycle(scope_a, link.id, reference_month)

      {first_scope, second_scope} =
        if first_confirmer == :user_a,
          do: {scope_a, scope_b},
          else: {scope_b, scope_a}

      result_first = SharedFinance.confirm_settlement(first_scope, cycle.id)

      assert result_first == {:error, :awaiting_counterpart_confirmation},
             "esperado :awaiting_counterpart_confirmation após primeira confirmação, mas obteve #{inspect(result_first)}"

      result_second = SharedFinance.confirm_settlement(second_scope, cycle.id)

      assert match?({:ok, %SettlementCycle{status: :settled}}, result_second),
             "esperado ciclo quitado após segunda confirmação, mas obteve #{inspect(result_second)}"

      {:ok, settled_cycle} = result_second
      assert not is_nil(settled_cycle.settled_at), "settled_at deve estar preenchido"
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: shared-finance, Property 19: Isolamento de dados por participantes do vínculo
  # Validates: Requirements 6.1, 6.2, 6.3
  # ---------------------------------------------------------------------------

  @tag feature: "shared-finance", property: 19
  property "Property 19: usuário não participante recebe {:error, :not_found} em operações de leitura" do
    check all(
            _ <- StreamData.constant(:ok),
            min_runs: 20
          ) do
      user_a = user_fixture()
      user_b = user_fixture()
      user_c = user_fixture()
      link = create_link(user_a, user_b)
      scope_a = make_scope(user_a)
      scope_c = make_scope(user_c)
      reference_month = Date.utc_today()

      {:ok, _cycle} =
        SharedFinance.get_or_create_settlement_cycle(scope_a, link.id, reference_month)

      assert {:error, :not_found} = SharedFinance.get_account_link(scope_c, link.id)
      assert {:error, :not_found} = SharedFinance.list_shared_entries(scope_c, link.id)

      assert {:error, :not_found} =
               SharedFinance.get_or_create_settlement_cycle(scope_c, link.id, reference_month)

      assert {:error, :not_found} = SharedFinance.list_settlement_cycles(scope_c, link.id)
    end
  end
end
