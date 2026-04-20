defmodule OrganizerWeb.DashboardLive.BulkEventHandlers do
  @moduledoc """
  Handlers de eventos LiveView relacionados ao bulk import do DashboardLive.

  Uso:
      use OrganizerWeb.DashboardLive.BulkEventHandlers

  Injeta todos os `handle_event` de bulk import no módulo chamador via macro `__using__`.
  """

  defmacro __using__(_opts) do
    quote do
      alias OrganizerWeb.DashboardLive.BulkImport
      alias Organizer.Planning.FieldSuggester

      @impl true
      def handle_event("apply_bulk_template", %{"template" => key}, socket)
          when key in @bulk_template_keys do
        payload = BulkImport.bulk_template_payload(key)

        {:noreply,
         socket
         |> assign(:bulk_form, Phoenix.Component.to_form(%{"payload" => payload}, as: :bulk))
         |> assign(:bulk_payload_text, payload)
         |> assign(:bulk_result, nil)
         |> assign(:bulk_preview, nil)
         |> assign(:bulk_import_block_index, 0)
         |> put_flash(:info, "Template pronto. Revise e interprete antes de importar.")}
      end

      @impl true
      def handle_event("toggle_bulk_template_favorite", %{"template" => key}, socket)
          when key in @bulk_template_keys do
        favorites = BulkImport.toggle_string_flag(socket.assigns.bulk_template_favorites, key)

        {:noreply,
         socket
         |> assign(:bulk_template_favorites, favorites)
         |> put_flash(:info, "Template atualizado nos favoritos.")}
      end

      @impl true
      def handle_event("copy_bulk_markdown_reference", _params, socket) do
        markdown = BulkImport.bulk_reference_markdown_template()

        {:noreply,
         socket
         |> push_event("copy-to-clipboard", %{text: markdown})
         |> put_flash(:info, "Template Markdown copiado para facilitar o uso em chat de IA.")}
      end

      @impl true
      def handle_event("load_bulk_history_payload", %{"id" => id}, socket) do
        case BulkImport.find_bulk_history_entry(socket.assigns.bulk_recent_payloads, id) do
          nil ->
            {:noreply, put_flash(socket, :error, "Payload do histórico não encontrado.")}

          entry ->
            {:noreply,
             socket
             |> assign(:bulk_payload_text, entry.payload)
             |> assign(
               :bulk_form,
               Phoenix.Component.to_form(%{"payload" => entry.payload}, as: :bulk)
             )
             |> assign(:bulk_result, nil)
             |> assign(:bulk_preview, nil)
             |> assign(:bulk_import_block_index, 0)
             |> put_flash(:info, "Payload carregado do histórico.")}
        end
      end

      @impl true
      def handle_event("toggle_bulk_history_favorite", %{"id" => id}, socket) do
        history =
          Enum.map(socket.assigns.bulk_recent_payloads, fn entry ->
            if to_string(entry.id) == to_string(id) do
              Map.update(entry, :favorite, true, &(!&1))
            else
              entry
            end
          end)

        {:noreply, assign(socket, :bulk_recent_payloads, history)}
      end

      @impl true
      def handle_event("set_bulk_block_size", %{"size" => raw_size}, socket) do
        size =
          case Integer.parse(to_string(raw_size)) do
            {value, ""} when value in [2, 3, 5, 10] -> value
            _ -> socket.assigns.bulk_import_block_size
          end

        {:noreply,
         socket
         |> assign(:bulk_import_block_size, size)
         |> assign(:bulk_import_block_index, 0)}
      end

      @impl true
      def handle_event("next_bulk_block", _params, socket) do
        total =
          BulkImport.bulk_block_total(
            socket.assigns.bulk_preview,
            socket.assigns.bulk_import_block_size
          )

        next_index =
          if total <= 0 do
            0
          else
            min(socket.assigns.bulk_import_block_index + 1, total - 1)
          end

        {:noreply, assign(socket, :bulk_import_block_index, next_index)}
      end

      @impl true
      def handle_event("prev_bulk_block", _params, socket) do
        {:noreply,
         assign(
           socket,
           :bulk_import_block_index,
           max(socket.assigns.bulk_import_block_index - 1, 0)
         )}
      end

      @impl true
      def handle_event("import_bulk_block", _params, socket) do
        block =
          BulkImport.current_bulk_import_block(
            socket.assigns.bulk_preview,
            socket.assigns.bulk_import_block_size,
            socket.assigns.bulk_import_block_index
          )

        if block.total == 0 or block.entries == [] do
          {:noreply, put_flash(socket, :error, "Nenhum bloco válido disponível para importação.")}
        else
          result =
            BulkImport.import_preview_entries(
              socket.assigns.current_scope,
              block.entries,
              socket.assigns.bulk_preview
            )

          imported_line_numbers = Enum.map(block.entries, & &1.line_number)

          remaining_payload =
            BulkImport.remove_bulk_payload_lines(
              socket.assigns.bulk_payload_text,
              imported_line_numbers
            )

          remaining_preview = BulkImport.preview_bulk_payload(remaining_payload)

          created_total = result.created.tasks + result.created.finances

          share_result =
            maybe_share_imported_finances(
              socket.assigns.current_scope,
              result.last_bulk_import,
              %{
                share_finances?: socket.assigns.bulk_share_finances,
                share_link_id: socket.assigns.bulk_share_link_id
              }
            )

          socket =
            socket
            |> BulkImport.remember_bulk_payload(socket.assigns.bulk_payload_text)
            |> assign(:bulk_result, result)
            |> assign(:last_bulk_import, result.last_bulk_import)
            |> assign(:bulk_payload_text, remaining_payload)
            |> assign(
              :bulk_form,
              Phoenix.Component.to_form(%{"payload" => remaining_payload}, as: :bulk)
            )
            |> assign(:bulk_preview, remaining_preview)
            |> assign(
              :bulk_import_block_index,
              BulkImport.clamp_bulk_block_index(
                socket.assigns.bulk_import_block_index,
                remaining_preview,
                socket.assigns.bulk_import_block_size
              )
            )

          socket =
            if created_total > 0 do
              socket
              |> put_flash(
                :info,
                "Bloco importado: #{result.created.tasks} tarefas e #{result.created.finances} lançamentos." <>
                  bulk_share_success_suffix(share_result)
              )
              |> load_operation_collections()
              |> refresh_dashboard_insights()
            else
              socket
            end

          socket =
            if result.errors != [] or share_result.errors > 0 do
              put_flash(
                socket,
                :error,
                build_bulk_error_message(
                  result.errors != [],
                  share_result.errors,
                  "Alguns itens do bloco não puderam ser importados."
                )
              )
            else
              socket
            end

          {:noreply, socket}
        end
      end

      @impl true
      def handle_event("apply_bulk_line_fix", %{"line" => line_number}, socket) do
        with {line_number, ""} <- Integer.parse(to_string(line_number)),
             {:ok, payload} <-
               BulkImport.apply_bulk_fix_for_line(socket.assigns.bulk_payload_text, line_number) do
          preview = BulkImport.preview_bulk_payload(payload)

          {:noreply,
           socket
           |> assign(:bulk_payload_text, payload)
           |> assign(:bulk_form, Phoenix.Component.to_form(%{"payload" => payload}, as: :bulk))
           |> assign(:bulk_preview, preview)
           |> assign(:bulk_result, nil)
           |> assign(:bulk_import_block_index, 0)
           |> put_flash(:info, "Correção aplicada na linha #{line_number}.")}
        else
          _ ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Não foi possível aplicar correção automática para essa linha."
             )}
        end
      end

      @impl true
      def handle_event("apply_all_bulk_fixes", _params, socket) do
        case BulkImport.apply_all_bulk_fixes(socket.assigns.bulk_payload_text) do
          {:ok, payload, fixed_count} when fixed_count > 0 ->
            preview = BulkImport.preview_bulk_payload(payload)

            {:noreply,
             socket
             |> assign(:bulk_payload_text, payload)
             |> assign(:bulk_form, Phoenix.Component.to_form(%{"payload" => payload}, as: :bulk))
             |> assign(:bulk_preview, preview)
             |> assign(:bulk_result, nil)
             |> assign(:bulk_import_block_index, 0)
             |> put_flash(:info, "#{fixed_count} correções aplicadas automaticamente.")}

          {:ok, _payload, 0} ->
            {:noreply,
             put_flash(socket, :error, "Nenhuma sugestão disponível para correção em lote.")}

          {:error, _reason} ->
            {:noreply,
             put_flash(socket, :error, "Não foi possível aplicar correções automáticas em lote.")}
        end
      end

      @impl true
      def handle_event("toggle_bulk_strict_mode", _params, socket) do
        strict_mode = !socket.assigns.bulk_strict_mode

        {:noreply,
         socket
         |> assign(:bulk_strict_mode, strict_mode)
         |> put_flash(
           :info,
           if(strict_mode,
             do: "Modo estrito ativado. A importação será bloqueada se houver erros.",
             else: "Modo estrito desativado. Linhas válidas podem ser importadas mesmo com erros."
           )
         )}
      end

      @impl true
      def handle_event(
            "submit_bulk_capture",
            %{"bulk" => %{"payload" => payload}} = params,
            socket
          ) do
        share_preferences = parse_bulk_share_preferences(socket, params)

        socket =
          socket
          |> assign(:bulk_share_finances, share_preferences.share_finances?)
          |> assign(:bulk_share_link_id, share_preferences.share_link_id)

        if byte_size(payload) > @max_bulk_payload_bytes do
          {:noreply,
           put_flash(
             socket,
             :error,
             "O payload excede o tamanho máximo permitido (50 KB). Reduza o conteúdo e tente novamente."
           )}
        else
          case Map.get(params, "action", "import") do
            "preview" ->
              preview = BulkImport.preview_bulk_payload(payload)

              socket =
                socket
                |> BulkImport.remember_bulk_payload(payload)
                |> assign(:bulk_payload_text, payload)
                |> assign(:bulk_preview, preview)
                |> assign(:bulk_result, nil)
                |> assign(:bulk_import_block_index, 0)
                |> assign(
                  :bulk_form,
                  Phoenix.Component.to_form(%{"payload" => payload}, as: :bulk)
                )

              socket =
                if preview.valid_total > 0 do
                  put_flash(socket, :info, "Pré-visualização pronta para importação.")
                else
                  put_flash(socket, :error, "Nenhuma linha válida encontrada para importar.")
                end

              {:noreply, socket}

            _ ->
              preview = BulkImport.preview_bulk_payload(payload)

              if socket.assigns.bulk_strict_mode and preview.invalid_total > 0 do
                {:noreply,
                 socket
                 |> BulkImport.remember_bulk_payload(payload)
                 |> assign(:bulk_payload_text, payload)
                 |> assign(:bulk_preview, preview)
                 |> assign(:bulk_result, nil)
                 |> assign(:bulk_import_block_index, 0)
                 |> assign(
                   :bulk_form,
                   Phoenix.Component.to_form(%{"payload" => payload}, as: :bulk)
                 )
                 |> put_flash(
                   :error,
                   "Modo estrito ativo: corrija as linhas com erro antes de importar."
                 )}
              else
                result =
                  BulkImport.import_bulk_payload(payload, socket.assigns.current_scope, preview)

                share_result =
                  maybe_share_imported_finances(
                    socket.assigns.current_scope,
                    result.last_bulk_import,
                    share_preferences
                  )

                created_total =
                  result.created.tasks + result.created.finances

                socket =
                  socket
                  |> BulkImport.remember_bulk_payload(payload)
                  |> assign(:bulk_result, result)
                  |> assign(:bulk_preview, result.preview)
                  |> assign(:last_bulk_import, result.last_bulk_import)
                  |> assign(:bulk_payload_text, "")
                  |> assign(:bulk_import_block_index, 0)
                  |> assign(:bulk_form, Phoenix.Component.to_form(%{"payload" => ""}, as: :bulk))

                socket =
                  if created_total > 0 do
                    socket
                    |> put_flash(
                      :info,
                      "Importação concluída: #{result.created.tasks} tarefas e #{result.created.finances} lançamentos." <>
                        bulk_share_success_suffix(share_result)
                    )
                    |> load_operation_collections()
                    |> refresh_dashboard_insights()
                  else
                    socket
                  end

                socket =
                  if result.errors != [] or share_result.errors > 0 do
                    put_flash(
                      socket,
                      :error,
                      build_bulk_error_message(
                        result.errors != [],
                        share_result.errors,
                        "Algumas linhas não puderam ser processadas. Revise os detalhes na seção de importação."
                      )
                    )
                  else
                    socket
                  end

                {:noreply, socket}
              end
          end
        end
      end

      @impl true
      def handle_event(
            "validate_bulk_line",
            %{"line" => raw_line, "index" => index_value},
            socket
          ) do
        index =
          case index_value do
            v when is_integer(v) ->
              v

            v ->
              case Integer.parse(to_string(v)) do
                {i, ""} -> i
                _ -> nil
              end
          end

        case index do
          nil ->
            {:reply, %{}, socket}

          index ->
            entry = BulkImport.build_bulk_preview_entry(raw_line, index)
            score = Organizer.Planning.BulkScoring.score_entry(entry)

            {:reply,
             %{
               index: index,
               entry: %{
                 status: entry.status,
                 error: entry[:error],
                 suggested_line: entry[:suggested_line],
                 type: entry[:type]
               },
               score: score.score,
               confidence_level: score.confidence_level |> to_string(),
               feedback: score.feedback
             }, socket}
        end
      end

      @impl true
      def handle_event("select_disambiguation", %{"index" => index, "line" => new_line}, socket) do
        with index when is_integer(index) <- BulkImport.parse_index(index),
             preview when not is_nil(preview) <- socket.assigns.bulk_preview do
          updated_entry = BulkImport.build_bulk_preview_entry(new_line, index)

          updated_entries =
            Enum.map(preview.entries, fn entry ->
              if entry.line_number == index, do: updated_entry, else: entry
            end)

          updated_preview = %{
            preview
            | entries: updated_entries,
              valid_total: Enum.count(updated_entries, &(&1.status == :valid)),
              invalid_total: Enum.count(updated_entries, &(&1.status == :invalid)),
              ignored_total: Enum.count(updated_entries, &(&1.status == :ignored)),
              scoring: Organizer.Planning.BulkScoring.score_entries(updated_entries)
          }

          {:noreply, assign(socket, :bulk_preview, updated_preview)}
        else
          _ -> {:noreply, socket}
        end
      end

      @impl true
      def handle_event("complete_field_value", %{"field" => field, "prefix" => prefix}, socket) do
        {:ok, completed} = FieldSuggester.complete(field, socket.assigns.current_scope, prefix)

        {:reply, %{field: field, completed: completed}, socket}
      end

      @impl true
      def handle_event("undo_last_bulk_import", _params, socket) do
        case socket.assigns.last_bulk_import do
          nil ->
            {:noreply, put_flash(socket, :error, "Não há importação recente para desfazer.")}

          last_bulk_import ->
            undo = BulkImport.undo_bulk_import(last_bulk_import, socket.assigns.current_scope)

            removed_total = undo.removed.tasks + undo.removed.finances

            socket =
              socket
              |> assign(:last_bulk_import, nil)
              |> assign(:bulk_result, nil)
              |> assign(:bulk_preview, nil)
              |> assign(:bulk_import_block_index, 0)

            socket =
              if removed_total > 0 do
                socket
                |> put_flash(
                  :info,
                  "Importação desfeita: #{undo.removed.tasks} tarefas e #{undo.removed.finances} lançamentos removidos."
                )
                |> load_operation_collections()
                |> refresh_dashboard_insights()
              else
                socket
              end

            socket =
              if undo.errors != [] do
                put_flash(socket, :error, "Nem todos os itens puderam ser removidos ao desfazer.")
              else
                socket
              end

            {:noreply, socket}
        end
      end

      defp parse_bulk_share_preferences(socket, params) do
        bulk_params = Map.get(params, "bulk", %{})
        link_ids = Enum.map(socket.assigns.account_links, & &1.id)
        fallback_link_id = socket.assigns.bulk_share_link_id || List.first(link_ids)
        raw_link_id = Map.get(bulk_params, "share_link_id")
        parsed_link_id = parse_optional_integer(raw_link_id)

        link_id =
          cond do
            parsed_link_id in link_ids -> parsed_link_id
            fallback_link_id in link_ids -> fallback_link_id
            true -> nil
          end

        share_finances? =
          truthy_param?(Map.get(bulk_params, "share_finances")) and is_integer(link_id)

        %{share_finances?: share_finances?, share_link_id: link_id}
      end

      defp maybe_share_imported_finances(
             scope,
             %{finances: finance_ids},
             %{share_finances?: true, share_link_id: link_id}
           )
           when is_list(finance_ids) and is_integer(link_id) do
        Enum.reduce(finance_ids, %{shared_count: 0, errors: 0}, fn finance_id, acc ->
          case Organizer.SharedFinance.share_finance_entry(scope, finance_id, link_id) do
            {:ok, _entry} ->
              %{acc | shared_count: acc.shared_count + 1}

            _ ->
              %{acc | errors: acc.errors + 1}
          end
        end)
      end

      defp maybe_share_imported_finances(_scope, _last_bulk_import, _share_preferences) do
        %{shared_count: 0, errors: 0}
      end

      defp bulk_share_success_suffix(%{shared_count: count}) when count > 0 do
        " #{count} lançamento(s) financeiro(s) compartilhado(s) neste vínculo."
      end

      defp bulk_share_success_suffix(_share_result), do: ""

      defp build_bulk_error_message(has_import_errors, share_errors, import_error_message) do
        []
        |> maybe_add_error_message(has_import_errors, import_error_message)
        |> maybe_add_error_message(
          share_errors > 0,
          "#{share_errors} lançamento(s) financeiro(s) não puderam ser compartilhado(s)."
        )
        |> Enum.join(" ")
      end

      defp maybe_add_error_message(messages, true, message), do: messages ++ [message]
      defp maybe_add_error_message(messages, false, _message), do: messages

      defp parse_optional_integer(value) when is_integer(value), do: value

      defp parse_optional_integer(value) when is_binary(value) do
        case Integer.parse(String.trim(value)) do
          {int, ""} -> int
          _ -> nil
        end
      end

      defp parse_optional_integer(_), do: nil

      defp truthy_param?(values) when is_list(values), do: Enum.any?(values, &truthy_param?/1)
      defp truthy_param?(value) when value in [true, "true", "on", "1", 1], do: true
      defp truthy_param?(_), do: false
    end
  end
end
