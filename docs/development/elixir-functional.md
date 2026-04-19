# Boas Práticas Elixir Funcional

## Fundamentos para este projeto

- Dados imutáveis + transformação explícita.
- Pattern matching para validar forma de entrada cedo.
- Múltiplas cláusulas com guards para variação de comportamento.
- Preferência por funções puras em parsing, normalização e cálculo.

Referências oficiais:

- Introduction: https://hexdocs.pm/elixir/introduction.html
- Pattern matching: https://hexdocs.pm/elixir/pattern-matching.html
- Modules and functions: https://hexdocs.pm/elixir/modules-and-functions.html

## Regras práticas

1. Use pattern matching no cabeçalho para separar casos válidos/inválidos.
2. Normalize erros em formatos previsíveis (`{:ok, value} | {:error, reason}`).
3. Evite `try/rescue` para fluxo de negócio esperado.
4. Evite `String.to_atom/1` com input externo.
5. Em listas, use `Enum.at/2` (não indexação estilo array).
6. Para concorrência em lote, prefira `Task.async_stream/3` com back-pressure.

## Organização de módulos

- Contexts concentram operações de domínio.
- Módulos de apoio devem ter fronteira semântica clara (`BulkParser`, `FieldSuggester`, etc).
- Evite módulos “util” genéricos sem domínio explícito.

## OTP no projeto

Use GenServer quando existir estado compartilhado e ciclo de vida contínuo:

- Cache por usuário (`AnalyticsCache`)
- Sugestões por frequência/correlação (`FieldSuggester`)

Referência oficial:

- https://hexdocs.pm/elixir/GenServer.html

## Anti-patterns que devemos evitar

- `with` com `else` muito complexo.
- Comentários redundantes em código autoexplicativo.
- Excesso de tipos primitivos quando um struct/map semântico é melhor.

Referências oficiais:

- https://hexdocs.pm/elixir/main/code-anti-patterns.html
- https://hexdocs.pm/elixir/main/design-anti-patterns.html
