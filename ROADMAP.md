# Roadmap de Evolucao

## Etapa 1 - Estabilizacao tecnica

1. Ajustar e ampliar a suite de testes para DashboardLive, API de tarefas e isolamento multiusuario.
2. Validar fluxo completo de auth em LiveView (registro, login, confirmacao, recuperacao, logout).
3. Fortalecer seguranca operacional: limites de payload, hardening de headers e trilha de auditoria minima.

## Etapa 2 - Cobertura completa de dominio

1. Expor APIs REST para financas, metas, custos fixos e datas importantes com semantica consistente.
2. Adicionar operacoes de edicao e exclusao no dashboard para todos os blocos de quick add.
3. Implementar filtros por periodo, status e prioridade nas visoes principais.

## Etapa 3 - Analitico e anti-burnout

1. Criar painel semanal, mensal e anual com comparativos de progresso.
2. Evoluir burndown com capacidade planejada versus executada e alertas de sobrecarga.
3. Adicionar indicadores de risco de burnout baseados em atraso, carga aberta e tendencia de conclusao.

## Etapa 4 - UX e produto

1. Refinar mobile-first do dashboard com foco em captura rapida e leitura instantanea.
2. Melhorar acessibilidade (teclado, contraste, feedback de erros).
3. Incluir onboarding curto para primeira configuracao de metas e categorias financeiras.

## Etapa 5 - Operacao e deploy

1. Automatizar pipeline de CI para format, compile, testes e analise estatica.
2. Publicar deploy inicial em Fly.io com volume persistente, backups periodicos e runbook.
3. Definir criterio de migracao SQLite -> Postgres conforme crescimento de concorrencia.
