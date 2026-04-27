# Features

## Área pública (não logada)

- Landing page em `/` com posicionamento do produto e acesso para cadastro/login.
- Cadastro em `/users/register`.
- Login em `/users/log-in`.
- Aceite de convite por token em `/account-links/accept/:token`:
  - Usuário autenticado: convite é processado na hora.
  - Usuário não autenticado: redireciona para login e retoma o fluxo.

## Área autenticada (LiveView)

### Finanças (`/finances`)

- Lançamento rápido de receita/despesa com presets.
- Compartilhamento opcional de despesa com vínculo ativo:
  - modo por proporção de renda
  - modo manual (minha parte / outra parte)
- Métricas financeiras com filtros de período e gráficos:
  - receitas x despesas no tempo
  - composição por natureza
  - top categorias de despesa
- Operação diária financeira:
  - filtros avançados (janela móvel, data, mês, intervalo, dia da semana, ordenação e faixa de valor)
  - edição e exclusão inline de lançamentos

### Experiência transversal

- Onboarding guiado em 6 passos para primeira experiência.
- Atalho global `Alt+B` para focar o lançamento rápido financeiro.
- Atalho `?` para exibir lembrete de atalhos.

## Colaboração financeira

- Gestão de vínculos em `/account-links`:
  - criar convite
  - aceitar convite por token
  - desativar vínculo
- Convites em `/account-links/invite` com geração de link e cópia para clipboard.
- Finanças compartilhadas em `/account-links/:link_id`:
  - visão de total compartilhado, proporções e tendência
  - filtro por período (`mês atual`, `últimos 3 meses`, `tudo`)
  - listagem de lançamentos compartilhados e remoção de compartilhamento
- Acerto em `/account-links/:link_id/settlement`:
  - registro de transferências
  - confirmação bilateral
  - quitação do ciclo quando ambas as partes confirmam

## API REST (`/api/v1`)

Recursos disponíveis:

- `finance-entries`
- `fixed-costs`
- `important-dates`

Notas:

- Todas as rotas exigem autenticação e escopo válido.
- O front atual usa principalmente finanças e colaboração; `fixed-costs` e `important-dates` estão disponíveis no domínio/API.

## Autenticação e segurança

- Registro, login e logout com sessão autenticada.
- Isolamento de dados por `current_scope`.
- Proteção de rotas autenticadas via pipeline e `live_session`.
