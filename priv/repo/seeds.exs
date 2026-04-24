# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Organizer.Repo.insert!(%Organizer.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

import Ecto.Query

alias Organizer.Repo
alias Organizer.Accounts.{OnboardingProgress, User, UserPreferences}
alias Organizer.Planning.{FinanceEntry, FixedCost, ImportantDate, Task, TaskChecklistItem}
alias Organizer.SharedFinance.{AccountLink, Invite, SettlementCycle, SettlementRecord}

now = DateTime.utc_now() |> DateTime.truncate(:second)
today = Date.utc_today()

seed_password = "Organizer12345!"

seed_emails = [
  "ana.silva@organizer.dev",
  "bruno.costa@organizer.dev",
  "carla.rocha@organizer.dev",
  "diego.lima@organizer.dev"
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

create_task! = fn user, attrs, shared_attrs ->
  task =
    %Task{user_id: user.id}
    |> Task.changeset(attrs)
    |> Repo.insert!()

  if map_size(shared_attrs) > 0 do
    task
    |> Ecto.Changeset.change(shared_attrs)
    |> Repo.update!()
  else
    task
  end
end

create_task_checklist_items! = fn task, items ->
  items
  |> Enum.with_index()
  |> Enum.each(fn {{label, checked?}, index} ->
    checked_at = if checked?, do: DateTime.add(now, -(index + 1) * 1800, :second), else: nil

    %TaskChecklistItem{task_id: task.id}
    |> TaskChecklistItem.changeset(%{
      label: label,
      position: index,
      checked: checked?,
      checked_at: checked_at
    })
    |> Repo.insert!()
  end)
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

datetime_from_date! = fn date, hour, minute, second ->
  DateTime.new!(date, Time.new!(hour, minute, second), "Etc/UTC")
end

ana = create_user!.("ana.silva@organizer.dev")
bruno = create_user!.("bruno.costa@organizer.dev")
carla = create_user!.("carla.rocha@organizer.dev")
diego = create_user!.("diego.lima@organizer.dev")

create_user_preferences!.(ana, %{
  analytics_panel_default_visible: true,
  operations_panel_default_visible: true,
  onboarding_completed: true,
  preferred_layout_mode: :expanded
})

create_user_preferences!.(bruno, %{
  analytics_panel_default_visible: true,
  operations_panel_default_visible: false,
  onboarding_completed: false,
  preferred_layout_mode: :focused
})

create_user_preferences!.(carla, %{
  analytics_panel_default_visible: false,
  operations_panel_default_visible: true,
  onboarding_completed: false,
  preferred_layout_mode: :minimal
})

create_user_preferences!.(diego, %{
  analytics_panel_default_visible: true,
  operations_panel_default_visible: true,
  onboarding_completed: false,
  preferred_layout_mode: :expanded
})

create_onboarding_progress!.(ana, %{
  current_step: 6,
  completed_steps: [1, 2, 3, 4, 5, 6],
  dismissed: false,
  completed_at: DateTime.add(now, -7 * 24 * 3600, :second)
})

create_onboarding_progress!.(bruno, %{
  current_step: 3,
  completed_steps: [1, 2],
  dismissed: false,
  completed_at: nil
})

create_onboarding_progress!.(carla, %{
  current_step: 2,
  completed_steps: [1],
  dismissed: true,
  completed_at: nil
})

create_onboarding_progress!.(diego, %{
  current_step: 1,
  completed_steps: [],
  dismissed: false,
  completed_at: nil
})

invite_accepted_ana_bruno = create_invite!.(ana, :accepted, 72)
invite_accepted_ana_carla = create_invite!.(ana, :accepted, 72)
_invite_pending_ana_diego = create_invite!.(ana, :pending, 72)
_invite_expired_bruno = create_invite!.(bruno, :expired, -24)

link_ana_bruno = create_account_link!.(ana, bruno, invite_accepted_ana_bruno)
link_ana_carla = create_account_link!.(ana, carla, invite_accepted_ana_carla)

pair_uuid_sync = Ecto.UUID.generate()
pair_uuid_copy = Ecto.UUID.generate()

ana_task_sync =
  create_task!.(
    ana,
    %{
      title: "Conciliar gastos compartilhados do mês",
      notes: "Revisar despesas conjuntas e fechar pendências até sexta.",
      status: :in_progress,
      priority: :high,
      due_on: Date.add(today, 2)
    },
    %{
      shared_with_link_id: link_ana_bruno.id,
      shared_pair_uuid: pair_uuid_sync,
      shared_sync_mode: :sync
    }
  )

create_task_checklist_items!.(ana_task_sync, [
  {"Validar lançamentos recorrentes", true},
  {"Conferir despesas de cartão", false},
  {"Enviar resumo para Bruno", false}
])

ana_task_copy =
  create_task!.(
    ana,
    %{
      title: "Pesquisar novo plano de internet",
      notes: "Comparar 3 provedores com upload > 300Mbps.",
      status: :todo,
      priority: :medium,
      due_on: Date.add(today, 5)
    },
    %{
      shared_with_link_id: link_ana_bruno.id,
      shared_pair_uuid: pair_uuid_copy,
      shared_sync_mode: :copy
    }
  )

create_task_checklist_items!.(ana_task_copy, [
  {"Levantar preço dos planos", true},
  {"Comparar fidelidade e multa", false}
])

_ana_tasks =
  [
    %{
      title: "Item de backlog",
      notes: "Ajustar descrição do item técnico e anexar referência.",
      status: :todo,
      priority: :low,
      due_on: Date.add(today, 6)
    },
    %{
      title: "Revisar PR de autenticação",
      notes: "https://dev.azure.com/org/projeto/_git/repo/pullrequest/1289",
      status: :todo,
      priority: :high,
      due_on: Date.add(today, 1)
    },
    %{
      title: "Organizar rotina da semana",
      notes: "Separar blocos de foco e janelas de reunião.",
      status: :in_progress,
      priority: :medium,
      due_on: Date.add(today, 3)
    },
    %{
      title: "Atualizar documentação de release",
      notes: "Incluir checklist de validação manual para produção.",
      status: :done,
      priority: :medium,
      due_on: Date.add(today, -1)
    },
    %{
      title: "Preparar retrospectiva do sprint",
      notes: "Consolidar pontos de melhoria e ações objetivas.",
      status: :done,
      priority: :high,
      due_on: Date.add(today, -3)
    },
    %{
      title: "Refatorar card de tarefas",
      notes: "Melhorar legibilidade em telas menores.",
      status: :in_progress,
      priority: :medium,
      due_on: Date.add(today, 4)
    },
    %{
      title: "Planejar compras da quinzena",
      notes: "Incluir itens compartilhados e itens pessoais separados.",
      status: :todo,
      priority: :low,
      due_on: Date.add(today, 7)
    },
    %{
      title: "Fechar pendências financeiras",
      notes: "Conferir recebimentos e confirmar pagamentos fixos.",
      status: :done,
      priority: :high,
      due_on: Date.add(today, -2)
    }
  ]
  |> Enum.map(fn attrs ->
    task = create_task!.(ana, attrs, %{})

    if attrs.status == :done do
      task
      |> Ecto.Changeset.change(%{
        completed_at: datetime_from_date!.(Date.add(today, -1), 17, 30, 0)
      })
      |> Repo.update!()
    else
      task
    end
  end)

_carla_tasks =
  [
    %{
      title: "Alinhar orçamento mensal",
      notes: "Definir teto por categoria para o próximo mês.",
      status: :todo,
      priority: :medium,
      due_on: Date.add(today, 8)
    },
    %{
      title: "Concluir checklist de viagem",
      notes: "Reservas, bagagem e documentos.",
      status: :in_progress,
      priority: :high,
      due_on: Date.add(today, 2)
    }
  ]
  |> Enum.map(&create_task!.(carla, &1, %{}))

bruno_task_sync =
  create_task!.(
    bruno,
    %{
      title: "Conciliar gastos compartilhados do mês",
      notes: "Sincronizada com Ana para fechamento semanal.",
      status: :in_progress,
      priority: :high,
      due_on: Date.add(today, 2)
    },
    %{
      shared_with_link_id: link_ana_bruno.id,
      shared_pair_uuid: pair_uuid_sync,
      shared_origin_task_id: ana_task_sync.id,
      shared_sync_mode: :sync
    }
  )

create_task_checklist_items!.(bruno_task_sync, [
  {"Validar lançamentos recorrentes", true},
  {"Anexar comprovantes pendentes", false}
])

_bruno_task_copy =
  create_task!.(
    bruno,
    %{
      title: "Pesquisar novo plano de internet",
      notes: "Versão copiada para avaliação própria.",
      status: :todo,
      priority: :medium,
      due_on: Date.add(today, 5)
    },
    %{
      shared_with_link_id: link_ana_bruno.id,
      shared_pair_uuid: pair_uuid_copy,
      shared_origin_task_id: ana_task_copy.id,
      shared_sync_mode: :copy
    }
  )

for {month_offset, index} <- Enum.with_index(-5..0) do
  create_finance_entry!.(ana, %{
    kind: :income,
    amount_cents: 950_000 + index * 12_500,
    category: "Salário",
    description: "Salário mensal",
    occurred_on: date_in_month.(month_offset, 5)
  })

  create_finance_entry!.(bruno, %{
    kind: :income,
    amount_cents: 720_000 + index * 9_500,
    category: "Salário",
    description: "Salário mensal",
    occurred_on: date_in_month.(month_offset, 6)
  })
end

[
  %{
    kind: :expense,
    expense_profile: :recurring_fixed,
    payment_method: :debit,
    amount_cents: 245_000,
    category: "Moradia",
    description: "Aluguel",
    occurred_on: Date.add(today, -20)
  },
  %{
    kind: :expense,
    expense_profile: :variable,
    payment_method: :debit,
    amount_cents: 48_900,
    category: "Mercado",
    description: "Compras da semana",
    occurred_on: Date.add(today, -6)
  },
  %{
    kind: :expense,
    expense_profile: :fixed,
    payment_method: :credit,
    installments_count: 6,
    amount_cents: 189_900,
    category: "Tecnologia",
    description: "Notebook parcelado",
    occurred_on: Date.add(today, -12)
  },
  %{
    kind: :expense,
    expense_profile: :recurring_variable,
    payment_method: :debit,
    amount_cents: 12_900,
    category: "Assinaturas",
    description: "Streaming + armazenamento",
    occurred_on: Date.add(today, -4)
  },
  %{
    kind: :income,
    amount_cents: 35_000,
    category: "Freelance",
    description: "Projeto pontual de design",
    occurred_on: Date.add(today, -9)
  }
]
|> Enum.each(&create_finance_entry!.(ana, &1))

[
  %{
    kind: :expense,
    expense_profile: :fixed,
    payment_method: :debit,
    amount_cents: 158_000,
    category: "Moradia",
    description: "Condomínio",
    occurred_on: Date.add(today, -18)
  },
  %{
    kind: :expense,
    expense_profile: :variable,
    payment_method: :credit,
    installments_count: 3,
    amount_cents: 42_500,
    category: "Saúde",
    description: "Consulta e exames",
    occurred_on: Date.add(today, -8)
  },
  %{
    kind: :expense,
    expense_profile: :recurring_variable,
    payment_method: :debit,
    amount_cents: 16_800,
    category: "Transporte",
    description: "Combustível e estacionamento",
    occurred_on: Date.add(today, -3)
  }
]
|> Enum.each(&create_finance_entry!.(bruno, &1))

for {month_offset, index} <- Enum.with_index(-5..0) do
  shared_amount_ana = 36_000 + index * 2_400

  create_finance_entry!.(ana, %{
    kind: :expense,
    expense_profile: :recurring_variable,
    payment_method: :debit,
    amount_cents: shared_amount_ana,
    category: "Casa compartilhada",
    description: "Supermercado compartilhado",
    occurred_on: date_in_month.(month_offset, 14),
    shared_with_link_id: link_ana_bruno.id,
    shared_split_mode: :income_ratio
  })

  shared_amount_bruno = 24_000 + index * 1_800

  create_finance_entry!.(bruno, %{
    kind: :expense,
    expense_profile: :variable,
    payment_method: :credit,
    installments_count: 2,
    amount_cents: shared_amount_bruno,
    category: "Serviços compartilhados",
    description: "Internet e utilidades",
    occurred_on: date_in_month.(month_offset, 18),
    shared_with_link_id: link_ana_bruno.id,
    shared_split_mode: :manual,
    shared_manual_mine_cents: div(shared_amount_bruno * 55, 100)
  })
end

create_finance_entry!.(ana, %{
  kind: :expense,
  expense_profile: :variable,
  payment_method: :debit,
  amount_cents: 19_500,
  category: "Lazer compartilhado",
  description: "Cinema e jantar",
  occurred_on: Date.add(today, -5),
  shared_with_link_id: link_ana_carla.id,
  shared_split_mode: :manual,
  shared_manual_mine_cents: 9_000
})

create_fixed_cost!.(ana, %{
  name: "Internet residencial",
  amount_cents: 14_990,
  billing_day: 10,
  starts_on: date_in_month.(-3, 10),
  active: true
})

create_fixed_cost!.(ana, %{
  name: "Plano de saúde",
  amount_cents: 62_000,
  billing_day: 12,
  starts_on: date_in_month.(-4, 12),
  active: true
})

create_fixed_cost!.(ana, %{
  name: "Academia",
  amount_cents: 9_990,
  billing_day: 20,
  starts_on: date_in_month.(-2, 20),
  active: true
})

create_important_date!.(ana, %{
  title: "Renovação do seguro do carro",
  category: :finance,
  date: Date.add(today, 9),
  notes: "Comparar cotações antes de renovar."
})

create_important_date!.(ana, %{
  title: "Aniversário da mãe",
  category: :personal,
  date: Date.add(today, 16),
  notes: "Comprar presente até dois dias antes."
})

create_important_date!.(ana, %{
  title: "Apresentação trimestral",
  category: :work,
  date: Date.add(today, 5),
  notes: "Levar indicadores de tarefas e finanças."
})

current_cycle =
  create_settlement_cycle!.(link_ana_bruno, %{
    reference_month: today.month,
    reference_year: today.year,
    status: :open,
    balance_cents: 18_500,
    debtor_id: bruno.id,
    confirmed_by_a: true,
    confirmed_by_b: false,
    settled_at: nil
  })

create_settlement_record!.(current_cycle, bruno, ana, %{
  amount_cents: 8_000,
  method: :pix,
  transferred_at: datetime_from_date!.(Date.add(today, -9), 19, 30, 0)
})

create_settlement_record!.(current_cycle, bruno, ana, %{
  amount_cents: 4_500,
  method: :transferencia_entre_contas,
  transferred_at: datetime_from_date!.(Date.add(today, -2), 21, 10, 0)
})

last_month_date = shift_month.(today, -1)

settled_cycle =
  create_settlement_cycle!.(link_ana_bruno, %{
    reference_month: last_month_date.month,
    reference_year: last_month_date.year,
    status: :settled,
    balance_cents: 0,
    debtor_id: nil,
    confirmed_by_a: true,
    confirmed_by_b: true,
    settled_at: DateTime.add(now, -18 * 24 * 3600, :second)
  })

create_settlement_record!.(settled_cycle, ana, bruno, %{
  amount_cents: 11_250,
  method: :pix,
  transferred_at: datetime_from_date!.(Date.add(last_month_date, 22), 20, 0, 0)
})

_carla_cycle =
  create_settlement_cycle!.(link_ana_carla, %{
    reference_month: today.month,
    reference_year: today.year,
    status: :open,
    balance_cents: 7_800,
    debtor_id: carla.id,
    confirmed_by_a: false,
    confirmed_by_b: false,
    settled_at: nil
  })

seed_user_ids = [ana.id, bruno.id, carla.id, diego.id]
seed_link_ids = [link_ana_bruno.id, link_ana_carla.id]

tasks_count = Repo.aggregate(from(t in Task, where: t.user_id in ^seed_user_ids), :count)

checklist_items_count =
  Repo.aggregate(
    from(i in TaskChecklistItem,
      join: t in Task,
      on: i.task_id == t.id,
      where: t.user_id in ^seed_user_ids
    ),
    :count
  )

finance_entries_count =
  Repo.aggregate(from(f in FinanceEntry, where: f.user_id in ^seed_user_ids), :count)

shared_finance_entries_count =
  Repo.aggregate(
    from(f in FinanceEntry,
      where: f.user_id in ^seed_user_ids and f.shared_with_link_id in ^seed_link_ids
    ),
    :count
  )

settlement_cycles_count =
  Repo.aggregate(from(c in SettlementCycle, where: c.account_link_id in ^seed_link_ids), :count)

settlement_records_count =
  Repo.aggregate(
    from(r in SettlementRecord,
      join: c in SettlementCycle,
      on: r.settlement_cycle_id == c.id,
      where: c.account_link_id in ^seed_link_ids
    ),
    :count
  )

IO.puts("""
✅ Seed de desenvolvimento concluído com sucesso.

Usuários de acesso (senha para todos: #{seed_password})
- #{ana.email}
- #{bruno.email}
- #{carla.email}
- #{diego.email}

Resumo do que foi criado:
- #{tasks_count} tarefas
- #{checklist_items_count} itens de checklist
- #{finance_entries_count} lançamentos financeiros (#{shared_finance_entries_count} compartilhados)
- #{length(seed_link_ids)} compartilhamentos ativos
- #{settlement_cycles_count} ciclos de acerto
- #{settlement_records_count} transferências registradas

Dica:
- Entre com #{ana.email} para ver dashboard completo com tarefas, finanças e compartilhamentos.
- Entre com #{bruno.email} para validar a visão da conta parceira.
""")
