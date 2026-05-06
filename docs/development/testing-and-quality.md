# Testes, Qualidade e Validação Pré-commit

## Status atual

A suíte de testes em `test/**` foi removida temporariamente para acelerar o refactor visual completo da plataforma.

Este estado é **temporário** e deve ser revertido com a reintrodução incremental de testes após estabilização do novo design.

## Estratégia de validação vigente (sem testes)

Enquanto a suíte estiver removida, a qualidade local e no CI passa por:

1. formatação obrigatória (`mix format --check-formatted` no CI)
2. compilação estrita (`mix compile --warnings-as-errors`)
3. análise de dependência de compilação (`mix xref graph --format plain --label compile-connected --fail-above 0`)
4. revisão visual/manual dos fluxos críticos no browser

## Comandos de validação local

Validação rápida:

```bash
mix format
mix compile --warnings-as-errors
mix xref graph --format plain --label compile-connected --fail-above 0
```

Validação completa recomendada antes de commit:

```bash
mix precommit
```

`mix precommit` neste projeto executa:

1. compilação com warnings como erro
2. dialyzer em `MIX_ENV=dev`
3. limpeza de deps não usadas
4. formatação

## Política temporária de merge local

Não considerar uma mudança pronta sem:

1. `mix precommit` verde
2. revisão visual/manual dos fluxos alterados
3. atualização de docs em `docs/` quando comportamento/arquitetura mudar

## Próximo passo após refactor

Quando o refactor visual estiver estável, reintroduzir suíte de testes por fatias verticais:

1. autenticação pública
2. fluxo principal autenticado
3. regressões de colaboração financeira
