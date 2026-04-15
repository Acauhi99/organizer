# Codebase Guidelines

## Objetivo
Garantir evolução consistente com foco em semântica, isolamento por usuário, comportamento observável e organização macro para micro.

## Princípio Macro para Micro
1. Comece no nível de domínio e fluxo.
2. Depois detalhe validação, transformação e renderização.
3. Evite esconder decisão de negócio em funções genéricas.

Aplicação prática:
- Macro: definir comportamento no Context (`Organizer.Planning`) e contratos de entrada/saída.
- Meso: estruturar handlers LiveView e controllers para orquestração clara.
- Micro: manter funções privadas pequenas e nomeadas por comportamento.

## Nomenclatura e Semântica
- Use verbos que indiquem efeito real: `create`, `update`, `delete`, `refresh`, `load`, `parse`, `validate`.
- Evite nomes vagos em funções e módulos: `helper`, `utils`, `common`, `misc`.
- Prefira nomes orientados a intenção de negócio:
  - `parse_positive_integer_or_default`
  - `refresh_dashboard_insights`
  - `load_operation_collections`
- Eventos LiveView devem expressar ação do usuário:
  - `set_analytics_days`
  - `filter_tasks`
  - `apply_bulk_template`

## Organização de Código
- Contexts concentram regras de domínio e isolamento por usuário via `Scope`.
- LiveViews orquestram estado e delegam regra de negócio para contexts.
- Controllers API só convertem request/response; não implementam regra de domínio.
- Não crie módulos "caixa de ferramentas". Se uma função merece existir, ela deve viver em um módulo semântico de domínio.

## Regras para Inserir Novo Código
1. Defina o comportamento esperado (entrada, saída, erro).
2. Escolha o módulo mais semântico já existente.
3. Adicione código no nível mais macro possível primeiro.
4. Extraia funções privadas apenas quando houver ganho de legibilidade real.
5. Nomeie cada função para explicar comportamento, não mecanismo.
6. Preserve o isolamento por usuário em toda consulta com `current_scope`.
7. Em LiveView, mantenha IDs únicos em elementos interativos para testes.

## Testes com foco em comportamento real
- Priorize assert de estado observável:
  - resposta HTTP e payload
  - persistência no banco
  - elementos com IDs estáveis
  - transições de estado
- Evite testes frágeis acoplados a copy textual.
- Para API:
  - cubra sucesso, validação (422), não encontrado (404) e não autenticado (401).
- Para LiveView:
  - use `has_element?/2` e eventos (`render_click`, `render_submit`, `render_change`).
  - valide o efeito de negócio após interação.

## Documentação e rastreabilidade
- Toda mudança funcional relevante deve atualizar:
  - `README.md` para visão de produto e arquitetura
  - `ROADMAP.md` para status real
  - `DESIGN_SYSTEM.md` para novas classes visuais
- Não usar emojis em documentação de engenharia.

## Checklist de Pull Request
- [ ] Nome dos módulos e funções descrevem comportamento.
- [ ] Não foi criado módulo/função com nome genérico (`helper`, `utils`).
- [ ] Testes cobrem comportamento de sucesso e falha.
- [ ] IDs de elementos foram adicionados quando necessário para testes.
- [ ] README/ROADMAP/DESIGN_SYSTEM atualizados quando aplicável.
- [ ] `mix precommit` executado com sucesso.
