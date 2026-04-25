# E2E Suite (Playwright)

## Pré-requisitos

```bash
cd e2e
npm install
npm run install:browsers
```

## Execução

```bash
npm test
```

### Modos opcionais

```bash
npm run test:headed
npm run test:ui
```

## Cobertura retroativa atual

- `public-auth.spec.js`
  - home pública
  - cadastro
  - login/logout
  - credencial inválida
- `finances.spec.js`
  - criar lançamento
  - editar lançamento
  - excluir lançamento
- `tasks.spec.js`
  - criar tarefas
  - checklist
  - modal de detalhes
  - timer (`iniciar`, `pausar`, `resetar`)
- `collaboration.spec.js`
  - gerar convite
  - aceitar convite
  - compartilhar lançamento
  - visualizar compartilhado
  - acerto (`registrar`, `confirmar`, `quitar`)
- `collaboration-management.spec.js`
  - aceite de convite com usuário deslogado (`redirect -> login -> retomada`)
  - remoção de compartilhamento de lançamento (`unshare`)
  - desativação de vínculo em `/account-links`
  - vínculo de tarefa a compartilhamento (`modo sincronizado`)
- `experience.spec.js`
  - onboarding (navegação, pular, persistência pós-reload)
  - atalho global `Alt+B` (foco em lançamento financeiro)
- `api.spec.js`
  - smoke autenticado de todos os módulos de API:
    - `tasks`
    - `finance-entries`
    - `fixed-costs`
    - `important-dates`
- `settings.spec.js`
  - atualização de senha
  - login com nova senha
