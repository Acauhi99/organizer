defmodule OrganizerWeb.DashboardLive.Components.BulkImportStudio do
  @moduledoc """
  Component for the bulk import studio section of the dashboard.
  """

  use Phoenix.Component
  import OrganizerWeb.CoreComponents
  import OrganizerWeb.DashboardLive.Formatters, only: [format_money: 1]
  alias OrganizerWeb.DashboardLive.BulkImport

  attr :bulk_form, :any, required: true
  attr :bulk_payload_text, :string, required: true
  attr :bulk_result, :map, default: nil
  attr :bulk_preview, :map, default: nil
  attr :bulk_strict_mode, :boolean, required: true
  attr :last_bulk_import, :map, default: nil
  attr :bulk_recent_payloads, :list, required: true
  attr :bulk_template_favorites, :list, required: true
  attr :bulk_import_block_size, :integer, required: true
  attr :bulk_import_block_index, :integer, required: true
  attr :bulk_top_categories, :list, required: true
  attr :bulk_share_finances, :boolean, default: false
  attr :bulk_share_link_id, :integer, default: nil
  attr :account_links, :list, default: []
  attr :current_user_id, :integer, default: 0

  def bulk_import_studio(assigns) do
    ~H"""
    <section
      id="quick-bulk"
      class="surface-card bulk-studio-shell order-5 rounded-2xl p-4 scroll-mt-20"
    >
      <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
        Importação rápida por texto
      </h2>
      <p class="mt-1 text-sm text-base-content/85">
        Cole uma linha por item usando o padrão tipo: conteúdo.
      </p>

      <div class="flex flex-wrap gap-[0.45rem] mt-3" aria-label="Etapas do fluxo de importação">
        <span class="inline-flex items-center gap-1.5 border border-base-content/22 rounded-full px-[0.62rem] py-[0.24rem] text-[0.72rem] text-base-content/96 bg-base-100/72">
          <strong>1.</strong> Colar texto
        </span>
        <span class="inline-flex items-center gap-1.5 border border-base-content/22 rounded-full px-[0.62rem] py-[0.24rem] text-[0.72rem] text-base-content/96 bg-base-100/72">
          <strong>2.</strong> Pré-visualizar
        </span>
        <span class="inline-flex items-center gap-1.5 border border-base-content/22 rounded-full px-[0.62rem] py-[0.24rem] text-[0.72rem] text-base-content/96 bg-base-100/72">
          <strong>3.</strong> Importar bloco ou tudo
        </span>
      </div>

      <div class="mt-3">
        <p class="text-[0.72rem] uppercase tracking-[0.08em] font-bold text-base-content/86">
          Templates rápidos
        </p>
        <div class="mt-2 grid gap-2 sm:grid-cols-2">
          <article
            :for={template <- sorted_bulk_templates(@bulk_template_favorites)}
            id={"bulk-template-card-#{template.key}"}
            class="justify-self-start inline-flex items-stretch border border-base-content/22 rounded-full overflow-hidden bg-base-100/76"
          >
            <button
              id={"bulk-template-#{template.key}"}
              type="button"
              phx-click="apply_bulk_template"
              phx-value-template={template.key}
              class="btn btn-xs rounded-none px-3"
            >
              {template.label}
            </button>
            <button
              id={"bulk-template-fav-#{template.key}"}
              type="button"
              phx-click="toggle_bulk_template_favorite"
              phx-value-template={template.key}
              aria-label={
                if template_favorited?(@bulk_template_favorites, template.key),
                  do: "Remover template dos favoritos",
                  else: "Adicionar template aos favoritos"
              }
              title={
                if template_favorited?(@bulk_template_favorites, template.key),
                  do: "Remover dos favoritos",
                  else: "Adicionar aos favoritos"
              }
              class={[
                "btn btn-xs rounded-none border-l border-base-content/20 min-w-[2.1rem] justify-center px-[0.48rem]",
                template_favorited?(@bulk_template_favorites, template.key) &&
                  "bg-info/14 text-base-content/98"
              ]}
            >
              <.icon
                name={
                  if template_favorited?(@bulk_template_favorites, template.key),
                    do: "hero-star-solid",
                    else: "hero-star"
                }
                class="size-3.5"
              />
            </button>
          </article>
        </div>
      </div>

      <details
        id="bulk-format-reference"
        class="border border-base-content/20 rounded-[0.8rem] bg-base-100/76 px-[0.72rem] py-[0.55rem] mt-3"
      >
        <summary class="cursor-pointer text-base text-base-content/92">
          Ver formatos e opções completas por tipo
        </summary>

        <div class="bulk-code-list mt-3 space-y-3">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <p class="text-sm text-base-content/78">
              Precisa enviar as regras para um chat de IA? Copie o template em Markdown.
            </p>
            <button
              id="bulk-copy-markdown-btn"
              type="button"
              phx-click="copy_bulk_markdown_reference"
              class="btn btn-soft btn-sm"
            >
              <.icon name="hero-document-duplicate" class="size-4" /> Copiar template Markdown
            </button>
          </div>

          <article class="micro-surface rounded-lg p-3">
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/62">
              Regras gerais
            </p>
            <ul class="mt-2 space-y-1 text-sm text-base-content/82">
              <li>
                Uma linha = um item, no padrão <code class="font-mono text-[0.84rem]">tipo: conteúdo</code>.
              </li>
              <li>
                Campos opcionais usam <code class="font-mono text-[0.84rem]">| campo=valor</code>.
              </li>
              <li>
                Linhas vazias e linhas iniciadas com <code class="font-mono text-[0.84rem]">#</code>
                são ignoradas.
              </li>
              <li>
                Datas aceitas: <code class="font-mono text-[0.84rem]">2026-04-20</code>, <code class="font-mono text-[0.84rem]">20/04/2026</code>, <code class="font-mono text-[0.84rem]">hoje</code>, <code class="font-mono text-[0.84rem]">amanhã</code>, <code class="font-mono text-[0.84rem]">ontem</code>.
              </li>
            </ul>
          </article>

          <article class="micro-surface rounded-lg p-3">
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/62">
              Prefixos de tipo aceitos
            </p>
            <div class="mt-2 flex flex-wrap gap-1.5 text-sm">
              <span class="rounded-full border border-base-content/20 px-2 py-0.5 font-mono">
                tarefa | task | t
              </span>
              <span class="rounded-full border border-base-content/20 px-2 py-0.5 font-mono">
                financeiro | finance | lancamento | lanc | fin | f
              </span>
              <span class="rounded-full border border-base-content/20 px-2 py-0.5 font-mono">
                receita | despesa
              </span>
            </div>
          </article>

          <div class="grid gap-3 xl:grid-cols-2">
            <article class="micro-surface rounded-lg p-3">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/62">
                Tarefa
              </p>
              <ul class="mt-2 space-y-1 text-sm text-base-content/82">
                <li>Título é obrigatório no conteúdo.</li>
                <li>
                  Campos: <code class="font-mono text-[0.84rem]">data/date/due/vencimento</code>, <code class="font-mono text-[0.84rem]">prioridade/priority/prio</code>, <code class="font-mono text-[0.84rem]">status</code>, <code class="font-mono text-[0.84rem]">nota/notas/notes</code>.
                </li>
                <li>
                  Prioridade: <code class="font-mono text-[0.84rem]">baixa|low|b</code>, <code class="font-mono text-[0.84rem]">media|médio|medium|normal|m</code>, <code class="font-mono text-[0.84rem]">alta|high|urgente|h</code>.
                </li>
                <li>
                  Status: <code class="font-mono text-[0.84rem]">todo|pendente</code>, <code class="font-mono text-[0.84rem]">in_progress|andamento|em_andamento</code>, <code class="font-mono text-[0.84rem]">done|concluida</code>.
                </li>
                <li>
                  Defaults: <code class="font-mono text-[0.84rem]">status=todo</code>
                  e <code class="font-mono text-[0.84rem]">prioridade=medium</code>.
                </li>
              </ul>
              <div class="mt-2 rounded-md border border-base-content/14 bg-base-100/65 p-2 font-mono text-[0.82rem] leading-[1.5] text-base-content/90">
                tarefa: Revisar orçamento amanhã alta<br />tarefa: Planejar viagem | data=2026-04-20 | prioridade=baixa | status=todo
              </div>
            </article>

            <article class="micro-surface rounded-lg p-3">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/62">
                Financeiro
              </p>
              <ul class="mt-2 space-y-1 text-sm text-base-content/82">
                <li>
                  Campos: <code class="font-mono text-[0.84rem]">tipo/kind</code>, <code class="font-mono text-[0.84rem]">natureza/perfil/recorrencia/expense_profile</code>, <code class="font-mono text-[0.84rem]">pagamento/meio/metodo/payment_method</code>, <code class="font-mono text-[0.84rem]">valor/amount/centavos</code>, <code class="font-mono text-[0.84rem]">categoria/category</code>, <code class="font-mono text-[0.84rem]">data/date/quando</code>, <code class="font-mono text-[0.84rem]">descricao/description</code>.
                </li>
                <li>
                  Tipo: <code class="font-mono text-[0.84rem]">despesa|expense</code>
                  ou <code class="font-mono text-[0.84rem]">receita|income</code>.
                </li>
                <li>
                  Natureza: <code class="font-mono text-[0.84rem]">fixa|fixo|recorrente|mensal</code>
                  ou <code class="font-mono text-[0.84rem]">variavel|variável|avulsa|pontual</code>.
                </li>
                <li>
                  Pagamento: <code class="font-mono text-[0.84rem]">credito|cartao</code>
                  ou <code class="font-mono text-[0.84rem]">debito|pix|dinheiro</code>.
                </li>
                <li>
                  Valor aceita exemplos como <code class="font-mono text-[0.84rem]">35</code>, <code class="font-mono text-[0.84rem]">125,90</code>, <code class="font-mono text-[0.84rem]">R$ 89,50</code>, <code class="font-mono text-[0.84rem]">1k</code>.
                </li>
                <li>
                  Defaults: se faltar data usa hoje; em despesa sem natureza/pagamento assume <code class="font-mono text-[0.84rem]">variável + débito</code>.
                </li>
              </ul>
              <div class="mt-2 rounded-md border border-base-content/14 bg-base-100/65 p-2 font-mono text-[0.82rem] leading-[1.5] text-base-content/90">
                financeiro: almoço 35<br />financeiro: tipo=despesa | natureza=fixa | pagamento=credito | valor=125,90 | categoria=moradia | data=2026-04-05
              </div>
            </article>
          </div>
        </div>
      </details>

      <div :if={@bulk_recent_payloads != []} id="bulk-history" class="mt-3 space-y-2">
        <p class="text-[0.72rem] uppercase tracking-[0.08em] font-bold text-base-content/86">
          Histórico recente
        </p>
        <div class="grid gap-2 sm:grid-cols-2">
          <article
            :for={entry <- @bulk_recent_payloads}
            id={"bulk-history-entry-#{entry.id}"}
            class={[
              "border border-base-content/20 bg-base-100/74",
              entry.favorite && "border-info/40",
              !entry.favorite && "border-base-content/12"
            ]}
          >
            <p class="font-mono text-[0.73rem] leading-[1.45] text-base-content/88">
              {entry.preview_line}
            </p>
            <div class="mt-2 flex items-center gap-2">
              <button
                id={"bulk-history-load-#{entry.id}"}
                type="button"
                phx-click="load_bulk_history_payload"
                phx-value-id={entry.id}
                class="btn btn-xs btn-soft"
              >
                Carregar
              </button>
              <button
                id={"bulk-history-fav-#{entry.id}"}
                type="button"
                phx-click="toggle_bulk_history_favorite"
                phx-value-id={entry.id}
                class={[
                  "btn btn-xs",
                  entry.favorite && "btn-primary",
                  !entry.favorite && "btn-soft"
                ]}
              >
                {if entry.favorite, do: "Fixado", else: "Fixar"}
              </button>
            </div>
          </article>
        </div>
      </div>

      <.form
        for={@bulk_form}
        id="bulk-capture-form"
        phx-submit="submit_bulk_capture"
        class="mt-3"
      >
        <section
          id="bulk-sharing-controls"
          class="border border-base-content/20 bg-base-100/74 mb-3 rounded-lg px-3 py-2"
        >
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/85">
                Compartilhamento no vínculo
              </p>
              <p class="text-xs text-base-content/75">
                Marque para publicar os lançamentos financeiros deste envio na visão conjunta.
              </p>
            </div>

            <label
              for="bulk-share-finances"
              class="inline-flex items-center gap-2 text-xs font-medium text-base-content/90"
            >
              <input type="hidden" name="bulk[share_finances]" value="false" />
              <input
                id="bulk-share-finances"
                type="checkbox"
                name="bulk[share_finances]"
                value="true"
                checked={@bulk_share_finances}
                disabled={Enum.empty?(@account_links)}
                class="toggle toggle-primary toggle-sm"
              /> Compartilhar lançamentos financeiros
            </label>
          </div>

          <div class="mt-3 grid gap-2 sm:grid-cols-[160px_1fr] sm:items-center">
            <label for="bulk-share-link-id" class="text-xs font-medium text-base-content/70">
              Vínculo destino
            </label>

            <select
              id="bulk-share-link-id"
              name="bulk[share_link_id]"
              class="select select-bordered select-sm w-full"
              disabled={Enum.empty?(@account_links)}
            >
              <option :if={Enum.empty?(@account_links)} value="">Sem vínculo ativo</option>
              <option
                :for={link <- @account_links}
                value={link.id}
                selected={to_string(link.id) == to_string(@bulk_share_link_id)}
              >
                {bulk_share_link_label(link, @current_user_id)}
              </option>
            </select>
          </div>
        </section>

        <div class="border border-base-content/20 bg-base-100/74 mb-3 flex items-center justify-between gap-3 rounded-lg px-3 py-2">
          <div>
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/85">
              Modo estrito
            </p>
            <p class="text-xs text-base-content/75">
              Bloqueia importação quando existir qualquer linha com erro.
            </p>
          </div>
          <button
            id="bulk-strict-toggle"
            type="button"
            phx-click="toggle_bulk_strict_mode"
            class={[
              "btn btn-xs",
              @bulk_strict_mode && "btn-primary",
              !@bulk_strict_mode && "btn-soft"
            ]}
          >
            {if @bulk_strict_mode, do: "Ligado", else: "Desligado"}
          </button>
        </div>

        <.input
          field={@bulk_form[:payload]}
          id="bulk-payload-input"
          type="textarea"
          label="Linhas para interpretação"
          rows="9"
          placeholder={bulk_capture_placeholder(@bulk_top_categories)}
          phx-hook="BulkCaptureEditor"
          data-preview-selector="#bulk-preview-btn"
          data-import-selector="#bulk-import-btn"
          data-fix-all-selector="#bulk-fix-all-btn"
          required
        />
        <div
          id="bulk-shortcuts-help"
          class="flex flex-wrap gap-[0.45rem] border border-base-content/22 bg-base-100/75 mt-2 rounded-lg px-3 py-2"
        >
          <span class="inline-flex items-center border border-base-content/18 rounded-full px-[0.52rem] py-[0.18rem] font-mono text-[0.68rem] text-base-content/92 bg-base-100/72">
            Tab: completar tipo ou campo
          </span>
          <span class="inline-flex items-center border border-base-content/18 rounded-full px-[0.52rem] py-[0.18rem] font-mono text-[0.68rem] text-base-content/92 bg-base-100/72">
            Ctrl/Cmd+Enter: preview
          </span>
          <span class="inline-flex items-center border border-base-content/18 rounded-full px-[0.52rem] py-[0.18rem] font-mono text-[0.68rem] text-base-content/92 bg-base-100/72">
            Ctrl/Cmd+Shift+F: corrigir tudo
          </span>
          <span class="inline-flex items-center border border-base-content/18 rounded-full px-[0.52rem] py-[0.18rem] font-mono text-[0.68rem] text-base-content/92 bg-base-100/72">
            Ctrl/Cmd+Shift+I: importar
          </span>
        </div>
        <div class="mt-3 grid gap-2 sm:grid-cols-2">
          <button
            id="bulk-preview-btn"
            type="submit"
            name="action"
            value="preview"
            phx-disable-with="Interpretando..."
            class="btn btn-soft w-full"
          >
            Pré-visualizar linhas
          </button>
          <button
            id="bulk-import-btn"
            type="submit"
            name="action"
            value="import"
            phx-disable-with="Importando..."
            class="btn btn-primary w-full"
          >
            Importar agora
          </button>
        </div>
      </.form>

      <div
        :if={@bulk_preview}
        id="bulk-capture-preview"
        class="border-t border-base-content/16 pt-[0.45rem] mt-4 space-y-3"
      >
        <% current_block =
          BulkImport.current_bulk_import_block(
            @bulk_preview,
            @bulk_import_block_size,
            @bulk_import_block_index
          ) %>

        <div class="flex items-center justify-between gap-2">
          <p class="text-sm font-medium text-base-content/90">
            Revisão automática das linhas interpretadas
          </p>
          <button
            :if={bulk_preview_fixable_count(@bulk_preview.entries) > 0}
            id="bulk-fix-all-btn"
            type="button"
            phx-click="apply_all_bulk_fixes"
            class="btn btn-xs btn-soft"
          >
            Aplicar todas as correções ({bulk_preview_fixable_count(@bulk_preview.entries)})
          </button>
        </div>

        <section
          id="bulk-block-controls"
          class="rounded-xl border border-base-content/12 bg-base-100/35 p-3"
        >
          <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                Importação incremental por bloco
              </p>
              <p class="text-xs text-base-content/65">
                Revise diferenças entre texto original e normalizado antes de confirmar cada bloco.
              </p>
            </div>

            <div class="flex flex-wrap items-center gap-2">
              <button
                id="bulk-prev-block-btn"
                type="button"
                phx-click="prev_bulk_block"
                class="btn btn-xs btn-soft"
                disabled={current_block.total <= 1}
              >
                Bloco anterior
              </button>
              <button
                id="bulk-next-block-btn"
                type="button"
                phx-click="next_bulk_block"
                class="btn btn-xs btn-soft"
                disabled={current_block.total <= 1}
              >
                Próximo bloco
              </button>
              <button
                id="bulk-import-block-btn"
                type="button"
                phx-click="import_bulk_block"
                class="btn btn-xs btn-primary"
                disabled={current_block.total == 0}
              >
                Importar bloco atual
              </button>
            </div>
          </div>

          <div class="mt-2 flex flex-wrap items-center gap-2 text-xs">
            <span class="text-base-content/70">Tamanho do bloco:</span>
            <button
              id="bulk-block-size-2"
              type="button"
              phx-click="set_bulk_block_size"
              phx-value-size="2"
              class={[
                "btn btn-xs",
                @bulk_import_block_size == 2 && "btn-primary",
                @bulk_import_block_size != 2 && "btn-soft"
              ]}
            >
              2
            </button>
            <button
              id="bulk-block-size-3"
              type="button"
              phx-click="set_bulk_block_size"
              phx-value-size="3"
              class={[
                "btn btn-xs",
                @bulk_import_block_size == 3 && "btn-primary",
                @bulk_import_block_size != 3 && "btn-soft"
              ]}
            >
              3
            </button>
            <button
              id="bulk-block-size-5"
              type="button"
              phx-click="set_bulk_block_size"
              phx-value-size="5"
              class={[
                "btn btn-xs",
                @bulk_import_block_size == 5 && "btn-primary",
                @bulk_import_block_size != 5 && "btn-soft"
              ]}
            >
              5
            </button>
            <button
              id="bulk-block-size-10"
              type="button"
              phx-click="set_bulk_block_size"
              phx-value-size="10"
              class={[
                "btn btn-xs",
                @bulk_import_block_size == 10 && "btn-primary",
                @bulk_import_block_size != 10 && "btn-soft"
              ]}
            >
              10
            </button>
          </div>

          <p class="mt-2 text-xs text-base-content/70">
            {if current_block.total == 0,
              do: "Sem linhas válidas para blocos.",
              else:
                "Bloco #{current_block.index + 1}/#{current_block.total} (#{length(current_block.entries)} linhas)."}
          </p>

          <div :if={current_block.entries != []} id="bulk-block-diff" class="mt-3 space-y-2">
            <article
              :for={entry <- current_block.entries}
              id={"bulk-block-diff-line-#{entry.line_number}"}
              class="rounded-lg border border-base-content/12 bg-base-100/45 p-2"
            >
              <p class="text-xs text-base-content/70">Linha {entry.line_number}</p>
              <div class="mt-1 grid gap-2 lg:grid-cols-2">
                <div class="rounded-md border border-base-content/12 bg-base-100/70 p-2">
                  <p class="text-[0.65rem] uppercase tracking-wide text-base-content/60">
                    Original
                  </p>
                  <p class="mt-1 break-words text-xs text-base-content/80">{entry.raw}</p>
                </div>
                <div class={[
                  "rounded-md border p-2",
                  bulk_line_changed?(entry) && "border-info/30 bg-info/10",
                  !bulk_line_changed?(entry) && "border-base-content/12 bg-base-100/70"
                ]}>
                  <p class="text-[0.65rem] uppercase tracking-wide text-base-content/60">
                    Normalizado
                  </p>
                  <p class="mt-1 break-words text-xs text-base-content/80">
                    {bulk_entry_normalized_line(entry)}
                  </p>
                </div>
              </div>
            </article>
          </div>
        </section>

        <div class="grid gap-2 sm:grid-cols-4">
          <article class="micro-surface rounded-lg p-3">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Linhas</p>
            <p class="mt-1 text-lg font-semibold text-base-content">
              {@bulk_preview.lines_total}
            </p>
          </article>
          <article class="micro-surface rounded-lg p-3">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Válidas</p>
            <p class="mt-1 text-lg font-semibold text-success">
              {@bulk_preview.valid_total}
            </p>
          </article>
          <article class="micro-surface rounded-lg p-3">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Com erro</p>
            <p class="mt-1 text-lg font-semibold text-warning-content">
              {@bulk_preview.invalid_total}
            </p>
          </article>
          <article class="micro-surface rounded-lg p-3">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Ignoradas</p>
            <p class="mt-1 text-lg font-semibold text-base-content">
              {@bulk_preview.ignored_total}
            </p>
          </article>
        </div>

        <%!-- Scoring summary --%>
        <div
          id="bulk-scoring-summary"
          class="rounded-lg border border-base-content/12 bg-base-100/40 px-3 py-2"
        >
          <%= cond do %>
            <% @bulk_preview.scoring.errors == 0 and @bulk_preview.scoring.low_confidence == 0 and @bulk_preview.scoring.medium_confidence == 0 and @bulk_preview.valid_total > 0 -> %>
              <p class="text-xs font-medium text-success">
                <.icon name="hero-check-circle" class="w-3.5 h-3.5 inline-block mr-1" />Pronto para importar — todas as linhas com alta confiança.
              </p>
            <% @bulk_preview.scoring.medium_confidence > 0 or @bulk_preview.scoring.low_confidence > 0 -> %>
              <p class="text-xs text-warning-content">
                <.icon name="hero-exclamation-triangle" class="w-3.5 h-3.5 inline-block mr-1" />
                {@bulk_preview.scoring.medium_confidence + @bulk_preview.scoring.low_confidence} linha(s) com confiança reduzida — revise antes de importar.
              </p>
            <% true -> %>
              <p class="text-xs text-base-content/60">
                {@bulk_preview.scoring.high_confidence} alta · {@bulk_preview.scoring.medium_confidence} média · {@bulk_preview.scoring.low_confidence} baixa · {@bulk_preview.scoring.errors} erro(s)
              </p>
          <% end %>
        </div>

        <div class="max-h-72 space-y-2 overflow-y-auto rounded-xl border border-base-content/12 bg-base-100/40 p-3">
          <article
            :for={entry <- @bulk_preview.entries}
            id={"bulk-preview-line-#{entry.line_number}"}
            class="border-base-content/24 bg-base-100/82 transition-colors hover:border-info/42 hover:bg-info/11 rounded-lg border p-2"
          >
            <div class="flex items-start justify-between gap-2">
              <p class="text-xs text-base-content/70">Linha {entry.line_number}</p>
              <span class={[
                "rounded px-2 py-0.5 text-[0.65rem] font-semibold uppercase tracking-wide",
                bulk_preview_status_badge_class(entry.status)
              ]}>
                {bulk_preview_status_label(entry.status)}
              </span>
            </div>
            <p class="font-mono text-[0.74rem] leading-[1.5] text-base-content/93 mt-1">
              {entry.raw}
            </p>
            <p class="mt-1 text-sm font-medium text-base-content/95">
              {bulk_preview_entry_label(entry)}
            </p>

            <div
              :if={entry.status == :valid and Map.get(entry, :inferred_fields, []) != []}
              class="mt-1 flex flex-wrap gap-1"
            >
              <span
                :for={field <- Map.get(entry, :inferred_fields, [])}
                class="rounded px-1.5 py-0.5 text-[0.6rem] font-medium uppercase tracking-wide border border-accent/38 bg-accent/14 text-accent-content"
              >
                {field} inferido
              </span>
            </div>

            <div
              :if={entry.status == :invalid and Map.get(entry, :suggested_line)}
              class="mt-2 rounded-md border border-info/30 bg-info/10 p-2"
            >
              <p class="text-xs text-info/90">
                Sugestão: {entry.suggested_line}
              </p>
              <button
                id={"bulk-fix-line-#{entry.line_number}"}
                type="button"
                phx-click="apply_bulk_line_fix"
                phx-value-line={entry.line_number}
                class="btn btn-xs btn-soft mt-2"
              >
                Aplicar correção
              </button>
            </div>
          </article>
        </div>
      </div>

      <div :if={@bulk_result} id="bulk-capture-result" class="mt-4 space-y-3">
        <div class="grid gap-2 sm:grid-cols-2">
          <article class="micro-surface rounded-lg p-3">
            <p class="text-xs uppercase tracking-wide text-base-content/65">Tarefas criadas</p>
            <p class="mt-1 text-lg font-semibold text-base-content">
              {@bulk_result.created.tasks}
            </p>
          </article>
          <article class="micro-surface rounded-lg p-3">
            <p class="text-xs uppercase tracking-wide text-base-content/65">
              Lançamentos criados
            </p>
            <p class="mt-1 text-lg font-semibold text-base-content">
              {@bulk_result.created.finances}
            </p>
          </article>
        </div>

        <button
          :if={@last_bulk_import}
          id="bulk-undo-btn"
          type="button"
          phx-click="undo_last_bulk_import"
          class="btn btn-sm btn-soft"
        >
          Desfazer última importação
        </button>

        <div
          :if={@bulk_result.errors != []}
          class="rounded-xl border border-warning/38 bg-warning/12 p-3"
        >
          <p class="text-xs font-semibold uppercase tracking-wide text-warning-content">
            Linhas com erro
          </p>
          <ul class="mt-2 space-y-1 text-xs text-warning-content/90">
            <li :for={error <- @bulk_result.errors}>{error}</li>
          </ul>
        </div>
      </div>
    </section>
    """
  end

  defp sorted_bulk_templates(favorites) do
    templates = [
      %{key: "mixed", label: "Misto"},
      %{key: "tasks", label: "Tarefas"},
      %{key: "finance", label: "Financeiro"}
    ]

    favorite_set = MapSet.new(favorites)

    Enum.sort_by(templates, fn template ->
      if MapSet.member?(favorite_set, template.key), do: 0, else: 1
    end)
  end

  defp template_favorited?(favorites, key), do: key in favorites

  defp bulk_capture_placeholder([top_cat | _]) do
    "tarefa: reunião amanhã\nfinanceiro: #{top_cat} 35"
  end

  defp bulk_capture_placeholder(_) do
    "tarefa: reunião amanhã\nfinanceiro: almoço 35"
  end

  defp bulk_preview_fixable_count(entries) when is_list(entries) do
    Enum.count(entries, fn entry ->
      entry.status == :invalid and is_binary(Map.get(entry, :suggested_line)) and
        Map.get(entry, :suggested_line) != ""
    end)
  end

  defp bulk_preview_fixable_count(_entries), do: 0

  defp bulk_preview_status_badge_class(:valid),
    do: "border border-success/35 bg-success/14 text-success-content"

  defp bulk_preview_status_badge_class(:invalid),
    do: "border border-warning/35 bg-warning/14 text-warning-content"

  defp bulk_preview_status_badge_class(:ignored),
    do: "border border-base-content/20 bg-base-100/60 text-base-content/70"

  defp bulk_preview_status_label(:valid), do: "válida"
  defp bulk_preview_status_label(:invalid), do: "erro"
  defp bulk_preview_status_label(:ignored), do: "ignorada"

  defp bulk_preview_entry_label(%{status: :ignored}), do: "Linha vazia ignorada"

  defp bulk_preview_entry_label(%{status: :invalid, error: error}),
    do: "Erro: #{error}"

  defp bulk_preview_entry_label(%{status: :valid, type: :task, attrs: attrs}) do
    title = Map.get(attrs, "title", "sem título")
    priority = Map.get(attrs, "priority", "prioridade padrão")
    date = Map.get(attrs, "due_on", "sem data")
    "Tarefa: #{title} • #{priority} • #{date}"
  end

  defp bulk_preview_entry_label(%{status: :valid, type: :finance, attrs: attrs}) do
    parts = [
      Map.get(attrs, "kind", "tipo pendente"),
      bulk_finance_expense_profile_label(attrs),
      bulk_finance_payment_method_label(attrs),
      format_bulk_amount(Map.get(attrs, "amount_cents")),
      Map.get(attrs, "category", "categoria pendente")
    ]

    "Financeiro: " <>
      (parts
       |> Enum.reject(&is_nil/1)
       |> Enum.join(" • "))
  end

  defp bulk_preview_entry_label(_), do: "Linha processada"

  defp bulk_entry_normalized_line(%{status: :valid, type: :task, attrs: attrs}) do
    title = Map.get(attrs, "title", "")

    [
      "tarefa: #{title}",
      Map.get(attrs, "due_on") && "data=#{Map.get(attrs, "due_on")}",
      Map.get(attrs, "priority") && "prioridade=#{Map.get(attrs, "priority")}",
      Map.get(attrs, "status") && "status=#{Map.get(attrs, "status")}",
      Map.get(attrs, "notes") && "notes=#{Map.get(attrs, "notes")}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
  end

  defp bulk_entry_normalized_line(%{status: :valid, type: :finance, attrs: attrs}) do
    [
      "financeiro: tipo=#{Map.get(attrs, "kind", "expense")}",
      Map.get(attrs, "kind") == "expense" &&
        "natureza=#{Map.get(attrs, "expense_profile", "variable")}",
      Map.get(attrs, "kind") == "expense" &&
        "pagamento=#{Map.get(attrs, "payment_method", "debit")}",
      Map.get(attrs, "amount_cents") && "valor=#{Map.get(attrs, "amount_cents")}",
      Map.get(attrs, "category") && "categoria=#{Map.get(attrs, "category")}",
      Map.get(attrs, "occurred_on") && "data=#{Map.get(attrs, "occurred_on")}",
      Map.get(attrs, "description") && "descricao=#{Map.get(attrs, "description")}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
  end

  defp bulk_entry_normalized_line(entry), do: Map.get(entry, :raw, "")

  defp bulk_line_changed?(entry) do
    String.trim(Map.get(entry, :raw, "")) != String.trim(bulk_entry_normalized_line(entry))
  end

  defp format_bulk_amount(amount_cents) when is_integer(amount_cents),
    do: format_money(amount_cents)

  defp format_bulk_amount(_), do: "valor pendente"

  defp bulk_finance_expense_profile_label(attrs) do
    if Map.get(attrs, "kind") == "expense" do
      case Map.get(attrs, "expense_profile") do
        "fixed" -> "fixa"
        "variable" -> "variável"
        _ -> "variável"
      end
    else
      nil
    end
  end

  defp bulk_finance_payment_method_label(attrs) do
    if Map.get(attrs, "kind") == "expense" do
      case Map.get(attrs, "payment_method") do
        "credit" -> "crédito"
        "debit" -> "débito"
        _ -> "débito"
      end
    else
      nil
    end
  end

  defp bulk_share_link_label(link, current_user_id) do
    partner_email =
      cond do
        current_user_id == link.user_a_id and is_map(link.user_b) ->
          Map.get(link.user_b, :email, "conta vinculada")

        current_user_id == link.user_b_id and is_map(link.user_a) ->
          Map.get(link.user_a, :email, "conta vinculada")

        true ->
          "conta vinculada"
      end

    "Vínculo ##{link.id} • #{partner_email}"
  end
end
