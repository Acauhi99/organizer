# Roadmap de Evolucao

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

## Etapa 4 - UX e produto

1. [x] Refinar mobile-first do dashboard com foco em captura rapida e leitura instantanea.
2. [x] Melhorar acessibilidade (teclado, contraste, feedback de erros).
3. [ ] Definir e implementar onboarding opcional orientado por contexto (sem bloquear o fluxo principal).

## Etapa 5 - Operacao e deploy

1. [x] Automatizar pipeline de CI para format, compile, testes e analise estatica.
2. [ ] Publicar deploy inicial em Fly.io com volume persistente, backups periodicos e runbook.
