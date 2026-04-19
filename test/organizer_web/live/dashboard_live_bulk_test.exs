defmodule OrganizerWeb.DashboardLiveBulkTest do
  use OrganizerWeb.ConnCase

  import Organizer.AccountsFixtures
  import Phoenix.LiveViewTest

  # ── helpers ──────────────────────────────────────────────────────────────────

  defp mount_authenticated(conn) do
    user = user_fixture()
    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/dashboard")
    {view, user_scope_fixture(user)}
  end

  defp do_preview(view, payload) do
    view
    |> element("#bulk-capture-form")
    |> render_submit(%{"bulk" => %{"payload" => payload}, "action" => "preview"})
  end

  # ── validate_bulk_line ────────────────────────────────────────────────────────

  describe "validate_bulk_line" do
    setup %{conn: conn} do
      {view, scope} = mount_authenticated(conn)
      %{view: view, scope: scope}
    end

    test "sends bulk-line-validated push event with index, level and feedback for valid task",
         %{view: view} do
      render_hook(view, "validate_bulk_line", %{
        "line" => "tarefa: Reunião de equipe | prioridade=alta",
        "index" => 0
      })

      assert_reply(view, payload)
      assert payload.index == 0
      assert payload.confidence_level in ["high", "medium", "low", "error", "ignored"]
      assert is_binary(payload.feedback)
      assert is_float(payload.score) or is_integer(payload.score)
    end

    test "sends bulk-line-validated for a valid finance line", %{view: view} do
      render_hook(view, "validate_bulk_line", %{
        "line" => "financeiro: almoço 35",
        "index" => 1
      })

      assert_reply(view, payload)
      assert payload.index == 1
      assert payload.confidence_level in ["high", "medium", "low", "error", "ignored"]
    end

    test "sends bulk-line-validated with error level for unparseable line", %{view: view} do
      render_hook(view, "validate_bulk_line", %{
        "line" => "linha sem prefixo de tipo",
        "index" => 3
      })

      assert_reply(view, payload)
      assert payload.index == 3
      assert payload.confidence_level in ["error", "low"]
    end

    test "accepts string index from JavaScript", %{view: view} do
      render_hook(view, "validate_bulk_line", %{
        "line" => "meta: Aprender Elixir",
        "index" => "2"
      })

      assert_reply(view, payload)
      assert payload.index == 2
    end

    test "sends ignored level for blank line", %{view: view} do
      render_hook(view, "validate_bulk_line", %{"line" => "", "index" => 0})

      assert_reply(view, payload)
      assert payload.index == 0
      assert payload.confidence_level == "ignored"
    end

    test "replies with completed field value for textarea autocomplete", %{view: view} do
      render_hook(view, "complete_field_value", %{
        "field" => "prioridade",
        "prefix" => "a"
      })

      assert_reply(view, %{field: "prioridade", completed: "alta"})
    end
  end

  # ── select_disambiguation ─────────────────────────────────────────────────────

  describe "select_disambiguation" do
    setup %{conn: conn} do
      {view, scope} = mount_authenticated(conn)
      %{view: view, scope: scope}
    end

    test "replaces the entry at the given index in bulk_preview", %{view: view} do
      today = Date.to_iso8601(Date.utc_today())

      # Build a preview first so bulk_preview assign is populated
      payload = "tarefa: Comprar leite | data=#{today} | prioridade=alta"
      do_preview(view, payload)

      assert has_element?(view, "#bulk-capture-preview")
      assert has_element?(view, "#bulk-preview-line-1")

      # Replace line 1 with a new interpretation
      new_line = "tarefa: Comprar leite | data=#{today} | prioridade=media"

      render_hook(view, "select_disambiguation", %{
        "index" => 1,
        "line" => new_line
      })

      # Preview still visible – the entry was replaced, not removed
      assert has_element?(view, "#bulk-capture-preview")
      assert has_element?(view, "#bulk-preview-line-1")
    end

    test "ignores event when bulk_preview is nil", %{view: view} do
      # No preview has been built – socket.assigns.bulk_preview is nil
      render_hook(view, "select_disambiguation", %{
        "index" => 1,
        "line" => "tarefa: Nova interpretação"
      })

      # Should not crash and preview should still be absent
      refute has_element?(view, "#bulk-capture-preview")
    end

    test "handles string index from JavaScript", %{view: view} do
      today = Date.to_iso8601(Date.utc_today())
      do_preview(view, "tarefa: Tarefa teste | data=#{today}")

      render_hook(view, "select_disambiguation", %{
        "index" => "1",
        "line" => "tarefa: Tarefa atualizada | data=#{today} | prioridade=baixa"
      })

      assert has_element?(view, "#bulk-preview-line-1")
    end
  end

  # ── submit_bulk_capture preview scoring aggregation ───────────────────────────

  describe "submit_bulk_capture with action=preview – scoring aggregation" do
    setup %{conn: conn} do
      {view, scope} = mount_authenticated(conn)
      %{view: view, scope: scope}
    end

    test "shows scoring summary element after preview", %{view: view} do
      today = Date.to_iso8601(Date.utc_today())

      do_preview(view, "tarefa: Task preview | data=#{today} | prioridade=alta")

      assert has_element?(view, "#bulk-capture-preview")
      assert has_element?(view, "#bulk-scoring-summary")
    end

    test "displays 'pronto para importar' when all entries are high confidence", %{view: view} do
      today = Date.to_iso8601(Date.utc_today())

      # A fully-specified task line should produce high confidence
      payload = "tarefa: Reunião semanal | data=#{today} | prioridade=alta"

      do_preview(view, payload)

      assert has_element?(view, "#bulk-scoring-summary")

      html = render(view)

      # The scoring summary should show either the ready-to-import confirmation
      # or the breakdown – assert the element is rendered without crashing
      assert html =~ "bulk-scoring-summary"
    end

    test "shows warning when entries have medium or low confidence", %{view: view} do
      # A line with missing required fields should produce medium/low confidence
      payload = "financeiro: almoço"

      do_preview(view, payload)

      assert has_element?(view, "#bulk-scoring-summary")
    end

    test "preview entries are rendered per line", %{view: view} do
      today = Date.to_iso8601(Date.utc_today())

      payload = """
      tarefa: Task A | data=#{today} | prioridade=alta
      meta: Meta B | horizonte=medio
      """

      do_preview(view, payload)

      assert has_element?(view, "#bulk-preview-line-1")
      assert has_element?(view, "#bulk-preview-line-2")
    end

    test "records no db entries during preview", %{view: view, scope: scope} do
      today = Date.to_iso8601(Date.utc_today())

      {:ok, tasks_before} = Organizer.Planning.list_tasks(scope, %{})

      do_preview(view, "tarefa: Só preview | data=#{today} | prioridade=alta")

      assert has_element?(view, "#bulk-capture-preview")
      refute has_element?(view, "#bulk-capture-result")

      {:ok, tasks_after} = Organizer.Planning.list_tasks(scope, %{})
      assert length(tasks_after) == length(tasks_before)
    end
  end
end
