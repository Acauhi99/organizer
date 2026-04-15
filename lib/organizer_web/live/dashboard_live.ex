defmodule OrganizerWeb.DashboardLive do
  use OrganizerWeb, :live_view

  alias Organizer.Accounts
  alias Organizer.Accounts.Scope
  alias Organizer.Planning
  alias Organizer.Planning.AttributeValidation
  alias Contex.{Dataset, Plot}

  @task_status_filters ["all", "todo", "in_progress", "done"]
  @task_priority_filters ["all", "low", "medium", "high"]
  @task_days_filters ["7", "14", "30"]
  @finance_days_filters ["7", "30", "90"]
  @goal_status_filters ["all", "active", "paused", "done"]
  @analytics_days_filters ["7", "15", "30", "90", "365"]
  @analytics_capacity_filters ["5", "10", "15", "20", "30"]
  @bulk_template_keys ["mixed", "tasks", "finance", "goals"]
  @ops_tabs ["tasks", "finances", "goals"]

  @impl true
  def mount(_params, session, socket) do
    with token when is_binary(token) <- session["user_token"],
         {user, _inserted_at} <- Accounts.get_user_by_session_token(token) do
      scope = Scope.for_user(user)
      {:ok, initialize_dashboard_state(socket, scope)}
    else
      _ -> {:ok, redirect(socket, to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("apply_bulk_template", %{"template" => key}, socket)
      when key in @bulk_template_keys do
    payload = bulk_template_payload(key)

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
    favorites = toggle_string_flag(socket.assigns.bulk_template_favorites, key)

    {:noreply,
     socket
     |> assign(:bulk_template_favorites, favorites)
     |> put_flash(:info, "Template atualizado nos favoritos.")}
  end

  @impl true
  def handle_event("load_bulk_history_payload", %{"id" => id}, socket) do
    case find_bulk_history_entry(socket.assigns.bulk_recent_payloads, id) do
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
    total = bulk_block_total(socket.assigns.bulk_preview, socket.assigns.bulk_import_block_size)

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
     assign(socket, :bulk_import_block_index, max(socket.assigns.bulk_import_block_index - 1, 0))}
  end

  @impl true
  def handle_event("import_bulk_block", _params, socket) do
    block =
      current_bulk_import_block(
        socket.assigns.bulk_preview,
        socket.assigns.bulk_import_block_size,
        socket.assigns.bulk_import_block_index
      )

    if block.total == 0 or block.entries == [] do
      {:noreply, put_flash(socket, :error, "Nenhum bloco válido disponível para importação.")}
    else
      result =
        import_preview_entries(
          socket.assigns.current_scope,
          block.entries,
          socket.assigns.bulk_preview
        )

      imported_line_numbers = Enum.map(block.entries, & &1.line_number)

      remaining_payload =
        remove_bulk_payload_lines(socket.assigns.bulk_payload_text, imported_line_numbers)

      remaining_preview = preview_bulk_payload(remaining_payload)

      created_total = result.created.tasks + result.created.finances + result.created.goals

      socket =
        socket
        |> remember_bulk_payload(socket.assigns.bulk_payload_text)
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
          clamp_bulk_block_index(
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
            "Bloco importado: #{result.created.tasks} tarefas, #{result.created.finances} lançamentos e #{result.created.goals} metas."
          )
          |> load_operation_collections()
          |> refresh_dashboard_insights()
        else
          socket
        end

      socket =
        if result.errors != [] do
          put_flash(socket, :error, "Alguns itens do bloco não puderam ser importados.")
        else
          socket
        end

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("apply_bulk_line_fix", %{"line" => line_number}, socket) do
    with {line_number, ""} <- Integer.parse(to_string(line_number)),
         {:ok, payload} <- apply_bulk_fix_for_line(socket.assigns.bulk_payload_text, line_number) do
      preview = preview_bulk_payload(payload)

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
    case apply_all_bulk_fixes(socket.assigns.bulk_payload_text) do
      {:ok, payload, fixed_count} when fixed_count > 0 ->
        preview = preview_bulk_payload(payload)

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
  def handle_event("submit_bulk_capture", %{"bulk" => %{"payload" => payload}} = params, socket) do
    case Map.get(params, "action", "import") do
      "preview" ->
        preview = preview_bulk_payload(payload)

        socket =
          socket
          |> remember_bulk_payload(payload)
          |> assign(:bulk_payload_text, payload)
          |> assign(:bulk_preview, preview)
          |> assign(:bulk_result, nil)
          |> assign(:bulk_import_block_index, 0)
          |> assign(:bulk_form, Phoenix.Component.to_form(%{"payload" => payload}, as: :bulk))

        socket =
          if preview.valid_total > 0 do
            put_flash(socket, :info, "Pré-visualização pronta para importação.")
          else
            put_flash(socket, :error, "Nenhuma linha válida encontrada para importar.")
          end

        {:noreply, socket}

      _ ->
        preview = preview_bulk_payload(payload)

        if socket.assigns.bulk_strict_mode and preview.invalid_total > 0 do
          {:noreply,
           socket
           |> remember_bulk_payload(payload)
           |> assign(:bulk_payload_text, payload)
           |> assign(:bulk_preview, preview)
           |> assign(:bulk_result, nil)
           |> assign(:bulk_import_block_index, 0)
           |> assign(:bulk_form, Phoenix.Component.to_form(%{"payload" => payload}, as: :bulk))
           |> put_flash(
             :error,
             "Modo estrito ativo: corrija as linhas com erro antes de importar."
           )}
        else
          result = import_bulk_payload(payload, socket.assigns.current_scope, preview)
          created_total = result.created.tasks + result.created.finances + result.created.goals

          socket =
            socket
            |> remember_bulk_payload(payload)
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
                "Importação concluída: #{result.created.tasks} tarefas, #{result.created.finances} lançamentos e #{result.created.goals} metas."
              )
              |> push_event("form:reset", %{id: "bulk-capture-form"})
              |> load_operation_collections()
              |> refresh_dashboard_insights()
            else
              socket
            end

          socket =
            if result.errors != [] do
              put_flash(
                socket,
                :error,
                "Algumas linhas não puderam ser processadas. Revise os detalhes na seção de importação."
              )
            else
              socket
            end

          {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_event("undo_last_bulk_import", _params, socket) do
    case socket.assigns.last_bulk_import do
      nil ->
        {:noreply, put_flash(socket, :error, "Não há importação recente para desfazer.")}

      last_bulk_import ->
        undo = undo_bulk_import(last_bulk_import, socket.assigns.current_scope)

        removed_total = undo.removed.tasks + undo.removed.finances + undo.removed.goals

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
              "Importação desfeita: #{undo.removed.tasks} tarefas, #{undo.removed.finances} lançamentos e #{undo.removed.goals} metas removidos."
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

  @impl true
  def handle_event("filter_tasks", %{"filters" => filters}, socket) do
    task_filters =
      socket.assigns.task_filters
      |> Map.merge(normalize_task_filters(filters))
      |> sanitize_task_filters()

    {:noreply,
     socket
     |> assign(:task_filters, task_filters)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("filter_finances", %{"filters" => filters}, socket) do
    finance_filters =
      socket.assigns.finance_filters
      |> Map.merge(normalize_finance_filters(filters))
      |> sanitize_finance_filters()

    {:noreply,
     socket
     |> assign(:finance_filters, finance_filters)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("filter_goals", %{"filters" => filters}, socket) do
    goal_filters =
      socket.assigns.goal_filters
      |> Map.merge(normalize_goal_filters(filters))
      |> sanitize_goal_filters()

    {:noreply,
     socket
     |> assign(:goal_filters, goal_filters)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("filter_analytics", %{"filters" => filters}, socket) do
    analytics_filters =
      socket.assigns.analytics_filters
      |> Map.merge(normalize_analytics_filters(filters))
      |> sanitize_analytics_filters()

    {:noreply,
     socket
     |> assign(:analytics_filters, analytics_filters)
     |> refresh_dashboard_insights()}
  end

  @impl true
  def handle_event("set_analytics_days", %{"days" => days}, socket)
      when days in @analytics_days_filters do
    analytics_filters =
      socket.assigns.analytics_filters
      |> Map.put(:days, days)
      |> sanitize_analytics_filters()

    {:noreply,
     socket
     |> assign(:analytics_filters, analytics_filters)
     |> refresh_dashboard_insights()}
  end

  @impl true
  def handle_event("set_analytics_capacity", %{"planned_capacity" => capacity}, socket)
      when capacity in @analytics_capacity_filters do
    analytics_filters =
      socket.assigns.analytics_filters
      |> Map.put(:planned_capacity, capacity)
      |> sanitize_analytics_filters()

    {:noreply,
     socket
     |> assign(:analytics_filters, analytics_filters)
     |> refresh_dashboard_insights()}
  end

  @impl true
  def handle_event("set_ops_tab", %{"tab" => tab}, socket) when tab in @ops_tabs do
    {:noreply, assign(socket, :ops_tab, tab)}
  end

  @impl true
  def handle_event("start_edit_task", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:ops_tab, "tasks")
     |> assign(:editing_task_id, id)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("cancel_edit_task", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_task_id, nil)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("save_task", %{"_id" => id, "task" => attrs}, socket) do
    case Planning.update_task(socket.assigns.current_scope, id, attrs) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tarefa atualizada.")
         |> assign(:editing_task_id, nil)
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Verifique os campos da tarefa.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Tarefa não encontrada.")
         |> assign(:editing_task_id, nil)}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível atualizar a tarefa.")}
    end
  end

  @impl true
  def handle_event("delete_task", %{"id" => id}, socket) do
    case Planning.delete_task(socket.assigns.current_scope, id) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tarefa removida.")
         |> assign(:editing_task_id, nil)
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Tarefa não encontrada.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível remover a tarefa.")}
    end
  end

  @impl true
  def handle_event("start_edit_finance", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:ops_tab, "finances")
     |> assign(:editing_finance_id, id)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("cancel_edit_finance", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_finance_id, nil)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("save_finance", %{"_id" => id, "finance" => attrs}, socket) do
    case Planning.update_finance_entry(socket.assigns.current_scope, id, attrs) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Lançamento atualizado.")
         |> assign(:editing_finance_id, nil)
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Verifique os campos do lançamento.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Lançamento não encontrado.")
         |> assign(:editing_finance_id, nil)}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível atualizar o lançamento.")}
    end
  end

  @impl true
  def handle_event("delete_finance", %{"id" => id}, socket) do
    case Planning.delete_finance_entry(socket.assigns.current_scope, id) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Lançamento removido.")
         |> assign(:editing_finance_id, nil)
         |> load_operation_collections()
         |> refresh_dashboard_insights()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Lançamento não encontrado.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível remover o lançamento.")}
    end
  end

  @impl true
  def handle_event("start_edit_goal", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:ops_tab, "goals")
     |> assign(:editing_goal_id, id)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("cancel_edit_goal", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_goal_id, nil)
     |> load_operation_collections()}
  end

  @impl true
  def handle_event("save_goal", %{"_id" => id, "goal" => attrs}, socket) do
    case Planning.update_goal(socket.assigns.current_scope, id, attrs) do
      {:ok, _goal} ->
        {:noreply,
         socket
         |> put_flash(:info, "Meta atualizada.")
         |> assign(:editing_goal_id, nil)
         |> load_operation_collections()}

      {:error, {:validation, _details}} ->
        {:noreply, put_flash(socket, :error, "Verifique os campos da meta.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Meta não encontrada.")
         |> assign(:editing_goal_id, nil)}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível atualizar a meta.")}
    end
  end

  @impl true
  def handle_event("delete_goal", %{"id" => id}, socket) do
    case Planning.delete_goal(socket.assigns.current_scope, id) do
      {:ok, _goal} ->
        {:noreply,
         socket
         |> put_flash(:info, "Meta removida.")
         |> assign(:editing_goal_id, nil)
         |> load_operation_collections()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Meta não encontrada.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível remover a meta.")}
    end
  end

  defp initialize_dashboard_state(socket, scope) do
    socket
    |> assign(:current_scope, scope)
    |> assign(:bulk_form, to_form(%{"payload" => ""}, as: :bulk))
    |> assign(:bulk_payload_text, "")
    |> assign(:bulk_result, nil)
    |> assign(:bulk_preview, nil)
    |> assign(:bulk_strict_mode, false)
    |> assign(:last_bulk_import, nil)
    |> assign(:bulk_recent_payloads, [])
    |> assign(:bulk_template_favorites, [])
    |> assign(:bulk_import_block_size, 3)
    |> assign(:bulk_import_block_index, 0)
    |> assign(:ops_tab, "tasks")
    |> assign(:task_filters, default_task_filters())
    |> assign(:finance_filters, default_finance_filters())
    |> assign(:goal_filters, default_goal_filters())
    |> assign(:analytics_filters, default_analytics_filters())
    |> assign(:editing_task_id, nil)
    |> assign(:editing_finance_id, nil)
    |> assign(:editing_goal_id, nil)
    |> load_operation_collections()
    |> refresh_dashboard_insights()
  end

  defp load_operation_collections(socket) do
    {:ok, tasks} = Planning.list_tasks(socket.assigns.current_scope, socket.assigns.task_filters)

    {:ok, finances} =
      Planning.list_finance_entries(socket.assigns.current_scope, socket.assigns.finance_filters)

    {:ok, goals} = Planning.list_goals(socket.assigns.current_scope, socket.assigns.goal_filters)

    socket
    |> stream(:tasks, tasks, reset: true)
    |> stream(:finances, finances, reset: true)
    |> stream(:goals, goals, reset: true)
    |> assign(:action_recommendations, build_action_recommendations(tasks, finances, goals))
    |> assign(:ops_counts, %{
      tasks_total: length(tasks),
      tasks_open: Enum.count(tasks, &(&1.status != :done)),
      finances_total: length(finances),
      goals_total: length(goals),
      goals_active: Enum.count(goals, &(&1.status == :active))
    })
  end

  defp refresh_dashboard_insights(socket) do
    {:ok, workload_capacity_snapshot} =
      Planning.burndown_snapshot(socket.assigns.current_scope, %{
        planned_capacity: socket.assigns.analytics_filters.planned_capacity
      })

    {:ok, insights_overview} =
      Planning.analytics_overview(socket.assigns.current_scope, %{
        days: socket.assigns.analytics_filters.days,
        planned_capacity: socket.assigns.analytics_filters.planned_capacity
      })

    {:ok, finance_summary} = Planning.finance_summary(socket.assigns.current_scope, 30)

    {:ok, finance_entries_for_charts} =
      Planning.list_finance_entries(socket.assigns.current_scope, %{
        days: socket.assigns.finance_filters.days
      })

    socket
    |> assign(:workload_capacity_snapshot, workload_capacity_snapshot)
    |> assign(:insights_overview, insights_overview)
    |> assign(:finance_summary, finance_summary)
    |> assign(:progress_chart_svg, progress_chart_svg(insights_overview))
    |> assign(
      :finance_trend_chart_svg,
      finance_weekly_balance_chart_svg(finance_entries_for_charts)
    )
    |> assign(
      :finance_chart_svg,
      finance_expense_categories_chart_svg(finance_entries_for_charts)
    )
  end

  defp default_task_filters do
    %{status: "all", priority: "all", days: "14"}
  end

  defp default_finance_filters do
    %{days: "30"}
  end

  defp default_goal_filters do
    %{status: "all"}
  end

  defp default_analytics_filters do
    %{days: "30", planned_capacity: "10"}
  end

  defp normalize_task_filters(filters) when is_map(filters) do
    %{
      status: Map.get(filters, "status"),
      priority: Map.get(filters, "priority"),
      days: Map.get(filters, "days")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp normalize_finance_filters(filters) when is_map(filters) do
    %{
      days: Map.get(filters, "days")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp normalize_goal_filters(filters) when is_map(filters) do
    %{
      status: Map.get(filters, "status")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp normalize_analytics_filters(filters) when is_map(filters) do
    %{
      days: Map.get(filters, "days"),
      planned_capacity: Map.get(filters, "planned_capacity")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp sanitize_task_filters(filters) do
    filters
    |> Map.update(:status, "all", fn value ->
      if value in @task_status_filters, do: value, else: "all"
    end)
    |> Map.update(:priority, "all", fn value ->
      if value in @task_priority_filters, do: value, else: "all"
    end)
    |> Map.update(:days, "14", fn value ->
      if value in @task_days_filters, do: value, else: "14"
    end)
  end

  defp sanitize_finance_filters(filters) do
    Map.update(filters, :days, "30", fn value ->
      if value in @finance_days_filters, do: value, else: "30"
    end)
  end

  defp sanitize_goal_filters(filters) do
    Map.update(filters, :status, "all", fn value ->
      if value in @goal_status_filters, do: value, else: "all"
    end)
  end

  defp sanitize_analytics_filters(filters) do
    filters
    |> Map.update(:days, "30", fn value ->
      if value in @analytics_days_filters, do: value, else: "30"
    end)
    |> Map.update(:planned_capacity, "10", fn value ->
      if value in @analytics_capacity_filters, do: value, else: "10"
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide={true}>
      <section class="dashboard-shell">
        <header class="brand-hero-card order-1 rounded-3xl p-6">
          <h1 class="text-2xl font-bold tracking-tight text-base-content">Painel Diário</h1>
          <p class="mt-1 text-sm text-base-content/80">
            Organize tarefas, financeiro e metas sem trocar de tela.
          </p>
          <div class="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <article class="micro-surface rounded-xl p-3">
              <div class="flex items-center justify-between gap-2">
                <p class="text-xs uppercase tracking-wide text-base-content/65">Burndown (14d)</p>
                <.icon name="hero-chart-bar" class="size-4 text-cyan-300/90" />
              </div>
              <p class="mt-1 text-xl font-semibold text-base-content">
                {@workload_capacity_snapshot.completed}/{@workload_capacity_snapshot.total}
              </p>
              <p class="text-xs text-base-content/65">
                {completion_rate(
                  @workload_capacity_snapshot.completed,
                  @workload_capacity_snapshot.total
                )}% concluído
              </p>
              <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-base-content/15">
                <div
                  class="h-full rounded-full bg-cyan-300"
                  style={"width: #{metric_bar_width(completion_rate(@workload_capacity_snapshot.completed, @workload_capacity_snapshot.total))}%;"}
                >
                </div>
              </div>
            </article>

            <article class="micro-surface rounded-xl p-3">
              <div class="flex items-center justify-between gap-2">
                <p class="text-xs uppercase tracking-wide text-base-content/65">Receitas (30d)</p>
                <.icon name="hero-arrow-trending-up" class="size-4 text-emerald-300/90" />
              </div>
              <p class="mt-1 text-xl font-semibold text-emerald-300">
                {format_money(@finance_summary.income_cents)}
              </p>
              <p class="text-xs text-base-content/65">Entradas no período filtrado</p>
            </article>

            <article class="micro-surface rounded-xl p-3">
              <div class="flex items-center justify-between gap-2">
                <p class="text-xs uppercase tracking-wide text-base-content/65">Despesas (30d)</p>
                <.icon name="hero-arrow-trending-down" class="size-4 text-rose-300/90" />
              </div>
              <p class="mt-1 text-xl font-semibold text-rose-300">
                {format_money(@finance_summary.expense_cents)}
              </p>
              <p class="text-xs text-base-content/65">Saídas no período filtrado</p>
            </article>

            <article class="micro-surface rounded-xl p-3">
              <div class="flex items-center justify-between gap-2">
                <p class="text-xs uppercase tracking-wide text-base-content/65">Saldo (30d)</p>
                <span class={[
                  "rounded-md border px-2 py-0.5 text-[0.65rem] font-semibold uppercase tracking-wide",
                  balance_badge_class(@finance_summary.balance_cents)
                ]}>
                  {balance_label(@finance_summary.balance_cents)}
                </span>
              </div>
              <p class={[
                "mt-1 text-xl font-semibold",
                balance_value_class(@finance_summary.balance_cents)
              ]}>
                {format_money(@finance_summary.balance_cents)}
              </p>
              <p class="text-xs text-base-content/65">Resultado consolidado do período</p>
            </article>
          </div>
        </header>

        <section id="action-strip" class="surface-card order-2 rounded-2xl p-4">
          <div class="flex items-center justify-between gap-2">
            <div>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
                Recomendações acionáveis
              </h2>
              <p class="text-xs text-base-content/65">
                Foco no que gera impacto imediato na sua rotina.
              </p>
            </div>
          </div>

          <div class="mt-3 grid gap-2 lg:grid-cols-3">
            <article
              :for={item <- @action_recommendations}
              id={"action-item-#{item.id}"}
              class="micro-surface rounded-xl p-3"
            >
              <div class="flex items-start justify-between gap-2">
                <p class="text-xs uppercase tracking-wide text-base-content/65">{item.category}</p>
                <.icon name={item.icon} class="size-4 text-cyan-300/90" />
              </div>
              <p class="mt-1 text-sm font-semibold text-base-content">{item.title}</p>
              <p class="mt-1 text-xs text-base-content/70">{item.detail}</p>
              <button
                type="button"
                phx-click="set_ops_tab"
                phx-value-tab={item.tab}
                class="btn btn-xs btn-soft mt-2"
              >
                {item.cta}
              </button>
            </article>
          </div>
        </section>

        <nav
          class="surface-card order-3 rounded-2xl p-2 lg:hidden"
          aria-label="Atalhos rápidos do dashboard"
        >
          <div class="flex gap-2 overflow-x-auto pb-1">
            <a href="#quick-bulk" class="btn btn-sm btn-ghost whitespace-nowrap">
              Importação rápida
            </a>
            <a href="#operations-panel" class="btn btn-sm btn-ghost whitespace-nowrap">
              Operação
            </a>
            <a href="#analytics-panel" class="btn btn-sm btn-ghost whitespace-nowrap">Analítico</a>
          </div>
        </nav>

        <section
          id="analytics-panel"
          class="surface-card order-7 rounded-2xl p-4 scroll-mt-20"
        >
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
                Visão analítica
              </h2>
              <p class="text-xs text-base-content/65">
                Compare execução planejada e acompanhe sinais de capacidade e saúde financeira.
              </p>
            </div>
            <div
              id="analytics-filters"
              class="analytics-filter-groups"
              aria-label="Filtros analíticos"
            >
              <div class="analytics-chip-group">
                <p class="analytics-filter-label">Janela de análise</p>
                <div class="analytics-chip-row">
                  <button
                    :for={days <- analytics_day_range_options()}
                    id={"analytics-days-#{days}"}
                    type="button"
                    phx-click="set_analytics_days"
                    phx-value-days={days}
                    class={[
                      "btn btn-xs ds-pill-btn",
                      @analytics_filters.days == days && "btn-primary",
                      @analytics_filters.days != days && "btn-soft"
                    ]}
                  >
                    {analytics_days_label(days)}
                  </button>
                </div>
              </div>

              <div class="analytics-chip-group">
                <p class="analytics-filter-label">Capacidade planejada (tarefas em 14 dias)</p>
                <div class="analytics-chip-row">
                  <button
                    :for={capacity <- analytics_capacity_options()}
                    id={"analytics-capacity-#{capacity}"}
                    type="button"
                    phx-click="set_analytics_capacity"
                    phx-value-planned_capacity={capacity}
                    class={[
                      "btn btn-xs ds-pill-btn",
                      @analytics_filters.planned_capacity == capacity && "btn-primary",
                      @analytics_filters.planned_capacity != capacity && "btn-soft"
                    ]}
                  >
                    {analytics_capacity_chip_label(capacity)}
                  </button>
                </div>
              </div>
            </div>
          </div>

          <div class="analytics-chart-stack mt-4">
            <article class="micro-surface analytics-chart-card rounded-xl p-3">
              <div class="flex items-center justify-between gap-2">
                <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                  Barras comparativas de execução
                </h3>
                <span class="text-[0.65rem] text-base-content/60">
                  executado vs planejado por período
                </span>
              </div>
              <div id="chart-progress" class="contex-plot mt-2 overflow-x-auto">
                {@progress_chart_svg}
              </div>
              <p
                :if={!progress_chart_has_data?(@insights_overview)}
                class="mt-2 text-xs text-base-content/65"
              >
                Sem dados suficientes neste intervalo. Ajuste a janela para visualizar tendências.
              </p>
            </article>

            <div class="analytics-chart-grid">
              <article class="micro-surface analytics-chart-card rounded-xl p-3">
                <div class="flex items-center justify-between gap-2">
                  <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                    Linha de tendência do saldo semanal
                  </h3>
                  <span class="text-[0.65rem] text-base-content/60">
                    evolução da saúde financeira
                  </span>
                </div>
                <div id="chart-finance-trend" class="contex-plot mt-2 overflow-x-auto">
                  {@finance_trend_chart_svg}
                </div>
                <p :if={@ops_counts.finances_total == 0} class="mt-2 text-xs text-base-content/65">
                  Sem lançamentos financeiros no período para montar tendência.
                </p>
              </article>

              <article class="micro-surface analytics-chart-card rounded-xl p-3">
                <div class="flex items-center justify-between gap-2">
                  <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                    Ranking de despesas por categoria
                  </h3>
                  <span class="text-[0.65rem] text-base-content/60">
                    top 5 categorias mais impactantes
                  </span>
                </div>
                <div id="chart-finance" class="contex-plot mt-2 overflow-x-auto">
                  {@finance_chart_svg}
                </div>
                <p :if={@ops_counts.finances_total == 0} class="mt-2 text-xs text-base-content/65">
                  Cadastre despesas para identificar categorias com maior impacto.
                </p>
              </article>
            </div>
          </div>

          <div class="mt-3 grid gap-3 md:grid-cols-2 xl:grid-cols-5">
            <article class="micro-surface rounded-xl p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Semanal</p>
              <p class="mt-1 text-lg font-semibold text-base-content">
                {@insights_overview.progress_by_period.weekly.executed}/{@insights_overview.progress_by_period.weekly.planned}
              </p>
              <p class="text-xs text-base-content/65">
                {format_percent(@insights_overview.progress_by_period.weekly.completion_rate)}% de conclusão
              </p>
              <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-base-content/15">
                <div
                  class="h-full rounded-full bg-cyan-300"
                  style={"width: #{metric_bar_width(@insights_overview.progress_by_period.weekly.completion_rate)}%;"}
                >
                </div>
              </div>
            </article>

            <article class="micro-surface rounded-xl p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Mensal</p>
              <p class="mt-1 text-lg font-semibold text-base-content">
                {@insights_overview.progress_by_period.monthly.executed}/{@insights_overview.progress_by_period.monthly.planned}
              </p>
              <p class="text-xs text-base-content/65">
                {format_percent(@insights_overview.progress_by_period.monthly.completion_rate)}% de conclusão
              </p>
              <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-base-content/15">
                <div
                  class="h-full rounded-full bg-emerald-300"
                  style={"width: #{metric_bar_width(@insights_overview.progress_by_period.monthly.completion_rate)}%;"}
                >
                </div>
              </div>
            </article>

            <article class="micro-surface rounded-xl p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Anual</p>
              <p class="mt-1 text-lg font-semibold text-base-content">
                {@insights_overview.progress_by_period.annual.executed}/{@insights_overview.progress_by_period.annual.planned}
              </p>
              <p class="text-xs text-base-content/65">
                {format_percent(@insights_overview.progress_by_period.annual.completion_rate)}% de conclusão
              </p>
              <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-base-content/15">
                <div
                  class="h-full rounded-full bg-violet-300"
                  style={"width: #{metric_bar_width(@insights_overview.progress_by_period.annual.completion_rate)}%;"}
                >
                </div>
              </div>
            </article>

            <article class="micro-surface rounded-xl p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Capacidade 14d</p>
              <p class={[
                "mt-1 text-lg font-semibold",
                capacity_gap_class(@workload_capacity_snapshot.capacity_gap)
              ]}>
                {@workload_capacity_snapshot.open_14d}/{@workload_capacity_snapshot.planned_capacity_14d}
              </p>
              <p class="text-xs text-base-content/65">
                {capacity_gap_label(@workload_capacity_snapshot.capacity_gap)} • Alerta: {if @workload_capacity_snapshot.overload_alert,
                  do: "ligado",
                  else: "desligado"}
              </p>
            </article>

            <article class="micro-surface rounded-xl p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Risco burnout</p>
              <p class={"mt-1 inline-flex rounded px-2 py-0.5 text-xs font-semibold " <> risk_badge_class(@insights_overview.burnout_risk_assessment.level)}>
                {burnout_level_label(@insights_overview.burnout_risk_assessment.level)} ({@insights_overview.burnout_risk_assessment.score})
              </p>
              <p class="mt-2 text-xs text-base-content/65">
                {if Enum.empty?(@insights_overview.burnout_risk_assessment.signals),
                  do: "Sem sinais críticos no momento.",
                  else: Enum.join(@insights_overview.burnout_risk_assessment.signals, " | ")}
              </p>
            </article>
          </div>
        </section>

        <section class="surface-card order-4 rounded-2xl p-4">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
            Copy/Paste Studio
          </h2>
          <p class="mt-1 text-xs text-base-content/65">
            Fluxo único: cole, pré-visualize, ajuste e importe em lote sem sair do teclado.
          </p>
        </section>

        <section
          id="quick-bulk"
          class="bulk-studio-shell surface-card order-5 rounded-2xl p-4 scroll-mt-20"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
            Importação rápida por texto
          </h2>
          <p class="mt-1 text-sm text-base-content/85">
            Cole uma linha por item usando o padrão tipo: conteúdo.
          </p>

          <div class="bulk-flow-steps mt-3" aria-label="Etapas do fluxo de importação">
            <span class="bulk-flow-chip">
              <strong>1.</strong> Colar texto
            </span>
            <span class="bulk-flow-chip">
              <strong>2.</strong> Pré-visualizar
            </span>
            <span class="bulk-flow-chip">
              <strong>3.</strong> Importar bloco ou tudo
            </span>
          </div>

          <div class="mt-3">
            <p class="bulk-section-title">Templates rápidos</p>
            <div class="mt-2 bulk-template-grid">
              <article
                :for={template <- sorted_bulk_templates(@bulk_template_favorites)}
                id={"bulk-template-card-#{template.key}"}
                class="bulk-template-card"
              >
                <button
                  id={"bulk-template-#{template.key}"}
                  type="button"
                  phx-click="apply_bulk_template"
                  phx-value-template={template.key}
                  class="btn btn-xs bulk-template-type-btn"
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
                    "btn btn-xs bulk-template-fav-btn",
                    template_favorited?(@bulk_template_favorites, template.key) &&
                      "bulk-template-fav-btn-active"
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

          <details class="bulk-examples mt-3">
            <summary>Ver formatos e exemplos</summary>
            <div class="bulk-code-list mt-2">
              <p class="bulk-code-line">
                tarefa: Revisar orçamento | data=2026-04-20 | prioridade=alta
              </p>
              <p class="bulk-code-line">
                financeiro: tipo=despesa | valor=125,90 | categoria=moradia | data=2026-04-05
              </p>
              <p class="bulk-code-line">
                meta: Reserva de emergência | horizonte=medio | alvo=300000
              </p>
            </div>
          </details>

          <div :if={@bulk_recent_payloads != []} id="bulk-history" class="mt-3 space-y-2">
            <p class="bulk-section-title">Histórico recente</p>
            <div class="grid gap-2 sm:grid-cols-2">
              <article
                :for={entry <- @bulk_recent_payloads}
                id={"bulk-history-entry-#{entry.id}"}
                class={[
                  "bulk-history-entry",
                  entry.favorite && "border-cyan-300/40",
                  !entry.favorite && "border-base-content/12"
                ]}
              >
                <p class="bulk-history-preview">{entry.preview_line}</p>
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
            <div class="bulk-control-strip mb-3 flex items-center justify-between gap-3 rounded-lg px-3 py-2">
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
              phx-hook="BulkCaptureEditor"
              data-preview-selector="#bulk-preview-btn"
              data-import-selector="#bulk-import-btn"
              data-fix-all-selector="#bulk-fix-all-btn"
              required
            />
            <div
              id="bulk-shortcuts-help"
              class="bulk-shortcuts-help mt-2 rounded-lg px-3 py-2"
            >
              <span class="bulk-shortcut-chip">Tab: completar tipo</span>
              <span class="bulk-shortcut-chip">Ctrl/Cmd+Enter: preview</span>
              <span class="bulk-shortcut-chip">Ctrl/Cmd+Shift+F: corrigir tudo</span>
              <span class="bulk-shortcut-chip">Ctrl/Cmd+Shift+I: importar</span>
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

          <div :if={@bulk_preview} id="bulk-capture-preview" class="bulk-preview-shell mt-4 space-y-3">
            <% current_block =
              current_bulk_import_block(
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
              <article class="bulk-kpi micro-surface rounded-lg p-3">
                <p class="text-xs uppercase tracking-wide text-base-content/65">Linhas</p>
                <p class="mt-1 text-lg font-semibold text-base-content">
                  {@bulk_preview.lines_total}
                </p>
              </article>
              <article class="bulk-kpi micro-surface rounded-lg p-3">
                <p class="text-xs uppercase tracking-wide text-base-content/65">Válidas</p>
                <p class="mt-1 text-lg font-semibold text-emerald-300">
                  {@bulk_preview.valid_total}
                </p>
              </article>
              <article class="bulk-kpi micro-surface rounded-lg p-3">
                <p class="text-xs uppercase tracking-wide text-base-content/65">Com erro</p>
                <p class="mt-1 text-lg font-semibold text-amber-200">
                  {@bulk_preview.invalid_total}
                </p>
              </article>
              <article class="bulk-kpi micro-surface rounded-lg p-3">
                <p class="text-xs uppercase tracking-wide text-base-content/65">Ignoradas</p>
                <p class="mt-1 text-lg font-semibold text-base-content">
                  {@bulk_preview.ignored_total}
                </p>
              </article>
            </div>

            <div class="max-h-72 space-y-2 overflow-y-auto rounded-xl border border-base-content/12 bg-base-100/40 p-3">
              <article
                :for={entry <- @bulk_preview.entries}
                id={"bulk-preview-line-#{entry.line_number}"}
                class="bulk-entry-card rounded-lg border border-base-content/12 bg-base-100/45 p-2"
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
                <p class="bulk-code-line mt-1">{entry.raw}</p>
                <p class="mt-1 text-sm font-medium text-base-content/95">
                  {bulk_preview_entry_label(entry)}
                </p>

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
            <div class="grid gap-2 sm:grid-cols-3">
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
              <article class="micro-surface rounded-lg p-3">
                <p class="text-xs uppercase tracking-wide text-base-content/65">Metas criadas</p>
                <p class="mt-1 text-lg font-semibold text-base-content">
                  {@bulk_result.created.goals}
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
              class="rounded-xl border border-amber-300/30 bg-amber-500/10 p-3"
            >
              <p class="text-xs font-semibold uppercase tracking-wide text-amber-100">
                Linhas com erro
              </p>
              <ul class="mt-2 space-y-1 text-xs text-amber-100/85">
                <li :for={error <- @bulk_result.errors}>{error}</li>
              </ul>
            </div>
          </div>
        </section>

        <section id="operations-panel" class="surface-card order-6 rounded-2xl p-4 scroll-mt-20">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
                Operação diária
              </h2>
              <p class="text-xs text-base-content/65">
                Foque no próximo passo: priorize tarefas, ajuste finanças e avance metas.
              </p>
            </div>
            <div class="flex flex-wrap gap-2" aria-label="Abas operacionais">
              <button
                id="ops-tab-tasks"
                type="button"
                phx-click="set_ops_tab"
                phx-value-tab="tasks"
                class={[
                  "btn btn-sm ds-pill-btn",
                  @ops_tab == "tasks" && "btn-primary",
                  @ops_tab != "tasks" && "btn-soft"
                ]}
              >
                Tarefas
              </button>
              <button
                id="ops-tab-finances"
                type="button"
                phx-click="set_ops_tab"
                phx-value-tab="finances"
                class={[
                  "btn btn-sm ds-pill-btn",
                  @ops_tab == "finances" && "btn-primary",
                  @ops_tab != "finances" && "btn-soft"
                ]}
              >
                Financeiro
              </button>
              <button
                id="ops-tab-goals"
                type="button"
                phx-click="set_ops_tab"
                phx-value-tab="goals"
                class={[
                  "btn btn-sm ds-pill-btn",
                  @ops_tab == "goals" && "btn-primary",
                  @ops_tab != "goals" && "btn-soft"
                ]}
              >
                Metas
              </button>
            </div>
          </div>

          <div class="mt-3 grid gap-2 md:grid-cols-4">
            <article class="micro-surface rounded-lg p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Tarefas abertas</p>
              <p class="mt-1 text-lg font-semibold text-base-content">
                {@ops_counts.tasks_open}
              </p>
            </article>
            <article class="micro-surface rounded-lg p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Tarefas no filtro</p>
              <p class="mt-1 text-lg font-semibold text-base-content">
                {@ops_counts.tasks_total}
              </p>
            </article>
            <article class="micro-surface rounded-lg p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">
                Lançamentos no filtro
              </p>
              <p class="mt-1 text-lg font-semibold text-base-content">
                {@ops_counts.finances_total}
              </p>
            </article>
            <article class="micro-surface rounded-lg p-3">
              <p class="text-xs uppercase tracking-wide text-base-content/65">Metas ativas</p>
              <p class="mt-1 text-lg font-semibold text-base-content">
                {@ops_counts.goals_active}/{@ops_counts.goals_total}
              </p>
            </article>
          </div>

          <div class="mt-3 space-y-4">
            <section class={[
              "rounded-xl border border-base-content/12 bg-base-100/35 p-4",
              @ops_tab != "tasks" && "hidden"
            ]}>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
                Próximas tarefas
              </h2>
              <form
                id="task-filters"
                phx-change="filter_tasks"
                class="mt-3 grid gap-2 sm:grid-cols-3"
                aria-label="Filtros de tarefas"
              >
                <select name="filters[status]" class="select select-bordered select-sm">
                  <option value="all" selected={@task_filters.status == "all"}>Todos status</option>
                  <option value="todo" selected={@task_filters.status == "todo"}>Todo</option>
                  <option value="in_progress" selected={@task_filters.status == "in_progress"}>
                    Em andamento
                  </option>
                  <option value="done" selected={@task_filters.status == "done"}>Concluída</option>
                </select>
                <select name="filters[priority]" class="select select-bordered select-sm">
                  <option value="all" selected={@task_filters.priority == "all"}>
                    Todas prioridades
                  </option>
                  <option value="low" selected={@task_filters.priority == "low"}>Baixa</option>
                  <option value="medium" selected={@task_filters.priority == "medium"}>Média</option>
                  <option value="high" selected={@task_filters.priority == "high"}>Alta</option>
                </select>
                <select name="filters[days]" class="select select-bordered select-sm">
                  <option value="7" selected={@task_filters.days == "7"}>7 dias</option>
                  <option value="14" selected={@task_filters.days == "14"}>14 dias</option>
                  <option value="30" selected={@task_filters.days == "30"}>30 dias</option>
                </select>
              </form>
              <div id="tasks" phx-update="stream" class="mt-3 space-y-2">
                <div
                  id="tasks-empty"
                  class="ds-empty-state hidden only:block rounded-lg p-4 text-sm"
                >
                  Nenhuma tarefa cadastrada.
                </div>
                <article
                  :for={{id, task} <- @streams.tasks}
                  id={id}
                  class="micro-surface rounded-lg p-3"
                >
                  <p class="font-medium text-base-content">{task.title}</p>
                  <p class="text-xs text-base-content/65">
                    {to_string(task.priority)} • {if task.due_on,
                      do: Date.to_iso8601(task.due_on),
                      else: "sem data"}
                  </p>
                  <div class="mt-2 flex gap-2">
                    <button
                      id={"task-edit-btn-#{task.id}"}
                      type="button"
                      phx-click="start_edit_task"
                      phx-value-id={task.id}
                      class="ds-inline-btn rounded-md px-2 py-1 text-xs"
                    >
                      Editar
                    </button>
                    <button
                      id={"task-delete-btn-#{task.id}"}
                      type="button"
                      phx-click="delete_task"
                      phx-value-id={task.id}
                      class="ds-inline-btn ds-inline-btn-danger rounded-md px-2 py-1 text-xs"
                    >
                      Excluir
                    </button>
                  </div>

                  <form
                    :if={editing?(@editing_task_id, task.id)}
                    id={"task-edit-form-#{task.id}"}
                    phx-submit="save_task"
                    class="ds-edit-form mt-3 space-y-2 rounded-md p-3"
                  >
                    <input type="hidden" name="_id" value={task.id} />
                    <label
                      class="text-xs font-medium text-base-content/70"
                      for={"task-title-#{task.id}"}
                    >
                      Título
                    </label>
                    <input
                      id={"task-title-#{task.id}"}
                      name="task[title]"
                      type="text"
                      value={task.title}
                      required
                      class="input input-bordered w-full"
                    />
                    <label
                      class="text-xs font-medium text-base-content/70"
                      for={"task-due-#{task.id}"}
                    >
                      Data
                    </label>
                    <input
                      id={"task-due-#{task.id}"}
                      name="task[due_on]"
                      type="date"
                      value={date_input_value(task.due_on)}
                      class="input input-bordered w-full"
                    />
                    <div class="grid gap-2 sm:grid-cols-2">
                      <div>
                        <label
                          class="text-xs font-medium text-base-content/70"
                          for={"task-priority-#{task.id}"}
                        >
                          Prioridade
                        </label>
                        <select
                          id={"task-priority-#{task.id}"}
                          name="task[priority]"
                          class="select select-bordered w-full"
                        >
                          <option value="low" selected={task.priority == :low}>Baixa</option>
                          <option value="medium" selected={task.priority == :medium}>Média</option>
                          <option value="high" selected={task.priority == :high}>Alta</option>
                        </select>
                      </div>
                      <div>
                        <label
                          class="text-xs font-medium text-base-content/70"
                          for={"task-status-#{task.id}"}
                        >
                          Status
                        </label>
                        <select
                          id={"task-status-#{task.id}"}
                          name="task[status]"
                          class="select select-bordered w-full"
                        >
                          <option value="todo" selected={task.status == :todo}>Todo</option>
                          <option value="in_progress" selected={task.status == :in_progress}>
                            Em andamento
                          </option>
                          <option value="done" selected={task.status == :done}>Concluída</option>
                        </select>
                      </div>
                    </div>
                    <div class="flex gap-2">
                      <button type="submit" class="btn btn-primary btn-sm">Salvar</button>
                      <button
                        type="button"
                        class="btn btn-ghost btn-sm"
                        phx-click="cancel_edit_task"
                      >
                        Cancelar
                      </button>
                    </div>
                  </form>
                </article>
              </div>
            </section>

            <section class={[
              "rounded-xl border border-base-content/12 bg-base-100/35 p-4",
              @ops_tab != "finances" && "hidden"
            ]}>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
                Lançamentos recentes
              </h2>
              <form
                id="finance-filters"
                phx-change="filter_finances"
                class="mt-3"
                aria-label="Filtros de lançamentos"
              >
                <select name="filters[days]" class="select select-bordered select-sm w-full">
                  <option value="7" selected={@finance_filters.days == "7"}>Últimos 7 dias</option>
                  <option value="30" selected={@finance_filters.days == "30"}>Últimos 30 dias</option>
                  <option value="90" selected={@finance_filters.days == "90"}>Últimos 90 dias</option>
                </select>
              </form>
              <div id="finances" phx-update="stream" class="mt-3 space-y-2">
                <div
                  id="finances-empty"
                  class="ds-empty-state hidden only:block rounded-lg p-4 text-sm"
                >
                  Nenhum lançamento cadastrado.
                </div>
                <article
                  :for={{id, entry} <- @streams.finances}
                  id={id}
                  class="micro-surface rounded-lg p-3"
                >
                  <p class="font-medium text-base-content">{entry.category}</p>
                  <p class="text-xs text-base-content/65">
                    {to_string(entry.kind)} • {format_money(entry.amount_cents)} • {Date.to_iso8601(
                      entry.occurred_on
                    )}
                  </p>
                  <div class="mt-2 flex gap-2">
                    <button
                      id={"finance-edit-btn-#{entry.id}"}
                      type="button"
                      phx-click="start_edit_finance"
                      phx-value-id={entry.id}
                      class="ds-inline-btn rounded-md px-2 py-1 text-xs"
                    >
                      Editar
                    </button>
                    <button
                      id={"finance-delete-btn-#{entry.id}"}
                      type="button"
                      phx-click="delete_finance"
                      phx-value-id={entry.id}
                      class="ds-inline-btn ds-inline-btn-danger rounded-md px-2 py-1 text-xs"
                    >
                      Excluir
                    </button>
                  </div>

                  <form
                    :if={editing?(@editing_finance_id, entry.id)}
                    id={"finance-edit-form-#{entry.id}"}
                    phx-submit="save_finance"
                    class="ds-edit-form mt-3 space-y-2 rounded-md p-3"
                  >
                    <input type="hidden" name="_id" value={entry.id} />
                    <div class="grid gap-2 sm:grid-cols-2">
                      <div>
                        <label
                          class="text-xs font-medium text-base-content/70"
                          for={"finance-kind-#{entry.id}"}
                        >
                          Tipo
                        </label>
                        <select
                          id={"finance-kind-#{entry.id}"}
                          name="finance[kind]"
                          class="select select-bordered w-full"
                        >
                          <option value="income" selected={entry.kind == :income}>Receita</option>
                          <option value="expense" selected={entry.kind == :expense}>Despesa</option>
                        </select>
                      </div>
                      <div>
                        <label
                          class="text-xs font-medium text-base-content/70"
                          for={"finance-amount-#{entry.id}"}
                        >
                          Valor
                        </label>
                        <input
                          id={"finance-amount-#{entry.id}"}
                          name="finance[amount_cents]"
                          type="number"
                          required
                          value={entry.amount_cents}
                          class="input input-bordered w-full"
                        />
                      </div>
                    </div>
                    <label
                      class="text-xs font-medium text-base-content/70"
                      for={"finance-category-#{entry.id}"}
                    >
                      Categoria
                    </label>
                    <input
                      id={"finance-category-#{entry.id}"}
                      name="finance[category]"
                      type="text"
                      required
                      value={entry.category}
                      class="input input-bordered w-full"
                    />
                    <label
                      class="text-xs font-medium text-base-content/70"
                      for={"finance-date-#{entry.id}"}
                    >
                      Data
                    </label>
                    <input
                      id={"finance-date-#{entry.id}"}
                      name="finance[occurred_on]"
                      type="date"
                      value={date_input_value(entry.occurred_on)}
                      class="input input-bordered w-full"
                    />
                    <label
                      class="text-xs font-medium text-base-content/70"
                      for={"finance-description-#{entry.id}"}
                    >
                      Descrição
                    </label>
                    <input
                      id={"finance-description-#{entry.id}"}
                      name="finance[description]"
                      type="text"
                      value={entry.description || ""}
                      class="input input-bordered w-full"
                    />
                    <div class="flex gap-2">
                      <button type="submit" class="btn btn-primary btn-sm">Salvar</button>
                      <button
                        type="button"
                        class="btn btn-ghost btn-sm"
                        phx-click="cancel_edit_finance"
                      >
                        Cancelar
                      </button>
                    </div>
                  </form>
                </article>
              </div>
            </section>

            <section class={[
              "rounded-xl border border-base-content/12 bg-base-100/35 p-4",
              @ops_tab != "goals" && "hidden"
            ]}>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
                Metas em andamento
              </h2>
              <form
                id="goal-filters"
                phx-change="filter_goals"
                class="mt-3"
                aria-label="Filtros de metas"
              >
                <select name="filters[status]" class="select select-bordered select-sm w-full">
                  <option value="all" selected={@goal_filters.status == "all"}>Todos status</option>
                  <option value="active" selected={@goal_filters.status == "active"}>Ativa</option>
                  <option value="paused" selected={@goal_filters.status == "paused"}>Pausada</option>
                  <option value="done" selected={@goal_filters.status == "done"}>Concluída</option>
                </select>
              </form>
              <div id="goals" phx-update="stream" class="mt-3 space-y-2">
                <div
                  id="goals-empty"
                  class="ds-empty-state hidden only:block rounded-lg p-4 text-sm"
                >
                  Nenhuma meta cadastrada.
                </div>
                <article
                  :for={{id, goal} <- @streams.goals}
                  id={id}
                  class="micro-surface rounded-lg p-3"
                >
                  <p class="font-medium text-base-content">{goal.title}</p>
                  <p class="text-xs text-base-content/65">
                    {to_string(goal.horizon)} • {to_string(goal.status)}
                  </p>
                  <div class="mt-2 flex gap-2">
                    <button
                      id={"goal-edit-btn-#{goal.id}"}
                      type="button"
                      phx-click="start_edit_goal"
                      phx-value-id={goal.id}
                      class="ds-inline-btn rounded-md px-2 py-1 text-xs"
                    >
                      Editar
                    </button>
                    <button
                      id={"goal-delete-btn-#{goal.id}"}
                      type="button"
                      phx-click="delete_goal"
                      phx-value-id={goal.id}
                      class="ds-inline-btn ds-inline-btn-danger rounded-md px-2 py-1 text-xs"
                    >
                      Excluir
                    </button>
                  </div>

                  <form
                    :if={editing?(@editing_goal_id, goal.id)}
                    id={"goal-edit-form-#{goal.id}"}
                    phx-submit="save_goal"
                    class="ds-edit-form mt-3 space-y-2 rounded-md p-3"
                  >
                    <input type="hidden" name="_id" value={goal.id} />
                    <label
                      class="text-xs font-medium text-base-content/70"
                      for={"goal-title-#{goal.id}"}
                    >
                      Título
                    </label>
                    <input
                      id={"goal-title-#{goal.id}"}
                      name="goal[title]"
                      type="text"
                      required
                      value={goal.title}
                      class="input input-bordered w-full"
                    />
                    <div class="grid gap-2 sm:grid-cols-2">
                      <div>
                        <label
                          class="text-xs font-medium text-base-content/70"
                          for={"goal-horizon-#{goal.id}"}
                        >
                          Horizonte
                        </label>
                        <select
                          id={"goal-horizon-#{goal.id}"}
                          name="goal[horizon]"
                          class="select select-bordered w-full"
                        >
                          <option value="short" selected={goal.horizon == :short}>Curto</option>
                          <option value="medium" selected={goal.horizon == :medium}>Médio</option>
                          <option value="long" selected={goal.horizon == :long}>Longo</option>
                        </select>
                      </div>
                      <div>
                        <label
                          class="text-xs font-medium text-base-content/70"
                          for={"goal-status-#{goal.id}"}
                        >
                          Status
                        </label>
                        <select
                          id={"goal-status-#{goal.id}"}
                          name="goal[status]"
                          class="select select-bordered w-full"
                        >
                          <option value="active" selected={goal.status == :active}>Ativa</option>
                          <option value="paused" selected={goal.status == :paused}>Pausada</option>
                          <option value="done" selected={goal.status == :done}>Concluída</option>
                        </select>
                      </div>
                    </div>
                    <div class="grid gap-2 sm:grid-cols-2">
                      <div>
                        <label
                          class="text-xs font-medium text-base-content/70"
                          for={"goal-target-#{goal.id}"}
                        >
                          Alvo
                        </label>
                        <input
                          id={"goal-target-#{goal.id}"}
                          name="goal[target_value]"
                          type="number"
                          value={goal.target_value || ""}
                          class="input input-bordered w-full"
                        />
                      </div>
                      <div>
                        <label
                          class="text-xs font-medium text-base-content/70"
                          for={"goal-current-#{goal.id}"}
                        >
                          Atual
                        </label>
                        <input
                          id={"goal-current-#{goal.id}"}
                          name="goal[current_value]"
                          type="number"
                          value={goal.current_value || 0}
                          class="input input-bordered w-full"
                        />
                      </div>
                    </div>
                    <label
                      class="text-xs font-medium text-base-content/70"
                      for={"goal-date-#{goal.id}"}
                    >
                      Data
                    </label>
                    <input
                      id={"goal-date-#{goal.id}"}
                      name="goal[due_on]"
                      type="date"
                      value={date_input_value(goal.due_on)}
                      class="input input-bordered w-full"
                    />
                    <label
                      class="text-xs font-medium text-base-content/70"
                      for={"goal-notes-#{goal.id}"}
                    >
                      Notas
                    </label>
                    <input
                      id={"goal-notes-#{goal.id}"}
                      name="goal[notes]"
                      type="text"
                      value={goal.notes || ""}
                      class="input input-bordered w-full"
                    />
                    <div class="flex gap-2">
                      <button type="submit" class="btn btn-primary btn-sm">Salvar</button>
                      <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit_goal">
                        Cancelar
                      </button>
                    </div>
                  </form>
                </article>
              </div>
            </section>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end

  defp format_money(cents) when is_integer(cents) do
    value = cents / 100
    :erlang.float_to_binary(value, decimals: 2)
  end

  defp progress_chart_svg(insights_overview) do
    progress = insights_overview.progress_by_period

    data = [
      {"Semanal", progress.weekly.executed, progress.weekly.planned},
      {"Mensal", progress.monthly.executed, progress.monthly.planned},
      {"Anual", progress.annual.executed, progress.annual.planned}
    ]

    dataset = Dataset.new(data, ["periodo", "executado", "planejado"])

    Plot.new(dataset, Contex.BarChart, 640, 260,
      mapping: %{category_col: "periodo", value_cols: ["executado", "planejado"]},
      type: :grouped,
      data_labels: false,
      title: "Progresso"
    )
    |> Plot.plot_options(%{legend_setting: :legend_bottom})
    |> Plot.to_svg()
  end

  defp finance_weekly_balance_chart_svg(finance_entries) when is_list(finance_entries) do
    week_starts = rolling_week_starts(8)

    week_label_lookup =
      week_starts
      |> Enum.with_index(1)
      |> Map.new(fn {week_start, index} -> {index, short_date_label(week_start)} end)

    data =
      Enum.with_index(week_starts, 1)
      |> Enum.map(fn {week_start, index} ->
        week_end = Date.add(week_start, 6)

        net_cents =
          finance_entries
          |> Enum.filter(fn entry ->
            Date.compare(entry.occurred_on, week_start) in [:gt, :eq] and
              Date.compare(entry.occurred_on, week_end) in [:lt, :eq]
          end)
          |> Enum.reduce(0, fn entry, acc ->
            if entry.kind == :income,
              do: acc + entry.amount_cents,
              else: acc - entry.amount_cents
          end)

        {index, net_cents}
      end)

    dataset = Dataset.new(data, ["week_index", "saldo"])

    Plot.new(dataset, Contex.LinePlot, 520, 260,
      mapping: %{x_col: "week_index", y_cols: ["saldo"]},
      smoothed: false,
      custom_x_formatter: fn value ->
        week_label_for_axis(value, week_label_lookup)
      end,
      custom_y_formatter: &money_axis_formatter/1,
      title: "Saldo líquido por semana"
    )
    |> Plot.to_svg()
  end

  defp finance_weekly_balance_chart_svg(_), do: finance_weekly_balance_chart_svg([])

  defp finance_expense_categories_chart_svg(finance_entries) when is_list(finance_entries) do
    data =
      finance_entries
      |> Enum.filter(&(&1.kind == :expense))
      |> Enum.group_by(&normalize_finance_category(&1.category))
      |> Enum.map(fn {category, entries} ->
        {category, Enum.reduce(entries, 0, fn entry, acc -> acc + entry.amount_cents end)}
      end)
      |> Enum.sort_by(fn {_category, total} -> -total end)
      |> Enum.take(5)

    data =
      if data == [] do
        [{"Sem despesas", 0}]
      else
        data
      end

    dataset = Dataset.new(data, ["categoria", "valor"])

    Plot.new(dataset, Contex.BarChart, 520, 260,
      mapping: %{category_col: "categoria", value_cols: ["valor"]},
      orientation: :horizontal,
      data_labels: false,
      title: "Top despesas por categoria",
      custom_value_formatter: &money_axis_formatter/1
    )
    |> Plot.to_svg()
  end

  defp finance_expense_categories_chart_svg(_), do: finance_expense_categories_chart_svg([])

  defp progress_chart_has_data?(insights_overview) do
    progress = insights_overview.progress_by_period

    progress.weekly.executed + progress.weekly.planned +
      progress.monthly.executed + progress.monthly.planned +
      progress.annual.executed + progress.annual.planned > 0
  end

  defp analytics_days_label("365"), do: "365d"
  defp analytics_days_label(days), do: days <> "d"

  defp analytics_capacity_chip_label(capacity), do: capacity <> " tarefas"

  defp analytics_day_range_options, do: @analytics_days_filters
  defp analytics_capacity_options, do: @analytics_capacity_filters

  defp build_action_recommendations(tasks, finances, goals) do
    [
      task_action_recommendation(tasks),
      finance_action_recommendation(finances),
      goal_action_recommendation(goals)
    ]
  end

  defp task_action_recommendation(tasks) when is_list(tasks) do
    today = Date.utc_today()

    overdue =
      Enum.filter(tasks, fn task ->
        task.status != :done and match?(%Date{}, task.due_on) and
          Date.compare(task.due_on, today) == :lt
      end)

    high_overdue = Enum.filter(overdue, &(&1.priority == :high))

    cond do
      high_overdue != [] ->
        next = Enum.min_by(high_overdue, & &1.due_on)

        %{
          id: "tasks",
          category: "Tarefas",
          icon: "hero-exclamation-triangle",
          title: "Priorize tarefas críticas atrasadas",
          detail:
            "#{length(high_overdue)} alta prioridade em atraso. Próxima: #{next.title} (#{short_date_label(next.due_on)}).",
          cta: "Abrir tarefas",
          tab: "tasks"
        }

      overdue != [] ->
        next = Enum.min_by(overdue, & &1.due_on)

        %{
          id: "tasks",
          category: "Tarefas",
          icon: "hero-clipboard-document-list",
          title: "Reduza tarefas em atraso",
          detail: "#{length(overdue)} tarefas atrasadas. Próxima: #{next.title}.",
          cta: "Abrir tarefas",
          tab: "tasks"
        }

      true ->
        open_tasks = Enum.count(tasks, &(&1.status != :done))

        %{
          id: "tasks",
          category: "Tarefas",
          icon: "hero-check-badge",
          title: "Planeje o próximo ciclo",
          detail: "Sem atrasos na janela atual. #{open_tasks} tarefas abertas para priorizar.",
          cta: "Abrir tarefas",
          tab: "tasks"
        }
    end
  end

  defp task_action_recommendation(_tasks), do: task_action_recommendation([])

  defp finance_action_recommendation(finances) when is_list(finances) do
    biggest_expense =
      finances
      |> Enum.filter(&(&1.kind == :expense))
      |> Enum.max_by(& &1.amount_cents, fn -> nil end)

    if biggest_expense do
      %{
        id: "finances",
        category: "Financeiro",
        icon: "hero-banknotes",
        title: "Revise a maior despesa da janela",
        detail:
          "#{normalize_finance_category(biggest_expense.category)}: #{money_label(biggest_expense.amount_cents)} em #{short_date_label(biggest_expense.occurred_on)}.",
        cta: "Abrir financeiro",
        tab: "finances"
      }
    else
      %{
        id: "finances",
        category: "Financeiro",
        icon: "hero-arrow-trending-up",
        title: "Registre movimentações essenciais",
        detail:
          "Sem despesas na janela atual. Registre entradas e saídas para análises mais úteis.",
        cta: "Abrir financeiro",
        tab: "finances"
      }
    end
  end

  defp finance_action_recommendation(_finances), do: finance_action_recommendation([])

  defp goal_action_recommendation(goals) when is_list(goals) do
    today = Date.utc_today()

    overdue_active =
      goals
      |> Enum.filter(fn goal ->
        goal.status in [:active, :paused] and match?(%Date{}, goal.due_on) and
          Date.compare(goal.due_on, today) == :lt
      end)

    cond do
      overdue_active != [] ->
        goal = Enum.min_by(overdue_active, & &1.due_on)

        %{
          id: "goals",
          category: "Metas",
          icon: "hero-flag",
          title: "Meta com maior atraso",
          detail: "#{goal.title} está atrasada desde #{short_date_label(goal.due_on)}.",
          cta: "Abrir metas",
          tab: "goals"
        }

      true ->
        lowest_progress =
          goals
          |> Enum.filter(&(&1.status in [:active, :paused]))
          |> Enum.filter(fn goal -> is_integer(goal.target_value) and goal.target_value > 0 end)
          |> Enum.min_by(
            fn goal -> goal_progress(goal.current_value, goal.target_value) end,
            fn -> nil end
          )

        if lowest_progress do
          progress =
            Float.round(
              goal_progress(lowest_progress.current_value, lowest_progress.target_value) * 100,
              1
            )

          %{
            id: "goals",
            category: "Metas",
            icon: "hero-chart-pie",
            title: "Meta com menor avanço",
            detail: "#{lowest_progress.title} está em #{progress}% do alvo definido.",
            cta: "Abrir metas",
            tab: "goals"
          }
        else
          %{
            id: "goals",
            category: "Metas",
            icon: "hero-sparkles",
            title: "Defina um alvo de crescimento",
            detail:
              "Sem metas ativas com progresso. Configure alvo e valor atual para acompanhar evolução.",
            cta: "Abrir metas",
            tab: "goals"
          }
        end
    end
  end

  defp goal_action_recommendation(_goals), do: goal_action_recommendation([])

  defp goal_progress(current, target)
       when is_integer(current) and is_integer(target) and target > 0 do
    current
    |> max(0)
    |> Kernel./(target)
    |> min(1.0)
  end

  defp goal_progress(_current, _target), do: 0.0

  defp money_label(cents) when is_integer(cents), do: "R$ " <> format_money(cents)
  defp money_label(_cents), do: "R$ 0.00"

  defp rolling_week_starts(weeks) when is_integer(weeks) and weeks > 0 do
    today = Date.utc_today()
    week_start = Date.add(today, 1 - Date.day_of_week(today))
    oldest_start = Date.add(week_start, -7 * (weeks - 1))

    Enum.map(0..(weeks - 1), fn index ->
      Date.add(oldest_start, index * 7)
    end)
  end

  defp short_date_label(%Date{} = date) do
    day = date.day |> Integer.to_string() |> String.pad_leading(2, "0")
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{day}/#{month}"
  end

  defp week_label_for_axis(value, lookup) when is_number(value) and is_map(lookup) do
    rounded = round(value)

    if abs(value - rounded) < 0.001 do
      Map.get(lookup, rounded, "")
    else
      ""
    end
  end

  defp week_label_for_axis(_value, _lookup), do: ""

  defp normalize_finance_category(nil), do: "Sem categoria"

  defp normalize_finance_category(category) when is_binary(category) do
    category = String.trim(category)
    if category == "", do: "Sem categoria", else: category
  end

  defp normalize_finance_category(category), do: to_string(category)

  defp money_axis_formatter(value) when is_number(value) do
    "R$ " <> :erlang.float_to_binary(value / 100, decimals: 0)
  end

  defp completion_rate(completed, total)
       when is_integer(completed) and is_integer(total) and total > 0 do
    Float.round(completed * 100 / total, 1)
  end

  defp completion_rate(_completed, _total), do: 0.0

  defp metric_bar_width(value) when is_number(value) do
    value
    |> max(0.0)
    |> min(100.0)
    |> Float.round(1)
  end

  defp metric_bar_width(_value), do: 0.0

  defp date_input_value(nil), do: ""
  defp date_input_value(%Date{} = date), do: Date.to_iso8601(date)

  defp editing?(editing_id, id) do
    to_string(editing_id) == to_string(id)
  end

  defp format_percent(value) when is_number(value), do: Float.round(value * 1.0, 1)
  defp format_percent(_value), do: 0.0

  defp balance_value_class(cents) when is_integer(cents) and cents < 0, do: "text-rose-300"
  defp balance_value_class(cents) when is_integer(cents) and cents > 0, do: "text-emerald-300"
  defp balance_value_class(_cents), do: "text-cyan-300"

  defp balance_badge_class(cents) when is_integer(cents) and cents < 0,
    do: "border-rose-300/35 bg-rose-500/12 text-rose-200"

  defp balance_badge_class(cents) when is_integer(cents) and cents > 0,
    do: "border-emerald-300/35 bg-emerald-500/12 text-emerald-200"

  defp balance_badge_class(_cents), do: "border-cyan-300/35 bg-cyan-500/12 text-cyan-200"

  defp balance_label(cents) when is_integer(cents) and cents < 0, do: "negativo"
  defp balance_label(cents) when is_integer(cents) and cents > 0, do: "positivo"
  defp balance_label(_cents), do: "neutro"

  defp capacity_gap_class(gap) when is_integer(gap) and gap > 0, do: "text-rose-300"
  defp capacity_gap_class(gap) when is_integer(gap) and gap < 0, do: "text-emerald-300"
  defp capacity_gap_class(_gap), do: "text-base-content"

  defp capacity_gap_label(gap) when is_integer(gap) and gap > 0,
    do: "Acima da capacidade em #{gap}"

  defp capacity_gap_label(gap) when is_integer(gap) and gap < 0,
    do: "Folga de #{abs(gap)}"

  defp capacity_gap_label(_gap), do: "Capacidade equilibrada"

  defp burnout_level_label(:high), do: "Alto"
  defp burnout_level_label(:medium), do: "Médio"
  defp burnout_level_label(_), do: "Baixo"

  defp risk_badge_class(:high), do: "border border-rose-300/30 bg-rose-500/15 text-rose-100"
  defp risk_badge_class(:medium), do: "border border-amber-300/30 bg-amber-500/15 text-amber-100"
  defp risk_badge_class(_), do: "border border-emerald-300/30 bg-emerald-500/15 text-emerald-100"

  defp preview_bulk_payload(payload) do
    entries =
      payload
      |> to_string()
      |> String.split(~r/\R/u, trim: false)
      |> Enum.with_index(1)
      |> Enum.map(fn {line, line_number} ->
        build_bulk_preview_entry(line, line_number)
      end)

    %{
      entries: entries,
      lines_total: length(entries),
      valid_total: Enum.count(entries, &(&1.status == :valid)),
      invalid_total: Enum.count(entries, &(&1.status == :invalid)),
      ignored_total: Enum.count(entries, &(&1.status == :ignored))
    }
  end

  defp import_bulk_payload(_payload, scope, preview) do
    import_preview_entries(scope, preview.entries, preview)
  end

  defp import_preview_entries(scope, entries, source_preview) do
    base = %{
      created: %{tasks: 0, finances: 0, goals: 0},
      errors:
        entries
        |> Enum.filter(&(&1.status == :invalid))
        |> Enum.map(fn entry -> "Linha #{entry.line_number}: #{entry.error}" end),
      preview: source_preview,
      last_bulk_import: nil
    }

    {result, imported_ids} =
      Enum.reduce(entries, {base, %{tasks: [], finances: [], goals: []}}, fn entry, {acc, ids} ->
        case entry do
          %{status: :valid, type: :task, attrs: attrs, line_number: line_number} ->
            case Planning.create_task(scope, attrs) do
              {:ok, task} ->
                {
                  increment_bulk_count(acc, :tasks),
                  Map.update!(ids, :tasks, fn values -> [task.id | values] end)
                }

              {:error, {:validation, details}} ->
                {add_bulk_error(acc, line_number, format_validation_errors(details)), ids}

              {:error, reason} ->
                {add_bulk_error(acc, line_number, inspect(reason)), ids}
            end

          %{status: :valid, type: :finance, attrs: attrs, line_number: line_number} ->
            case Planning.create_finance_entry(scope, attrs) do
              {:ok, finance} ->
                {
                  increment_bulk_count(acc, :finances),
                  Map.update!(ids, :finances, fn values -> [finance.id | values] end)
                }

              {:error, {:validation, details}} ->
                {add_bulk_error(acc, line_number, format_validation_errors(details)), ids}

              {:error, reason} ->
                {add_bulk_error(acc, line_number, inspect(reason)), ids}
            end

          %{status: :valid, type: :goal, attrs: attrs, line_number: line_number} ->
            case Planning.create_goal(scope, attrs) do
              {:ok, goal} ->
                {
                  increment_bulk_count(acc, :goals),
                  Map.update!(ids, :goals, fn values -> [goal.id | values] end)
                }

              {:error, {:validation, details}} ->
                {add_bulk_error(acc, line_number, format_validation_errors(details)), ids}

              {:error, reason} ->
                {add_bulk_error(acc, line_number, inspect(reason)), ids}
            end

          _ ->
            {acc, ids}
        end
      end)

    last_bulk_import =
      if total_bulk_created(result.created) > 0 do
        %{
          tasks: Enum.reverse(imported_ids.tasks),
          finances: Enum.reverse(imported_ids.finances),
          goals: Enum.reverse(imported_ids.goals)
        }
      else
        nil
      end

    %{result | last_bulk_import: last_bulk_import}
  end

  defp undo_bulk_import(last_bulk_import, scope) do
    {task_removed, task_errors} =
      undo_bulk_items(last_bulk_import.tasks, fn id ->
        Planning.delete_task(scope, id)
      end)

    {finance_removed, finance_errors} =
      undo_bulk_items(last_bulk_import.finances, fn id ->
        Planning.delete_finance_entry(scope, id)
      end)

    {goal_removed, goal_errors} =
      undo_bulk_items(last_bulk_import.goals, fn id ->
        Planning.delete_goal(scope, id)
      end)

    %{
      removed: %{tasks: task_removed, finances: finance_removed, goals: goal_removed},
      errors: task_errors ++ finance_errors ++ goal_errors
    }
  end

  defp undo_bulk_items(ids, delete_fun) do
    Enum.reduce(ids, {0, []}, fn id, {removed, errors} ->
      case delete_fun.(id) do
        {:ok, _} ->
          {removed + 1, errors}

        {:error, :not_found} ->
          {removed, errors}

        {:error, reason} ->
          {removed, errors ++ ["item #{id}: #{inspect(reason)}"]}
      end
    end)
  end

  defp build_bulk_preview_entry(raw_line, line_number) do
    line = String.trim(raw_line)

    case parse_bulk_line(raw_line) do
      :skip ->
        %{line_number: line_number, raw: line, status: :ignored}

      {:error, reason} ->
        %{
          line_number: line_number,
          raw: line,
          status: :invalid,
          error: reason,
          suggested_line: suggest_bulk_fix(line, reason)
        }

      {:ok, {type, attrs}} ->
        case validate_preview_entry(type, attrs) do
          :ok ->
            %{line_number: line_number, raw: line, status: :valid, type: type, attrs: attrs}

          {:error, reason, suggested_line} ->
            %{
              line_number: line_number,
              raw: line,
              status: :invalid,
              error: reason,
              suggested_line: suggested_line
            }
        end
    end
  end

  defp validate_preview_entry(:task, attrs) do
    case AttributeValidation.validate_task_attrs(attrs) do
      {:ok, _} ->
        :ok

      {:error, {:validation, details}} ->
        {:error, format_validation_errors(details), suggest_task_validation_fix(attrs, details)}
    end
  end

  defp validate_preview_entry(:finance, attrs) do
    case AttributeValidation.validate_finance_entry_attrs(attrs) do
      {:ok, _} ->
        :ok

      {:error, {:validation, details}} ->
        {:error, format_validation_errors(details),
         suggest_finance_validation_fix(attrs, details)}
    end
  end

  defp validate_preview_entry(:goal, attrs) do
    case AttributeValidation.validate_goal_attrs(attrs) do
      {:ok, _} ->
        :ok

      {:error, {:validation, details}} ->
        {:error, format_validation_errors(details), suggest_goal_validation_fix(attrs, details)}
    end
  end

  defp suggest_bulk_fix(line, reason) when is_binary(line) and is_binary(reason) do
    cond do
      String.contains?(reason, "formato inválido") -> suggest_missing_colon_fix(line)
      String.contains?(reason, "tipo não reconhecido") -> suggest_unknown_type_fix(line)
      true -> nil
    end
  end

  defp suggest_bulk_fix(_line, _reason), do: nil

  defp suggest_missing_colon_fix(line) do
    case String.split(line, ~r/\s+/, parts: 2, trim: true) do
      [raw_type, body] ->
        case canonical_bulk_type(raw_type) do
          {:task, _} -> "tarefa: " <> body
          {:goal, _} -> "meta: " <> body
          {:finance_kind, kind} -> "financeiro: " <> kind <> " " <> body
          {:finance, _} -> "financeiro: " <> body
          :unknown -> nil
        end

      _ ->
        nil
    end
  end

  defp suggest_unknown_type_fix(line) do
    case String.split(line, ":", parts: 2) do
      [raw_type, body] ->
        normalized_body = String.trim(body)

        case canonical_bulk_type(raw_type) do
          {:task, _} -> "tarefa: " <> normalized_body
          {:goal, _} -> "meta: " <> normalized_body
          {:finance_kind, kind} -> "financeiro: " <> kind <> " " <> normalized_body
          {:finance, _} -> "financeiro: " <> normalized_body
          :unknown -> nil
        end

      _ ->
        nil
    end
  end

  defp canonical_bulk_type(token) do
    case normalize_token(token) do
      value when value in ["tarefa", "task", "t"] ->
        {:task, "tarefa"}

      value when value in ["meta", "goal", "g", "objetivo"] ->
        {:goal, "meta"}

      value
      when value in ["financeiro", "finance", "lancamento", "lanc", "fin", "f"] ->
        {:finance, "financeiro"}

      value when value in ["receita", "despesa", "income", "expense"] ->
        {:finance_kind, value}

      _ ->
        :unknown
    end
  end

  defp suggest_task_validation_fix(attrs, details) do
    if Map.has_key?(details, :due_on) do
      title = Map.get(attrs, "title", "Nova tarefa")
      priority = Map.get(attrs, "priority", "medium")
      "tarefa: #{title} | prioridade=#{priority}"
    else
      nil
    end
  end

  defp suggest_finance_validation_fix(attrs, details) do
    if Enum.any?([:kind, :amount_cents, :category, :occurred_on], &Map.has_key?(details, &1)) do
      attrs
      |> Map.put_new("kind", "expense")
      |> Map.put_new("amount_cents", 100)
      |> Map.put_new("category", "geral")
      |> Map.put_new("occurred_on", Date.to_iso8601(Date.utc_today()))
      |> then(fn fixed ->
        body =
          [
            "tipo=#{Map.get(fixed, "kind")}",
            "valor=#{Map.get(fixed, "amount_cents")}",
            "categoria=#{Map.get(fixed, "category")}",
            "data=#{Map.get(fixed, "occurred_on")}",
            Map.get(fixed, "description") && "descricao=#{Map.get(fixed, "description")}"
          ]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" | ")

        "financeiro: " <> body
      end)
    else
      nil
    end
  end

  defp suggest_goal_validation_fix(attrs, details) do
    if Map.has_key?(details, :horizon) do
      title = Map.get(attrs, "title", "Nova meta")

      parts =
        [
          "horizonte=medium",
          Map.get(attrs, "target_value") && "alvo=#{Map.get(attrs, "target_value")}",
          Map.get(attrs, "status") && "status=#{Map.get(attrs, "status")}",
          Map.get(attrs, "due_on") && "data=#{Map.get(attrs, "due_on")}"
        ]
        |> Enum.reject(&is_nil/1)

      "meta: #{title} | " <> Enum.join(parts, " | ")
    else
      nil
    end
  end

  defp apply_bulk_fix_for_line(payload, line_number)
       when is_binary(payload) and line_number > 0 do
    preview = preview_bulk_payload(payload)

    case Enum.find(preview.entries, &(&1.line_number == line_number)) do
      %{status: :invalid, suggested_line: suggested_line}
      when is_binary(suggested_line) and suggested_line != "" ->
        lines = String.split(payload, ~r/\R/u, trim: false)

        if line_number <= length(lines) do
          {:ok, List.replace_at(lines, line_number - 1, suggested_line) |> Enum.join("\n")}
        else
          {:error, :line_out_of_bounds}
        end

      _ ->
        {:error, :no_fix_available}
    end
  end

  defp apply_bulk_fix_for_line(_payload, _line_number), do: {:error, :invalid_input}

  defp apply_all_bulk_fixes(payload) when is_binary(payload) do
    preview = preview_bulk_payload(payload)
    lines = String.split(payload, ~r/\R/u, trim: false)
    line_count = length(lines)

    {fixed_lines, fixed_count} =
      Enum.reduce(preview.entries, {lines, 0}, fn entry, {acc_lines, acc_count} ->
        suggested_line = Map.get(entry, :suggested_line)

        if entry.status == :invalid and is_binary(suggested_line) and suggested_line != "" and
             entry.line_number <= line_count do
          {List.replace_at(acc_lines, entry.line_number - 1, suggested_line), acc_count + 1}
        else
          {acc_lines, acc_count}
        end
      end)

    {:ok, Enum.join(fixed_lines, "\n"), fixed_count}
  end

  defp apply_all_bulk_fixes(_payload), do: {:error, :invalid_input}

  defp bulk_preview_fixable_count(entries) when is_list(entries) do
    Enum.count(entries, fn entry ->
      entry.status == :invalid and is_binary(Map.get(entry, :suggested_line)) and
        Map.get(entry, :suggested_line) != ""
    end)
  end

  defp bulk_preview_fixable_count(_entries), do: 0

  defp parse_bulk_line(line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        :skip

      String.contains?(trimmed, ":") ->
        [raw_type, raw_body] = String.split(trimmed, ":", parts: 2)
        type = normalize_token(raw_type)
        body = String.trim(raw_body)

        cond do
          type in ["tarefa", "task", "t"] ->
            parse_task_line(body)

          type in ["financeiro", "finance", "lancamento", "lanc", "fin", "f"] ->
            parse_finance_line(body, nil)

          type in ["meta", "goal", "g"] ->
            parse_goal_line(body)

          type in ["receita", "despesa", "income", "expense"] ->
            parse_finance_line(body, type)

          true ->
            {:error, "tipo não reconhecido. Use: tarefa, financeiro ou meta"}
        end

      true ->
        {:error, "formato inválido. Use o padrão tipo: conteúdo"}
    end
  end

  defp bulk_template_payload("mixed") do
    """
    tarefa: Revisar orçamento | data=2026-04-20 | prioridade=alta
    financeiro: tipo=despesa | valor=125,90 | categoria=moradia | data=2026-04-05
    meta: Reserva de emergência | horizonte=medio | alvo=300000
    """
    |> String.trim()
  end

  defp bulk_template_payload("tasks") do
    """
    tarefa: Revisar metas da semana | data=2026-04-20 | prioridade=alta
    tarefa: Organizar documentos | data=2026-04-21 | prioridade=media
    tarefa: Planejar descanso | prioridade=baixa
    """
    |> String.trim()
  end

  defp bulk_template_payload("finance") do
    """
    financeiro: tipo=despesa | valor=98,40 | categoria=alimentacao | data=2026-04-12
    financeiro: tipo=receita | valor=250000 | categoria=freela | data=2026-04-10
    financeiro: despesa 4590 transporte 2026-04-11
    """
    |> String.trim()
  end

  defp bulk_template_payload("goals") do
    """
    meta: Reserva anual | horizonte=longo | alvo=1200000 | atual=250000
    meta: Curso de especialização | horizonte=medio | alvo=80000
    meta: Rotina de treino | horizonte=curto | status=active
    """
    |> String.trim()
  end

  defp bulk_template_payload(_), do: ""

  defp parse_task_line(body) do
    segments = split_pipe_segments(body)

    case segments do
      [] ->
        {:error, "tarefa sem título"}

      [title | rest] ->
        kv = parse_kv_segments(rest)

        attrs =
          %{"title" => title}
          |> maybe_put(
            "due_on",
            normalize_date_token(map_get_any(kv, ["data", "date", "due", "vencimento"]))
          )
          |> maybe_put(
            "priority",
            map_priority(map_get_any(kv, ["prioridade", "priority", "prio"]))
          )
          |> maybe_put("status", map_task_status(map_get_any(kv, ["status"])))
          |> maybe_put("notes", map_get_any(kv, ["nota", "notas", "notes"]))

        {:ok, {:task, attrs}}
    end
  end

  defp parse_goal_line(body) do
    segments = split_pipe_segments(body)

    case segments do
      [] ->
        {:error, "meta sem título"}

      [title | rest] ->
        kv = parse_kv_segments(rest)

        attrs =
          %{"title" => title}
          |> maybe_put("horizon", map_goal_horizon(map_get_any(kv, ["horizonte", "horizon"])))
          |> maybe_put("status", map_goal_status(map_get_any(kv, ["status"])))
          |> maybe_put(
            "target_value",
            parse_int_token(map_get_any(kv, ["alvo", "target", "target_value"]))
          )
          |> maybe_put(
            "current_value",
            parse_int_token(map_get_any(kv, ["atual", "current", "current_value"]))
          )
          |> maybe_put(
            "due_on",
            normalize_date_token(map_get_any(kv, ["data", "date", "due", "prazo"]))
          )
          |> maybe_put("notes", map_get_any(kv, ["nota", "notas", "notes"]))

        {:ok, {:goal, attrs}}
    end
  end

  defp parse_finance_line(body, declared_kind) do
    segments = split_pipe_segments(body)
    kv = parse_kv_segments(segments)

    free_segments =
      segments
      |> Enum.reject(&String.contains?(&1, "="))

    {kind, amount_cents, category, occurred_on, description} =
      parse_finance_fields(kv, free_segments, declared_kind)

    attrs =
      %{}
      |> maybe_put("kind", kind)
      |> maybe_put("amount_cents", amount_cents)
      |> maybe_put("category", category)
      |> maybe_put("occurred_on", occurred_on)
      |> maybe_put("description", description)

    {:ok, {:finance, attrs}}
  end

  defp parse_finance_fields(kv, free_segments, declared_kind) do
    free_tokens =
      free_segments
      |> Enum.join(" ")
      |> String.split(~r/\s+/, trim: true)

    kind =
      declared_kind
      |> map_finance_kind()
      |> fallback(map_finance_kind(map_get_any(kv, ["tipo", "kind"])))
      |> fallback(detect_kind_in_tokens(free_tokens))

    amount_cents =
      parse_amount_cents_token(map_get_any(kv, ["valor", "amount", "centavos", "amount_cents"])) ||
        detect_amount_in_tokens(free_tokens)

    category =
      map_get_any(kv, ["categoria", "category"]) ||
        detect_category_in_tokens(free_tokens, kind, amount_cents)

    occurred_on = normalize_date_token(map_get_any(kv, ["data", "date", "quando", "occurred_on"]))
    description = map_get_any(kv, ["descricao", "description", "desc"])

    {kind, amount_cents, category, occurred_on, description}
  end

  defp detect_kind_in_tokens(tokens) do
    tokens
    |> Enum.find_value(&map_finance_kind/1)
  end

  defp detect_amount_in_tokens(tokens) do
    tokens
    |> Enum.find_value(&parse_amount_cents_token/1)
  end

  defp detect_category_in_tokens(tokens, kind, amount_cents) do
    cleaned =
      tokens
      |> Enum.reject(fn token ->
        map_finance_kind(token) == kind or parse_amount_cents_token(token) == amount_cents
      end)

    case cleaned do
      [] -> nil
      [first | _] -> first
    end
  end

  defp split_pipe_segments(body) do
    body
    |> String.split("|", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_kv_segments(segments) do
    Enum.reduce(segments, %{}, fn segment, acc ->
      case String.split(segment, "=", parts: 2) do
        [key, value] -> Map.put(acc, normalize_token(key), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp map_get_any(map, keys) do
    Enum.find_value(keys, fn key ->
      Map.get(map, key)
    end)
  end

  defp map_priority(nil), do: nil

  defp map_priority(value) do
    case normalize_token(value) do
      "baixa" -> "low"
      "low" -> "low"
      "b" -> "low"
      "media" -> "medium"
      "média" -> "medium"
      "medium" -> "medium"
      "normal" -> "medium"
      "m" -> "medium"
      "alta" -> "high"
      "high" -> "high"
      "urgente" -> "high"
      "h" -> "high"
      _ -> nil
    end
  end

  defp map_task_status(nil), do: nil

  defp map_task_status(value) do
    case normalize_token(value) do
      "todo" -> "todo"
      "pendente" -> "todo"
      "in_progress" -> "in_progress"
      "andamento" -> "in_progress"
      "em_andamento" -> "in_progress"
      "done" -> "done"
      "concluida" -> "done"
      "concluída" -> "done"
      _ -> nil
    end
  end

  defp map_goal_horizon(nil), do: nil

  defp map_goal_horizon(value) do
    case normalize_token(value) do
      "curto" -> "short"
      "short" -> "short"
      "medio" -> "medium"
      "médio" -> "medium"
      "medium" -> "medium"
      "longo" -> "long"
      "long" -> "long"
      _ -> nil
    end
  end

  defp map_goal_status(nil), do: nil

  defp map_goal_status(value) do
    case normalize_token(value) do
      "active" -> "active"
      "ativa" -> "active"
      "paused" -> "paused"
      "pausada" -> "paused"
      "done" -> "done"
      "concluida" -> "done"
      "concluída" -> "done"
      _ -> nil
    end
  end

  defp map_finance_kind(nil), do: nil

  defp map_finance_kind(value) do
    case normalize_token(value) do
      "receita" -> "income"
      "income" -> "income"
      "despesa" -> "expense"
      "expense" -> "expense"
      _ -> nil
    end
  end

  defp parse_int_token(nil), do: nil

  defp parse_int_token(value) when is_integer(value), do: value

  defp parse_int_token(value) when is_binary(value) do
    cleaned =
      value
      |> String.trim()
      |> String.replace(~r/[^0-9-]/u, "")

    case Integer.parse(cleaned) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int_token(_), do: nil

  defp parse_amount_cents_token(nil), do: nil

  defp parse_amount_cents_token(value) when is_integer(value), do: value

  defp parse_amount_cents_token(value) when is_binary(value) do
    cleaned =
      value
      |> String.trim()
      |> String.replace(" ", "")
      |> String.replace("R$", "")
      |> String.replace(~r/[^0-9,\.\-]/u, "")

    sign = if String.starts_with?(cleaned, "-"), do: -1, else: 1

    normalized =
      cleaned
      |> String.replace("-", "")
      |> normalize_amount_numeric_string()

    cond do
      normalized == "" ->
        nil

      true ->
        normalized
        |> amount_string_to_cents()
        |> case do
          nil -> nil
          cents -> sign * cents
        end
    end
  end

  defp parse_amount_cents_token(_), do: nil

  defp normalize_date_token(nil), do: nil
  defp normalize_date_token(%Date{} = date), do: Date.to_iso8601(date)

  defp normalize_date_token(value) when is_binary(value) do
    cleaned = String.trim(value)

    case normalize_token(cleaned) do
      "hoje" ->
        Date.to_iso8601(Date.utc_today())

      "amanha" ->
        Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

      "amanhã" ->
        Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

      "ontem" ->
        Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()

      _ ->
        normalize_explicit_date(cleaned)
    end
  end

  defp normalize_date_token(_), do: nil

  defp normalize_explicit_date(cleaned) do
    case Date.from_iso8601(cleaned) do
      {:ok, date} ->
        Date.to_iso8601(date)

      _ ->
        with [y, m, d] <-
               Regex.run(~r/^(\d{4})[\/\-\.](\d{1,2})[\/\-\.](\d{1,2})$/u, cleaned,
                 capture: :all_but_first
               ),
             {year, ""} <- Integer.parse(y),
             {month, ""} <- Integer.parse(m),
             {day, ""} <- Integer.parse(d),
             {:ok, date} <- Date.new(year, month, day) do
          Date.to_iso8601(date)
        else
          _ ->
            with [a, b, y] <-
                   Regex.run(~r/^(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{4})$/u, cleaned,
                     capture: :all_but_first
                   ),
                 {da, ""} <- Integer.parse(a),
                 {db, ""} <- Integer.parse(b),
                 {dy, ""} <- Integer.parse(y),
                 {year, month, day} <- infer_date_parts(da, db, dy),
                 {:ok, date} <- Date.new(year, month, day) do
              Date.to_iso8601(date)
            else
              _ -> cleaned
            end
        end
    end
  end

  defp amount_string_to_cents(value) do
    cond do
      Regex.match?(~r/^\d+$/u, value) ->
        parse_int_token(value)

      Regex.match?(~r/^\d+\.\d{1,2}$/u, value) ->
        [whole, frac] = String.split(value, ".", parts: 2)
        cents = parse_int_token(whole)

        frac_cents =
          case String.length(frac) do
            1 -> parse_int_token(frac) * 10
            _ -> parse_int_token(frac)
          end

        cents * 100 + frac_cents

      true ->
        nil
    end
  end

  defp infer_date_parts(a, b, y) when a > 12, do: {y, b, a}
  defp infer_date_parts(a, b, y) when b > 12, do: {y, a, b}
  defp infer_date_parts(a, b, y), do: {y, b, a}

  defp normalize_token(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_token(value), do: value |> to_string() |> normalize_token()

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp fallback(nil, value), do: value
  defp fallback(value, _other), do: value

  defp total_bulk_created(created) do
    created.tasks + created.finances + created.goals
  end

  defp bulk_preview_status_badge_class(:valid),
    do: "border border-emerald-300/30 bg-emerald-500/15 text-emerald-100"

  defp bulk_preview_status_badge_class(:invalid),
    do: "border border-amber-300/30 bg-amber-500/15 text-amber-100"

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
    kind = Map.get(attrs, "kind", "tipo pendente")
    category = Map.get(attrs, "category", "categoria pendente")
    amount = format_bulk_amount(Map.get(attrs, "amount_cents"))
    "Financeiro: #{kind} • #{amount} • #{category}"
  end

  defp bulk_preview_entry_label(%{status: :valid, type: :goal, attrs: attrs}) do
    title = Map.get(attrs, "title", "sem título")
    horizon = Map.get(attrs, "horizon", "horizonte pendente")
    target = Map.get(attrs, "target_value", "alvo pendente")
    "Meta: #{title} • #{horizon} • alvo #{target}"
  end

  defp bulk_preview_entry_label(_), do: "Linha processada"

  defp format_bulk_amount(amount_cents) when is_integer(amount_cents),
    do: format_money(amount_cents)

  defp format_bulk_amount(_), do: "valor pendente"

  defp add_bulk_error(acc, line_number, message) do
    Map.update!(acc, :errors, fn errors ->
      errors ++ ["Linha #{line_number}: #{message}"]
    end)
  end

  defp increment_bulk_count(acc, key) do
    update_in(acc, [:created, key], &(&1 + 1))
  end

  defp format_validation_errors(details) when is_map(details) do
    details
    |> Enum.map(fn {field, messages} ->
      "#{field}: #{Enum.join(messages, ", ")}"
    end)
    |> Enum.join(" | ")
  end

  defp format_validation_errors(details), do: inspect(details)

  defp remember_bulk_payload(socket, payload) when is_binary(payload) do
    trimmed = String.trim(payload)

    if trimmed == "" do
      socket
    else
      entry =
        case Enum.find(socket.assigns.bulk_recent_payloads, &(&1.payload == trimmed)) do
          nil ->
            %{
              id: System.unique_integer([:positive]),
              payload: trimmed,
              preview_line: preview_history_line(trimmed),
              favorite: false
            }

          existing ->
            %{
              existing
              | preview_line: preview_history_line(trimmed)
            }
        end

      history =
        [entry | Enum.reject(socket.assigns.bulk_recent_payloads, &(&1.payload == trimmed))]
        |> Enum.take(10)

      assign(socket, :bulk_recent_payloads, history)
    end
  end

  defp remember_bulk_payload(socket, _payload), do: socket

  defp preview_history_line(payload) do
    payload
    |> String.split(~r/\R/u, trim: true)
    |> List.first()
    |> case do
      nil -> "(vazio)"
      value -> value
    end
  end

  defp sorted_bulk_templates(favorites) do
    templates = [
      %{key: "mixed", label: "Misto"},
      %{key: "tasks", label: "Tarefas"},
      %{key: "finance", label: "Financeiro"},
      %{key: "goals", label: "Metas"}
    ]

    favorite_set = MapSet.new(favorites)

    Enum.sort_by(templates, fn template ->
      if MapSet.member?(favorite_set, template.key), do: 0, else: 1
    end)
  end

  defp template_favorited?(favorites, key), do: key in favorites

  defp toggle_string_flag(list, value) do
    if value in list do
      Enum.reject(list, &(&1 == value))
    else
      [value | list]
    end
  end

  defp find_bulk_history_entry(history, id) do
    Enum.find(history, &(to_string(&1.id) == to_string(id)))
  end

  defp current_bulk_import_block(nil, _size, _index),
    do: %{entries: [], index: 0, total: 0}

  defp current_bulk_import_block(preview, size, index) do
    safe_size = max(size, 1)

    blocks =
      preview.entries
      |> Enum.filter(&(&1.status == :valid))
      |> Enum.chunk_every(safe_size)

    total = length(blocks)
    safe_index = clamp_bulk_index(index, total)

    entries = if total > 0, do: Enum.at(blocks, safe_index, []), else: []

    %{entries: entries, index: safe_index, total: total}
  end

  defp bulk_block_total(nil, _size), do: 0

  defp bulk_block_total(preview, size) do
    preview
    |> current_bulk_import_block(size, 0)
    |> Map.get(:total, 0)
  end

  defp clamp_bulk_block_index(index, preview, size) do
    total = bulk_block_total(preview, size)
    clamp_bulk_index(index, total)
  end

  defp clamp_bulk_index(_index, total) when total <= 0, do: 0
  defp clamp_bulk_index(index, total), do: index |> max(0) |> min(total - 1)

  defp remove_bulk_payload_lines(payload, line_numbers) when is_binary(payload) do
    to_remove = MapSet.new(line_numbers)

    payload
    |> String.split(~r/\R/u, trim: false)
    |> Enum.with_index(1)
    |> Enum.reject(fn {_line, line_number} -> MapSet.member?(to_remove, line_number) end)
    |> Enum.map(fn {line, _line_number} -> line end)
    |> Enum.join("\n")
    |> String.trim()
  end

  defp remove_bulk_payload_lines(payload, _line_numbers), do: payload

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
      Map.get(attrs, "amount_cents") && "valor=#{Map.get(attrs, "amount_cents")}",
      Map.get(attrs, "category") && "categoria=#{Map.get(attrs, "category")}",
      Map.get(attrs, "occurred_on") && "data=#{Map.get(attrs, "occurred_on")}",
      Map.get(attrs, "description") && "descricao=#{Map.get(attrs, "description")}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
  end

  defp bulk_entry_normalized_line(%{status: :valid, type: :goal, attrs: attrs}) do
    [
      "meta: #{Map.get(attrs, "title", "")}",
      Map.get(attrs, "horizon") && "horizonte=#{Map.get(attrs, "horizon")}",
      Map.get(attrs, "target_value") && "alvo=#{Map.get(attrs, "target_value")}",
      Map.get(attrs, "current_value") && "atual=#{Map.get(attrs, "current_value")}",
      Map.get(attrs, "status") && "status=#{Map.get(attrs, "status")}",
      Map.get(attrs, "due_on") && "data=#{Map.get(attrs, "due_on")}",
      Map.get(attrs, "notes") && "notes=#{Map.get(attrs, "notes")}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
  end

  defp bulk_entry_normalized_line(entry), do: Map.get(entry, :raw, "")

  defp bulk_line_changed?(entry) do
    String.trim(Map.get(entry, :raw, "")) != String.trim(bulk_entry_normalized_line(entry))
  end

  defp normalize_amount_numeric_string(value) do
    has_comma = String.contains?(value, ",")
    has_dot = String.contains?(value, ".")

    cond do
      has_comma and has_dot ->
        if last_index(value, ",") > last_index(value, ".") do
          value
          |> String.replace(".", "")
          |> String.replace(",", ".")
        else
          String.replace(value, ",", "")
        end

      has_comma ->
        if Regex.match?(~r/,\d{1,2}$/u, value) do
          String.replace(value, ",", ".")
        else
          String.replace(value, ",", "")
        end

      has_dot ->
        if Regex.match?(~r/\.\d{1,2}$/u, value) do
          value
        else
          String.replace(value, ".", "")
        end

      true ->
        value
    end
  end

  defp last_index(value, pattern) when is_binary(value) and is_binary(pattern) do
    case :binary.matches(value, pattern) do
      [] ->
        -1

      matches ->
        {index, _len} = List.last(matches)
        index
    end
  end
end
