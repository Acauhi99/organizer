defmodule OrganizerWeb.Components.BulkImportHeroTest do
  use OrganizerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Phoenix.Component
  alias OrganizerWeb.Components.BulkImportHero

  describe "empty_state_educational/1" do
    test "renders empty state for bulk_import" do
      assigns = %{entity_type: :bulk_import}

      html =
        rendered_to_string(~H"""
        <BulkImportHero.empty_state_educational entity_type={@entity_type} />
        """)

      assert html =~ "empty-state-bulk_import"
      assert html =~ "Comece a importar seus dados"
    end

    test "renders empty state for tasks" do
      assigns = %{entity_type: :tasks}

      html =
        rendered_to_string(~H"""
        <BulkImportHero.empty_state_educational entity_type={@entity_type} />
        """)

      assert html =~ "empty-state-tasks"
      assert html =~ "Nenhuma tarefa cadastrada"
      assert html =~ "tarefa: título"
    end

    test "renders empty state for finances" do
      assigns = %{entity_type: :finances}

      html =
        rendered_to_string(~H"""
        <BulkImportHero.empty_state_educational entity_type={@entity_type} />
        """)

      assert html =~ "empty-state-finances"
      assert html =~ "Nenhum lançamento financeiro"
      assert html =~ "finança: valor descrição"
    end

    test "renders empty state for goals" do
      assigns = %{entity_type: :goals}

      html =
        rendered_to_string(~H"""
        <BulkImportHero.empty_state_educational entity_type={@entity_type} />
        """)

      assert html =~ "empty-state-goals"
      assert html =~ "Nenhuma meta cadastrada"
      assert html =~ "meta: descrição"
    end

    test "includes load example button" do
      assigns = %{entity_type: :tasks}

      html =
        rendered_to_string(~H"""
        <BulkImportHero.empty_state_educational entity_type={@entity_type} />
        """)

      assert html =~ "load-example-tasks"
      assert html =~ "Carregar no editor"
      assert html =~ "phx-click=\"load_example_to_bulk\""
    end

    test "includes example code for each entity type" do
      for entity_type <- [:bulk_import, :tasks, :finances, :goals] do
        assigns = %{entity_type: entity_type}

        html =
          rendered_to_string(~H"""
          <BulkImportHero.empty_state_educational entity_type={@entity_type} />
          """)

        assert html =~ "Exemplo:"
        assert html =~ "<code "
      end
    end

    test "uses correct icon for each entity type" do
      assigns = %{entity_type: :tasks}

      html =
        rendered_to_string(~H"""
        <BulkImportHero.empty_state_educational entity_type={@entity_type} />
        """)

      assert html =~ "hero-check-circle"
    end
  end

  describe "onboarding_hints/1" do
    test "renders onboarding hints when active" do
      assigns = %{
        bulk_form: Phoenix.Component.to_form(%{}, as: :bulk),
        bulk_payload_text: "",
        bulk_result: nil,
        bulk_preview: nil,
        bulk_strict_mode: false,
        last_bulk_import: nil,
        bulk_recent_payloads: [],
        bulk_template_favorites: [],
        bulk_import_block_size: 3,
        bulk_import_block_index: 0,
        bulk_top_categories: [],
        onboarding_active: true,
        onboarding_step: 1,
        has_any_imports: false
      }

      html =
        rendered_to_string(~H"""
        <BulkImportHero.bulk_import_hero
          bulk_form={@bulk_form}
          bulk_payload_text={@bulk_payload_text}
          bulk_result={@bulk_result}
          bulk_preview={@bulk_preview}
          bulk_strict_mode={@bulk_strict_mode}
          last_bulk_import={@last_bulk_import}
          bulk_recent_payloads={@bulk_recent_payloads}
          bulk_template_favorites={@bulk_template_favorites}
          bulk_import_block_size={@bulk_import_block_size}
          bulk_import_block_index={@bulk_import_block_index}
          bulk_top_categories={@bulk_top_categories}
          onboarding_active={@onboarding_active}
          onboarding_step={@onboarding_step}
          has_any_imports={@has_any_imports}
        />
        """)

      assert html =~ "onboarding-hints"
      assert html =~ "Bem-vindo ao Copy/Paste Studio!"
    end

    test "does not render onboarding hints when inactive" do
      assigns = %{
        bulk_form: Phoenix.Component.to_form(%{}, as: :bulk),
        bulk_payload_text: "",
        bulk_result: nil,
        bulk_preview: nil,
        bulk_strict_mode: false,
        last_bulk_import: nil,
        bulk_recent_payloads: [],
        bulk_template_favorites: [],
        bulk_import_block_size: 3,
        bulk_import_block_index: 0,
        bulk_top_categories: [],
        onboarding_active: false,
        onboarding_step: 1,
        has_any_imports: false
      }

      html =
        rendered_to_string(~H"""
        <BulkImportHero.bulk_import_hero
          bulk_form={@bulk_form}
          bulk_payload_text={@bulk_payload_text}
          bulk_result={@bulk_result}
          bulk_preview={@bulk_preview}
          bulk_strict_mode={@bulk_strict_mode}
          last_bulk_import={@last_bulk_import}
          bulk_recent_payloads={@bulk_recent_payloads}
          bulk_template_favorites={@bulk_template_favorites}
          bulk_import_block_size={@bulk_import_block_size}
          bulk_import_block_index={@bulk_import_block_index}
          bulk_top_categories={@bulk_top_categories}
          onboarding_active={@onboarding_active}
          onboarding_step={@onboarding_step}
          has_any_imports={@has_any_imports}
        />
        """)

      refute html =~ "onboarding-hints"
    end

    test "displays step-specific content for step 1" do
      assigns = %{
        bulk_form: Phoenix.Component.to_form(%{}, as: :bulk),
        bulk_payload_text: "",
        bulk_result: nil,
        bulk_preview: nil,
        bulk_strict_mode: false,
        last_bulk_import: nil,
        bulk_recent_payloads: [],
        bulk_template_favorites: [],
        bulk_import_block_size: 3,
        bulk_import_block_index: 0,
        bulk_top_categories: [],
        onboarding_active: true,
        onboarding_step: 1,
        has_any_imports: false
      }

      html =
        rendered_to_string(~H"""
        <BulkImportHero.bulk_import_hero
          bulk_form={@bulk_form}
          bulk_payload_text={@bulk_payload_text}
          bulk_result={@bulk_result}
          bulk_preview={@bulk_preview}
          bulk_strict_mode={@bulk_strict_mode}
          last_bulk_import={@last_bulk_import}
          bulk_recent_payloads={@bulk_recent_payloads}
          bulk_template_favorites={@bulk_template_favorites}
          bulk_import_block_size={@bulk_import_block_size}
          bulk_import_block_index={@bulk_import_block_index}
          bulk_top_categories={@bulk_top_categories}
          onboarding_active={@onboarding_active}
          onboarding_step={@onboarding_step}
          has_any_imports={@has_any_imports}
        />
        """)

      assert html =~ "Bem-vindo ao Copy/Paste Studio!"
      assert html =~ "componente principal da plataforma"
      assert html =~ "hero-sparkles"
    end

    test "displays step-specific content for step 2" do
      assigns = %{
        bulk_form: Phoenix.Component.to_form(%{}, as: :bulk),
        bulk_payload_text: "",
        bulk_result: nil,
        bulk_preview: nil,
        bulk_strict_mode: false,
        last_bulk_import: nil,
        bulk_recent_payloads: [],
        bulk_template_favorites: [],
        bulk_import_block_size: 3,
        bulk_import_block_index: 0,
        bulk_top_categories: [],
        onboarding_active: true,
        onboarding_step: 2,
        has_any_imports: false
      }

      html =
        rendered_to_string(~H"""
        <BulkImportHero.bulk_import_hero
          bulk_form={@bulk_form}
          bulk_payload_text={@bulk_payload_text}
          bulk_result={@bulk_result}
          bulk_preview={@bulk_preview}
          bulk_strict_mode={@bulk_strict_mode}
          last_bulk_import={@last_bulk_import}
          bulk_recent_payloads={@bulk_recent_payloads}
          bulk_template_favorites={@bulk_template_favorites}
          bulk_import_block_size={@bulk_import_block_size}
          bulk_import_block_index={@bulk_import_block_index}
          bulk_top_categories={@bulk_top_categories}
          onboarding_active={@onboarding_active}
          onboarding_step={@onboarding_step}
          has_any_imports={@has_any_imports}
        />
        """)

      assert html =~ "Digite suas linhas aqui"
      assert html =~ "tipo: conteúdo"
      assert html =~ "hero-document-text"
      assert html =~ "onboarding-arrow-down"
    end

    test "displays step-specific content for step 3" do
      assigns = %{
        bulk_form: Phoenix.Component.to_form(%{}, as: :bulk),
        bulk_payload_text: "",
        bulk_result: nil,
        bulk_preview: nil,
        bulk_strict_mode: false,
        last_bulk_import: nil,
        bulk_recent_payloads: [],
        bulk_template_favorites: [],
        bulk_import_block_size: 3,
        bulk_import_block_index: 0,
        bulk_top_categories: [],
        onboarding_active: true,
        onboarding_step: 3,
        has_any_imports: false
      }

      html =
        rendered_to_string(~H"""
        <BulkImportHero.bulk_import_hero
          bulk_form={@bulk_form}
          bulk_payload_text={@bulk_payload_text}
          bulk_result={@bulk_result}
          bulk_preview={@bulk_preview}
          bulk_strict_mode={@bulk_strict_mode}
          last_bulk_import={@last_bulk_import}
          bulk_recent_payloads={@bulk_recent_payloads}
          bulk_template_favorites={@bulk_template_favorites}
          bulk_import_block_size={@bulk_import_block_size}
          bulk_import_block_index={@bulk_import_block_index}
          bulk_top_categories={@bulk_top_categories}
          onboarding_active={@onboarding_active}
          onboarding_step={@onboarding_step}
          has_any_imports={@has_any_imports}
        />
        """)

      assert html =~ "Revise antes de importar"
      assert html =~ "Pré-visualizar"
      assert html =~ "hero-eye"
      assert html =~ "onboarding-arrow-right"
    end

    test "displays step-specific content for step 4" do
      assigns = %{
        bulk_form: Phoenix.Component.to_form(%{}, as: :bulk),
        bulk_payload_text: "",
        bulk_result: nil,
        bulk_preview: nil,
        bulk_strict_mode: false,
        last_bulk_import: nil,
        bulk_recent_payloads: [],
        bulk_template_favorites: [],
        bulk_import_block_size: 3,
        bulk_import_block_index: 0,
        bulk_top_categories: [],
        onboarding_active: true,
        onboarding_step: 4,
        has_any_imports: false
      }

      html =
        rendered_to_string(~H"""
        <BulkImportHero.bulk_import_hero
          bulk_form={@bulk_form}
          bulk_payload_text={@bulk_payload_text}
          bulk_result={@bulk_result}
          bulk_preview={@bulk_preview}
          bulk_strict_mode={@bulk_strict_mode}
          last_bulk_import={@last_bulk_import}
          bulk_recent_payloads={@bulk_recent_payloads}
          bulk_template_favorites={@bulk_template_favorites}
          bulk_import_block_size={@bulk_import_block_size}
          bulk_import_block_index={@bulk_import_block_index}
          bulk_top_categories={@bulk_top_categories}
          onboarding_active={@onboarding_active}
          onboarding_step={@onboarding_step}
          has_any_imports={@has_any_imports}
        />
        """)

      assert html =~ "Correções automáticas"
      assert html =~ "sugestões inteligentes"
      assert html =~ "hero-wrench-screwdriver"
    end

    test "includes data-step attribute for CSS targeting" do
      assigns = %{
        bulk_form: Phoenix.Component.to_form(%{}, as: :bulk),
        bulk_payload_text: "",
        bulk_result: nil,
        bulk_preview: nil,
        bulk_strict_mode: false,
        last_bulk_import: nil,
        bulk_recent_payloads: [],
        bulk_template_favorites: [],
        bulk_import_block_size: 3,
        bulk_import_block_index: 0,
        bulk_top_categories: [],
        onboarding_active: true,
        onboarding_step: 2,
        has_any_imports: false
      }

      html =
        rendered_to_string(~H"""
        <BulkImportHero.bulk_import_hero
          bulk_form={@bulk_form}
          bulk_payload_text={@bulk_payload_text}
          bulk_result={@bulk_result}
          bulk_preview={@bulk_preview}
          bulk_strict_mode={@bulk_strict_mode}
          last_bulk_import={@last_bulk_import}
          bulk_recent_payloads={@bulk_recent_payloads}
          bulk_template_favorites={@bulk_template_favorites}
          bulk_import_block_size={@bulk_import_block_size}
          bulk_import_block_index={@bulk_import_block_index}
          bulk_top_categories={@bulk_top_categories}
          onboarding_active={@onboarding_active}
          onboarding_step={@onboarding_step}
          has_any_imports={@has_any_imports}
        />
        """)

      assert html =~ "data-step=\"2\""
    end
  end
end
