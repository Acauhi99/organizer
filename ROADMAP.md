# Roadmap de Evolucao

## Refatoracao OTP (Concluida)

1. [x] **Fase 0 - Baseline**: 155 testes passando, business invariants documentados.
2. [x] **Fase 1 - LiveView Auth Lifecycle**: Migração de plugs para on_mount callbacks, simplificação de mount/3.
3. [x] **Fase 2 - Infraestrutura OTP**: 
   - Task.Supervisor para operações assíncronas
   - AnalyticsCache com GenServer + ETS para analytics com TTL 5min
   - Invalidação automática em mutações (9 pontos: create/update/delete task/finance/goal)
   - 10 testes de domínio passando, cache isolado por usuário
4. [x] **Fase 3 - Dashboard Refactoring**: 
   - Integração de cache API em refresh_dashboard_insights
   - Filter debouncing (500ms) em task/finance/goal forms para reduzir eventos
   - 16 testes (10 originais + 6 cache integration) passando
5. [x] **Fase 4 - Testes e Documentação**: 
   - 6 novos testes de cache (hit, miss, invalidação, isolamento, mutações)
   - README.md atualizado com arquitetura OTP
   - CODEBASE_GUIDELINES.md com critérios GenServer/cache
   - ROADMAP.md com status refator
6. [x] **Fase 5 - FieldSuggester**:
   - FieldSuggester GenServer + ETS para sugestão de valores por frequência de uso
   - Autocompletar prefixos de campos (`complete/3`) e correlações entre campos
   - `record_import/2` via cast não-bloqueante após importação em lote
   - Testes de propriedade (property-based) com `stream_data` para parsers e sugestores
   - Documentação de arquitetura atualizada (README, CODEBASE_GUIDELINES)

**Status**: Infraestrutura OTP completa com dois GenServers em produção.

## Etapa 1 - Estabilizacao tecnica

1. [x] Ajustar e ampliar a suite de testes para DashboardLive, API de tarefas e isolamento multiusuario.
2. [x] Validar fluxo completo de auth web (registro, login, recuperacao de senha, logout e confirmacao de troca de e-mail).
3. [x] Fortalecer seguranca operacional: limites de payload, hardening de headers e trilha de auditoria minima.

## Etapa 2 - Cobertura completa de dominio

1. [x] Expor APIs REST para financas, metas, custos fixos e datas importantes com semantica consistente.
2. [x] Adicionar operacoes de edicao e exclusao no dashboard para todos os blocos de quick add.
3. [x] Implementar filtros por periodo, status e prioridade nas visoes principais.

## Etapa 3 - Analitico e anti-burnout

1. [x] Criar painel semanal, mensal e anual com comparativos de progresso.
2. [x] Evoluir burndown com capacidade planejada versus executada e alertas de sobrecarga.
3. [x] Adicionar indicadores de risco de burnout baseados em atraso, carga aberta e tendencia de conclusao.

## Dashboard UX Refactor (Concluido)

1. [x] **Hierarquia visual de três níveis**: Bulk Import Hero (primário), Operations Panel (secundário), Analytics Panel (terciário) com CSS Grid e áreas nomeadas.
2. [x] **Onboarding interativo**: Sequência de 5 passos com spotlight, progresso persistido por usuário e opção de pular/retomar.
3. [x] **Controles de visibilidade de painéis**: Toggle individual de Analytics e Operations, três modos de layout (expanded, focused, minimal), preferências persistidas.
4. [x] **Estados vazios educativos**: Exemplos de importação por tipo de entidade com carregamento direto no editor.
5. [x] **Atalhos de teclado**: Alt+B, Alt+O, Alt+A, Alt+F, Esc, ? — documentados no menu de ajuda.
6. [x] **Carregamento assíncrono de gráficos**: AsyncChartLoader com skeleton loading, não bloqueia renderização principal.
7. [x] **Responsividade mobile-first**: Accordion para painéis secundários, Analytics oculto por padrão em mobile.
8. [x] **Acessibilidade**: Skip links, ARIA labels, indicadores de foco, navegação por teclado completa.
9. [x] **Schemas de persistência**: `user_preferences` e `onboarding_progress` com isolamento por usuário.

**Status**: Dashboard UX Refactor completo.

**Melhorias futuras (não implementadas nesta iteração)**:
- Screenshots e demo interativo no README
- Testes de regressão visual (Percy ou similar)
- Auditoria Lighthouse automatizada no CI
- Gestos touch nativos para troca de painéis em mobile

## Etapa 4 - UX e produto

1. [x] Refinar mobile-first do dashboard com foco em captura rapida e leitura instantanea.
2. [x] Melhorar acessibilidade (teclado, contraste, feedback de erros).

## Etapa 5 - Operacao e deploy

1. [x] Automatizar pipeline de CI para format, compile, testes e analise estatica.
2. [x] Publicar deploy inicial em Fly.io com volume persistente, backups periodicos e runbook.
