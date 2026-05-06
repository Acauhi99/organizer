# Features

## Área pública (não logada)

- Landing `/` com identidade Neon Grid e CTAs claros para cadastro/login.
- Cadastro em `/users/register`.
- Login em `/users/log-in`.
- Aceite de convite por token em `/account-links/accept/:token`:
  - autenticado: processa na hora
  - não autenticado: redireciona para login e retoma fluxo

## Área autenticada (LiveView)

### Finanças (`/finances`)

- Lançamento rápido de receita/despesa com presets
- Compartilhamento opcional de despesa com vínculo ativo:
  - por proporção de renda
  - manual (minha parte / outra parte)
- Métricas financeiras:
  - receitas x despesas no tempo
  - composição por natureza
  - top categorias de despesa
- Operação diária:
  - filtros avançados
  - edição/exclusão inline

### Colaboração financeira

- Gestão de vínculos em `/account-links`
- Convites em `/account-links/invite`
- Finanças compartilhadas em `/account-links/:link_id`:
  - visão consolidada compartilhada
  - filtros de período
  - remoção de compartilhamento
  - acerto unificado no mesmo fluxo

### Experiência transversal

- Onboarding guiado
- Atalhos globais (`Alt+B`, `?`)
- Feedback visual Neon Grid consistente entre telas

## API REST (`/api/v1`)

Recursos disponíveis:

- `finance-entries`
- `fixed-costs`
- `important-dates`

Notas:

- rotas exigem autenticação + escopo válido
- front atual prioriza finanças e colaboração

## Autenticação e segurança

- Registro/login/logout por sessão
- Isolamento de dados por `current_scope`
- Rotas autenticadas via pipelines + `live_session`
