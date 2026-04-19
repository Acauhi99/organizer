defmodule OrganizerWeb.Components.OnboardingOverlayTest do
  use OrganizerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Phoenix.Component
  alias OrganizerWeb.Components.OnboardingOverlay

  describe "onboarding_overlay/1" do
    test "renders when active is true" do
      assigns = %{active: true, current_step: 1, total_steps: 6, can_skip: true}

      html =
        rendered_to_string(~H"""
        <OnboardingOverlay.onboarding_overlay
          active={@active}
          current_step={@current_step}
          total_steps={@total_steps}
          can_skip={@can_skip}
        />
        """)

      assert html =~ "onboarding-overlay"
      assert html =~ "backdrop-blur-[4px]"
      assert html =~ "backdrop-blur-[12px]"
    end

    test "does not render when active is false" do
      assigns = %{active: false, current_step: 1, total_steps: 6, can_skip: true}

      html =
        rendered_to_string(~H"""
        <OnboardingOverlay.onboarding_overlay
          active={@active}
          current_step={@current_step}
          total_steps={@total_steps}
          can_skip={@can_skip}
        />
        """)

      refute html =~ "onboarding-overlay"
    end

    test "renders correct step content for step 1" do
      assigns = %{active: true, current_step: 1, total_steps: 6, can_skip: true}

      html =
        rendered_to_string(~H"""
        <OnboardingOverlay.onboarding_overlay
          active={@active}
          current_step={@current_step}
          total_steps={@total_steps}
          can_skip={@can_skip}
        />
        """)

      assert html =~ "Bem-vindo ao Organizer!"
      assert html =~ "importação em lote"
    end

    test "renders correct step content for step 2" do
      assigns = %{active: true, current_step: 2, total_steps: 6, can_skip: true}

      html =
        rendered_to_string(~H"""
        <OnboardingOverlay.onboarding_overlay
          active={@active}
          current_step={@current_step}
          total_steps={@total_steps}
          can_skip={@can_skip}
        />
        """)

      assert html =~ "Formato de Importação"
      assert html =~ "tipo: conteúdo"
    end

    test "renders correct step content for step 6" do
      assigns = %{active: true, current_step: 6, total_steps: 6, can_skip: true}

      html =
        rendered_to_string(~H"""
        <OnboardingOverlay.onboarding_overlay
          active={@active}
          current_step={@current_step}
          total_steps={@total_steps}
          can_skip={@can_skip}
        />
        """)

      assert html =~ "Conecte outra conta"
      assert html =~ "compartilhar lançamentos"
    end

    test "renders correct step content for all 6 steps" do
      for step <- 1..6 do
        assigns = %{active: true, current_step: step, total_steps: 6, can_skip: true}

        html =
          rendered_to_string(~H"""
          <OnboardingOverlay.onboarding_overlay
            active={@active}
            current_step={@current_step}
            total_steps={@total_steps}
            can_skip={@can_skip}
          />
          """)

        assert html =~ "grid gap-4"
        assert html =~ "data-onboarding-step=\"#{step}\""
      end
    end

    test "shows skip button when can_skip is true" do
      assigns = %{active: true, current_step: 1, total_steps: 6, can_skip: true}

      html =
        rendered_to_string(~H"""
        <OnboardingOverlay.onboarding_overlay
          active={@active}
          current_step={@current_step}
          total_steps={@total_steps}
          can_skip={@can_skip}
        />
        """)

      assert html =~ "onboarding-skip-btn"
      assert html =~ "Pular"
    end

    test "hides skip button when can_skip is false" do
      assigns = %{active: true, current_step: 1, total_steps: 6, can_skip: false}

      html =
        rendered_to_string(~H"""
        <OnboardingOverlay.onboarding_overlay
          active={@active}
          current_step={@current_step}
          total_steps={@total_steps}
          can_skip={@can_skip}
        />
        """)

      refute html =~ "onboarding-skip-btn"
    end

    test "shows previous button when not on first step" do
      assigns = %{active: true, current_step: 2, total_steps: 6, can_skip: true}

      html =
        rendered_to_string(~H"""
        <OnboardingOverlay.onboarding_overlay
          active={@active}
          current_step={@current_step}
          total_steps={@total_steps}
          can_skip={@can_skip}
        />
        """)

      assert html =~ "onboarding-prev-btn"
      assert html =~ "Anterior"
    end

    test "hides previous button on first step" do
      assigns = %{active: true, current_step: 1, total_steps: 6, can_skip: true}

      html =
        rendered_to_string(~H"""
        <OnboardingOverlay.onboarding_overlay
          active={@active}
          current_step={@current_step}
          total_steps={@total_steps}
          can_skip={@can_skip}
        />
        """)

      refute html =~ "onboarding-prev-btn"
    end

    test "shows 'Próximo' button when not on last step" do
      assigns = %{active: true, current_step: 3, total_steps: 6, can_skip: true}

      html =
        rendered_to_string(~H"""
        <OnboardingOverlay.onboarding_overlay
          active={@active}
          current_step={@current_step}
          total_steps={@total_steps}
          can_skip={@can_skip}
        />
        """)

      assert html =~ "Próximo"
    end

    test "shows 'Concluir' button on last step" do
      assigns = %{active: true, current_step: 6, total_steps: 6, can_skip: true}

      html =
        rendered_to_string(~H"""
        <OnboardingOverlay.onboarding_overlay
          active={@active}
          current_step={@current_step}
          total_steps={@total_steps}
          can_skip={@can_skip}
        />
        """)

      assert html =~ "Concluir"
    end

    test "renders progress dots for all steps" do
      assigns = %{active: true, current_step: 3, total_steps: 6, can_skip: true}

      html =
        rendered_to_string(~H"""
        <OnboardingOverlay.onboarding_overlay
          active={@active}
          current_step={@current_step}
          total_steps={@total_steps}
          can_skip={@can_skip}
        />
        """)

      assert html =~ "flex gap-2 mt-6"
      # Should have 6 dots
      assert String.split(html, "rounded-full transition-all duration-200") |> length() == 7
    end

    test "marks current step dot as active" do
      assigns = %{active: true, current_step: 3, total_steps: 6, can_skip: true}

      html =
        rendered_to_string(~H"""
        <OnboardingOverlay.onboarding_overlay
          active={@active}
          current_step={@current_step}
          total_steps={@total_steps}
          can_skip={@can_skip}
        />
        """)

      # The active dot should have the gradient classes
      assert html =~ "from-cyan-400"
    end

    test "includes ARIA attributes for accessibility" do
      assigns = %{active: true, current_step: 1, total_steps: 6, can_skip: true}

      html =
        rendered_to_string(~H"""
        <OnboardingOverlay.onboarding_overlay
          active={@active}
          current_step={@current_step}
          total_steps={@total_steps}
          can_skip={@can_skip}
        />
        """)

      assert html =~ "role=\"dialog\""
      assert html =~ "aria-labelledby=\"onboarding-title\""
      assert html =~ "aria-describedby=\"onboarding-description\""
      assert html =~ "aria-modal=\"true\""
    end
  end
end
