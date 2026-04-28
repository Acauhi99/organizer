# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

import Ecto.Query

alias Organizer.Accounts.{OnboardingProgress, User, UserPreferences}
alias Organizer.Planning.{FinanceEntry, FixedCost, ImportantDate}
alias Organizer.Repo
alias Organizer.SharedFinance.{AccountLink, Invite, SettlementCycle, SettlementRecord}

now = DateTime.utc_now() |> DateTime.truncate(:second)
today = Date.utc_today()

seed_password = "Organizer12345!"

seed_emails = [
  "ana.silva@organizer.dev",
  "bruno.costa@organizer.dev",
  "carla.rocha@organizer.dev"
]

Repo.delete_all(from u in User, where: u.email in ^seed_emails)

create_user! = fn email ->
  %User{}
  |> User.registration_changeset(%{email: email, password: seed_password})
  |> Repo.insert!()
end

create_user_preferences! = fn user, attrs ->
  %UserPreferences{user_id: user.id}
  |> UserPreferences.changeset(attrs)
  |> Repo.insert!()
end

create_onboarding_progress! = fn user, attrs ->
  %OnboardingProgress{user_id: user.id}
  |> OnboardingProgress.changeset(attrs)
  |> Repo.insert!()
end

create_finance_entry! = fn user, attrs ->
  %FinanceEntry{user_id: user.id}
  |> FinanceEntry.changeset(attrs)
  |> Repo.insert!()
end

create_fixed_cost! = fn user, attrs ->
  %FixedCost{user_id: user.id}
  |> FixedCost.changeset(attrs)
  |> Repo.insert!()
end

create_important_date! = fn user, attrs ->
  %ImportantDate{user_id: user.id}
  |> ImportantDate.changeset(attrs)
  |> Repo.insert!()
end

create_invite! = fn inviter, status, expires_in_hours ->
  %Invite{inviter_id: inviter.id}
  |> Invite.changeset(%{
    token: "seed-#{status}-#{Ecto.UUID.generate()}",
    status: status,
    expires_at: DateTime.add(now, expires_in_hours * 3600, :second)
  })
  |> Repo.insert!()
end

create_account_link! = fn user_a, user_b, invite ->
  %AccountLink{
    user_a_id: user_a.id,
    user_b_id: user_b.id,
    invite_id: if(is_nil(invite), do: nil, else: invite.id)
  }
  |> AccountLink.changeset(%{status: :active})
  |> Repo.insert!()
end

create_settlement_cycle! = fn link, attrs ->
  debtor_id = Map.get(attrs, :debtor_id)

  %SettlementCycle{account_link_id: link.id, debtor_id: debtor_id}
  |> SettlementCycle.changeset(Map.drop(attrs, [:debtor_id]))
  |> Repo.insert!()
end

create_settlement_record! = fn cycle, payer, receiver, attrs ->
  %SettlementRecord{
    settlement_cycle_id: cycle.id,
    payer_id: payer.id,
    receiver_id: receiver.id
  }
  |> SettlementRecord.changeset(attrs)
  |> Repo.insert!()
end

shift_month = fn %Date{year: year, month: month, day: day}, month_offset ->
  total_months = year * 12 + month - 1 + month_offset
  shifted_year = div(total_months, 12)
  shifted_month = rem(total_months, 12) + 1
  shifted_day = min(day, :calendar.last_day_of_the_month(shifted_year, shifted_month))
  Date.new!(shifted_year, shifted_month, shifted_day)
end

date_in_month = fn month_offset, day ->
  shifted = shift_month.(today, month_offset)
  safe_day = min(day, :calendar.last_day_of_the_month(shifted.year, shifted.month))
  Date.new!(shifted.year, shifted.month, safe_day)
end

ana = create_user!.("ana.silva@organizer.dev")
bruno = create_user!.("bruno.costa@organizer.dev")
carla = create_user!.("carla.rocha@organizer.dev")

create_user_preferences!.(ana, %{preferred_layout_mode: :expanded, onboarding_completed: false})
create_user_preferences!.(bruno, %{preferred_layout_mode: :focused, onboarding_completed: true})
create_user_preferences!.(carla, %{preferred_layout_mode: :minimal, onboarding_completed: false})

create_onboarding_progress!.(ana, %{current_step: 2, completed_steps: [1], dismissed: false})

create_onboarding_progress!.(bruno, %{
  current_step: 6,
  completed_steps: [1, 2, 3, 4, 5, 6],
  dismissed: false
})

create_onboarding_progress!.(carla, %{current_step: 1, completed_steps: [], dismissed: false})

invite_ana_bruno = create_invite!.(ana, :accepted, 48)
link_ana_bruno = create_account_link!.(ana, bruno, invite_ana_bruno)

_ana_finances =
  [
    %{
      kind: :income,
      amount_cents: 920_000,
      category: "Salário",
      description: "Salário mensal",
      occurred_on: date_in_month.(0, 5)
    },
    %{
      kind: :expense,
      amount_cents: 42_900,
      category: "Alimentação",
      description: "Mercado da semana",
      occurred_on: date_in_month.(0, 11),
      expense_profile: :variable,
      payment_method: :debit
    },
    %{
      kind: :expense,
      amount_cents: 18_600,
      category: "Transporte",
      description: "Combustível",
      occurred_on: date_in_month.(0, 13),
      expense_profile: :variable,
      payment_method: :credit,
      installment_number: 1,
      installments_count: 2,
      shared_with_link_id: link_ana_bruno.id,
      shared_split_mode: :income_ratio
    },
    %{
      kind: :expense,
      amount_cents: 32_000,
      category: "Moradia",
      description: "Condomínio",
      occurred_on: date_in_month.(0, 8),
      expense_profile: :fixed,
      payment_method: :debit,
      shared_with_link_id: link_ana_bruno.id,
      shared_split_mode: :manual,
      shared_manual_mine_cents: 16_000
    }
  ]
  |> Enum.map(&create_finance_entry!.(ana, &1))

_bruno_finances =
  [
    %{
      kind: :income,
      amount_cents: 610_000,
      category: "Salário",
      description: "Salário mensal",
      occurred_on: date_in_month.(0, 5)
    },
    %{
      kind: :expense,
      amount_cents: 24_500,
      category: "Lazer",
      description: "Assinaturas",
      occurred_on: date_in_month.(0, 15),
      expense_profile: :recurring_variable,
      payment_method: :credit,
      installment_number: 1,
      installments_count: 1
    }
  ]
  |> Enum.map(&create_finance_entry!.(bruno, &1))

_carla_finances =
  [
    %{
      kind: :income,
      amount_cents: 480_000,
      category: "Salário",
      description: "Renda principal",
      occurred_on: date_in_month.(0, 6)
    },
    %{
      kind: :expense,
      amount_cents: 29_900,
      category: "Saúde",
      description: "Plano de saúde",
      occurred_on: date_in_month.(0, 10),
      expense_profile: :fixed,
      payment_method: :debit
    }
  ]
  |> Enum.map(&create_finance_entry!.(carla, &1))

create_fixed_cost!.(ana, %{
  name: "Aluguel",
  amount_cents: 180_000,
  billing_day: 5,
  starts_on: date_in_month.(-6, 5),
  active: true
})

create_fixed_cost!.(bruno, %{
  name: "Internet",
  amount_cents: 11_900,
  billing_day: 12,
  starts_on: date_in_month.(-4, 12),
  active: true
})

create_important_date!.(ana, %{
  title: "Renovação seguro carro",
  category: :finance,
  date: date_in_month.(1, 20),
  notes: "Comparar propostas antes de renovar"
})

create_important_date!.(carla, %{
  title: "Pagamento IPVA",
  category: :finance,
  date: date_in_month.(1, 15),
  notes: "Verificar desconto por cota única"
})

cycle =
  create_settlement_cycle!.(link_ana_bruno, %{
    reference_month: today.month,
    reference_year: today.year,
    balance_cents: 8_000,
    debtor_id: ana.id,
    status: :open
  })

create_settlement_record!.(cycle, ana, bruno, %{
  amount_cents: 8_000,
  method: :pix,
  transferred_at: DateTime.utc_now() |> DateTime.truncate(:second)
})

finances_count =
  Repo.aggregate(
    from(f in FinanceEntry, where: f.user_id in [^ana.id, ^bruno.id, ^carla.id]),
    :count
  )

links_count = Repo.aggregate(from(l in AccountLink, where: l.status == :active), :count)

IO.puts("""

Seeds financeiras concluídas.

Usuários de acesso (senha para todos: #{seed_password})
- #{ana.email}
- #{bruno.email}
- #{carla.email}

Dados gerados:
- #{finances_count} lançamentos financeiros
- #{links_count} compartilhamento(s) ativo(s)

""")
