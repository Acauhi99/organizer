defmodule OrganizerWeb.DashboardLive.Components.BulkImportStudioTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Phoenix.LiveViewTest
  alias OrganizerWeb.DashboardLive.Components.BulkImportStudio

  # Feature: dashboard-components, Property 4: BulkImportStudio é uma função pura
  # Validates: Requirements 4.1, 4.4
  property "BulkImportStudio is a pure function - same assigns produce identical output" do
    check all(
            payload_text <- StreamData.string(:printable),
            bulk_strict_mode <- StreamData.boolean(),
            bulk_template_favorites <-
              StreamData.list_of(StreamData.member_of(["mixed", "tasks", "finance", "goals"])),
            bulk_import_block_size <- StreamData.member_of([2, 3, 5, 10]),
            bulk_import_block_index <- StreamData.integer(0..5)
          ) do
      bulk_form = Phoenix.Component.to_form(%{"payload" => payload_text}, as: :bulk)

      assigns = %{
        bulk_form: bulk_form,
        bulk_payload_text: payload_text,
        bulk_result: nil,
        bulk_preview: nil,
        bulk_strict_mode: bulk_strict_mode,
        last_bulk_import: nil,
        bulk_recent_payloads: [],
        bulk_template_favorites: bulk_template_favorites,
        bulk_import_block_size: bulk_import_block_size,
        bulk_import_block_index: bulk_import_block_index,
        bulk_top_categories: []
      }

      html1 = render_component(&BulkImportStudio.bulk_import_studio/1, assigns)
      html2 = render_component(&BulkImportStudio.bulk_import_studio/1, assigns)

      assert html1 == html2
    end
  end

  defp base_assigns do
    %{
      bulk_form: Phoenix.Component.to_form(%{"payload" => ""}, as: :bulk),
      bulk_payload_text: "",
      bulk_result: nil,
      bulk_preview: nil,
      bulk_strict_mode: false,
      last_bulk_import: nil,
      bulk_recent_payloads: [],
      bulk_template_favorites: [],
      bulk_import_block_size: 3,
      bulk_import_block_index: 0,
      bulk_top_categories: []
    }
  end

  describe "unit tests" do
    test "renders with nil preview and nil result" do
      html = render_component(&BulkImportStudio.bulk_import_studio/1, base_assigns())

      assert html =~ "bulk-capture-form"
      assert html =~ "Importação rápida por texto"
      refute html =~ "bulk-capture-preview"
      refute html =~ "bulk-capture-result"
    end

    test "shows undo button when last_bulk_import is set" do
      assigns =
        base_assigns()
        |> Map.put(:last_bulk_import, %{id: "some-id"})
        |> Map.put(:bulk_result, %{
          created: %{tasks: 1, finances: 0, goals: 0},
          errors: []
        })

      html = render_component(&BulkImportStudio.bulk_import_studio/1, assigns)

      assert html =~ "Desfazer"
      assert html =~ "bulk-undo-btn"
    end

    test "shows preview section when bulk_preview is set" do
      preview = %{
        lines_total: 2,
        valid_total: 1,
        invalid_total: 1,
        ignored_total: 0,
        entries: [
          %{
            line_number: 1,
            status: :valid,
            raw: "tarefa: test",
            type: :task,
            attrs: %{"title" => "test", "priority" => "medium", "due_on" => "2026-04-20"},
            inferred_fields: []
          },
          %{
            line_number: 2,
            status: :invalid,
            raw: "invalid line",
            error: "Tipo não reconhecido",
            suggested_line: nil
          }
        ],
        scoring: %{high_confidence: 1, medium_confidence: 0, low_confidence: 0, errors: 1}
      }

      assigns = Map.put(base_assigns(), :bulk_preview, preview)

      html = render_component(&BulkImportStudio.bulk_import_studio/1, assigns)

      assert html =~ "bulk-capture-preview"
      assert html =~ "bulk-preview-line-1"
      assert html =~ "bulk-preview-line-2"
      assert html =~ "tarefa: test"
      assert html =~ "invalid line"
    end
  end
end
