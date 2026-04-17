defmodule OrganizerWeb.DashboardLive.OpsPanelFilterAlignmentTest do
  use OrganizerWeb.ConnCase
  use ExUnitProperties

  import Organizer.AccountsFixtures
  import Phoenix.LiveViewTest

  # ---------------------------------------------------------------------------
  # Setup
  # ---------------------------------------------------------------------------

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), scope: user_scope_fixture(user)}
  end

  # ---------------------------------------------------------------------------
  # Task 4.2 — Estado inicial dos Period_Labels
  # ---------------------------------------------------------------------------

  describe "estado inicial dos Period_Labels" do
    test "cards exibem labels de período corretos ao montar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#ops-card-tasks-open", "14d")
      assert has_element?(view, "#ops-card-tasks-total", "14d")
      assert has_element?(view, "#ops-card-finances-total", "30d")
      assert has_element?(view, "#ops-card-goals-active", "365d")
    end
  end

  # ---------------------------------------------------------------------------
  # Task 4.3 — Atualização de label ao mudar filtro de tarefas
  # ---------------------------------------------------------------------------

  describe "atualização de label ao mudar filtro de tarefas" do
    test "cards de tarefas refletem novo valor de days", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#task-filters", %{"filters" => %{"days" => "7"}})
      |> render_change()

      assert has_element?(view, "#ops-card-tasks-open", "7d")
      assert has_element?(view, "#ops-card-tasks-total", "7d")
    end

    test "card de lançamentos não é afetado ao mudar filtro de tarefas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#task-filters", %{"filters" => %{"days" => "7"}})
      |> render_change()

      assert has_element?(view, "#ops-card-finances-total", "30d")
    end
  end

  # ---------------------------------------------------------------------------
  # Task 4.4 — Atualização de label ao mudar filtro de finanças
  # ---------------------------------------------------------------------------

  describe "atualização de label ao mudar filtro de finanças" do
    test "card de lançamentos reflete novo valor de days", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#finance-filters", %{"filters" => %{"days" => "90"}})
      |> render_change()

      assert has_element?(view, "#ops-card-finances-total", "90d")
    end

    test "cards de tarefas não são afetados ao mudar filtro de finanças", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#finance-filters", %{"filters" => %{"days" => "90"}})
      |> render_change()

      assert has_element?(view, "#ops-card-tasks-open", "14d")
      assert has_element?(view, "#ops-card-tasks-total", "14d")
    end
  end

  # ---------------------------------------------------------------------------
  # Task 4.5 — Isolamento entre abas
  # ---------------------------------------------------------------------------

  describe "isolamento entre filtros de abas distintas" do
    test "mudar filtro de tarefas não altera label de metas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#task-filters", %{"filters" => %{"days" => "30"}})
      |> render_change()

      assert has_element?(view, "#ops-card-goals-active", "365d")
    end

    test "mudar filtro de finanças não altera label de metas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#finance-filters", %{"filters" => %{"days" => "7"}})
      |> render_change()

      assert has_element?(view, "#ops-card-goals-active", "365d")
    end

    test "mudar filtro de metas não altera labels de tarefas e finanças", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#goal-filters", %{"filters" => %{"days" => "90"}})
      |> render_change()

      assert has_element?(view, "#ops-card-tasks-open", "14d")
      assert has_element?(view, "#ops-card-tasks-total", "14d")
      assert has_element?(view, "#ops-card-finances-total", "30d")
    end
  end

  # ---------------------------------------------------------------------------
  # Task 4.6 — Preservação de labels ao navegar entre abas
  # ---------------------------------------------------------------------------

  describe "navegação entre abas preserva Period_Labels" do
    test "trocar de aba não recalcula filtros nem labels", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # Mudar filtro de tarefas para valor conhecido
      view
      |> form("#task-filters", %{"filters" => %{"days" => "7"}})
      |> render_change()

      # Navegar para aba de finanças
      view |> element("#ops-tab-finances") |> render_click()

      # Labels devem permanecer inalterados
      assert has_element?(view, "#ops-card-tasks-open", "7d")
      assert has_element?(view, "#ops-card-tasks-total", "7d")
      assert has_element?(view, "#ops-card-finances-total", "30d")

      # Voltar para aba de tarefas
      view |> element("#ops-tab-tasks") |> render_click()

      assert has_element?(view, "#ops-card-tasks-open", "7d")
    end
  end

  # ---------------------------------------------------------------------------
  # Task 4.7 — aria-label nos cards
  # ---------------------------------------------------------------------------

  describe "acessibilidade: aria-label nos cards" do
    test "cards têm aria-label descritivo com período no estado inicial", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ ~s(aria-label="Tarefas abertas nos últimos 14 dias")
      assert html =~ ~s(aria-label="Tarefas no filtro nos últimos 14 dias")
      assert html =~ ~s(aria-label="Lançamentos no filtro nos últimos 30 dias")
      assert html =~ ~s(aria-label="Metas ativas nos próximos 365 dias")
    end

    test "aria-label do card de tarefas atualiza ao mudar filtro", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#task-filters", %{"filters" => %{"days" => "30"}})
      |> render_change()

      html = render(view)
      assert html =~ ~s(aria-label="Tarefas abertas nos últimos 30 dias")
    end
  end

  # ---------------------------------------------------------------------------
  # Task 4.8 — Property 1: Period_Label de tarefas reflete o filtro ativo
  # Feature: ops-panel-filter-alignment, Property 1: Period_Label de tarefas reflete o filtro ativo
  # Validates: Requirements 1.2, 1.5
  # ---------------------------------------------------------------------------

  describe "Property 1: Period_Label de tarefas reflete o filtro ativo" do
    property "para qualquer days válido, cards de tarefas exibem o label correto", %{conn: conn} do
      check all days <- StreamData.member_of(["7", "14", "30"]) do
        {:ok, view, _html} = live(conn, ~p"/dashboard")

        view
        |> form("#task-filters", %{"filters" => %{"days" => days}})
        |> render_change()

        assert has_element?(view, "#ops-card-tasks-open", "#{days}d")
        assert has_element?(view, "#ops-card-tasks-total", "#{days}d")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Task 4.9 — Property 2: Period_Label de finanças reflete o filtro ativo
  # Feature: ops-panel-filter-alignment, Property 2: Period_Label de finanças reflete o filtro ativo
  # Validates: Requirements 1.3, 1.5
  # ---------------------------------------------------------------------------

  describe "Property 2: Period_Label de finanças reflete o filtro ativo" do
    property "para qualquer days válido, card de lançamentos exibe o label correto", %{
      conn: conn
    } do
      check all days <- StreamData.member_of(["7", "30", "90"]) do
        {:ok, view, _html} = live(conn, ~p"/dashboard")

        view
        |> form("#finance-filters", %{"filters" => %{"days" => days}})
        |> render_change()

        assert has_element?(view, "#ops-card-finances-total", "#{days}d")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Task 4.10 — Property 3: Isolamento entre Period_Labels de abas distintas
  # Feature: ops-panel-filter-alignment, Property 3: Isolamento entre Period_Labels de abas distintas
  # Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6
  # ---------------------------------------------------------------------------

  describe "Property 3: Isolamento entre Period_Labels de abas distintas" do
    property "atualizar filtro de tarefas não altera label de finanças", %{conn: conn} do
      check all task_days <- StreamData.member_of(["7", "14", "30"]),
                finance_days <- StreamData.member_of(["7", "30", "90"]) do
        {:ok, view, _html} = live(conn, ~p"/dashboard")

        # Setar filtro de finanças primeiro
        view
        |> form("#finance-filters", %{"filters" => %{"days" => finance_days}})
        |> render_change()

        # Mudar filtro de tarefas
        view
        |> form("#task-filters", %{"filters" => %{"days" => task_days}})
        |> render_change()

        # Label de finanças deve ser preservado
        assert has_element?(view, "#ops-card-finances-total", "#{finance_days}d")
      end
    end

    property "atualizar filtro de finanças não altera labels de tarefas", %{conn: conn} do
      check all task_days <- StreamData.member_of(["7", "14", "30"]),
                finance_days <- StreamData.member_of(["7", "30", "90"]) do
        {:ok, view, _html} = live(conn, ~p"/dashboard")

        # Setar filtro de tarefas primeiro
        view
        |> form("#task-filters", %{"filters" => %{"days" => task_days}})
        |> render_change()

        # Mudar filtro de finanças
        view
        |> form("#finance-filters", %{"filters" => %{"days" => finance_days}})
        |> render_change()

        # Labels de tarefas devem ser preservados
        assert has_element?(view, "#ops-card-tasks-open", "#{task_days}d")
        assert has_element?(view, "#ops-card-tasks-total", "#{task_days}d")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Task 2.2 — Property 4: Sanitização de Goal_Filters.days
  # Feature: ops-panel-filter-alignment, Property 4: Sanitização de Goal_Filters.days
  # Validates: Requirements 4.1, 4.2, 4.3
  # ---------------------------------------------------------------------------

  describe "Property 4: Sanitização de Goal_Filters.days" do
    property "valores entre 1 e 3650 são exibidos corretamente no card de metas", %{conn: conn} do
      check all n <- StreamData.integer(1..3650) do
        {:ok, view, _html} = live(conn, ~p"/dashboard")

        view
        |> form("#goal-filters", %{"filters" => %{"days" => to_string(n)}})
        |> render_change()

        assert has_element?(view, "#ops-card-goals-active", "#{n}d")
      end
    end

    property "valores fora de 1..3650 fazem fallback para 365d no card de metas", %{conn: conn} do
      check all n <- StreamData.filter(StreamData.integer(), fn x -> x < 1 or x > 3650 end) do
        {:ok, view, _html} = live(conn, ~p"/dashboard")

        view
        |> form("#goal-filters", %{"filters" => %{"days" => to_string(n)}})
        |> render_change()

        assert has_element?(view, "#ops-card-goals-active", "365d")
      end
    end

    test "string não numérica faz fallback para 365d no card de metas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#goal-filters", %{"filters" => %{"days" => "abc"}})
      |> render_change()

      assert has_element?(view, "#ops-card-goals-active", "365d")
    end
  end
end
