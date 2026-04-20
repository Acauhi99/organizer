defmodule OrganizerWeb.DashboardLive.OpsPanelFilterAlignmentTest do
  use OrganizerWeb.ConnCase
  use ExUnitProperties

  import Organizer.AccountsFixtures
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), scope: user_scope_fixture(user)}
  end

  describe "estado inicial dos period labels" do
    test "cards exibem labels corretos ao montar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#ops-card-tasks-open", "14d")
      assert has_element?(view, "#ops-card-tasks-total", "14d")
      assert has_element?(view, "#ops-card-finances-total", "30d")
      assert has_element?(view, "#ops-card-finances-balance", "30d")
    end
  end

  describe "atualização dos labels por filtro" do
    test "filtro de tarefas atualiza apenas cards de tarefas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#task-filters", %{"filters" => %{"days" => "7"}})
      |> render_change()

      assert has_element?(view, "#ops-card-tasks-open", "7d")
      assert has_element?(view, "#ops-card-tasks-total", "7d")
      assert has_element?(view, "#ops-card-finances-total", "30d")
      assert has_element?(view, "#ops-card-finances-balance", "30d")
    end

    test "filtro de finanças atualiza apenas cards financeiros", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#finance-filters", %{"filters" => %{"days" => "90"}})
      |> render_change()

      assert has_element?(view, "#ops-card-finances-total", "90d")
      assert has_element?(view, "#ops-card-finances-balance", "90d")
      assert has_element?(view, "#ops-card-tasks-open", "14d")
      assert has_element?(view, "#ops-card-tasks-total", "14d")
    end
  end

  describe "navegação entre abas preserva labels" do
    test "trocar entre tarefas e finanças mantém os períodos ativos", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      view
      |> form("#task-filters", %{"filters" => %{"days" => "7"}})
      |> render_change()

      view
      |> form("#finance-filters", %{"filters" => %{"days" => "90"}})
      |> render_change()

      view |> element("#ops-tab-finances") |> render_click()
      view |> element("#ops-tab-tasks") |> render_click()

      assert has_element?(view, "#ops-card-tasks-open", "7d")
      assert has_element?(view, "#ops-card-tasks-total", "7d")
      assert has_element?(view, "#ops-card-finances-total", "90d")
      assert has_element?(view, "#ops-card-finances-balance", "90d")
    end
  end

  describe "aria-label dos cards" do
    test "cards têm aria-label descritivo", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ ~s(aria-label="Tarefas abertas nos últimos 14 dias")
      assert html =~ ~s(aria-label="Tarefas no filtro nos últimos 14 dias")
      assert html =~ ~s(aria-label="Lançamentos no filtro nos últimos 30 dias")
      assert html =~ ~s(aria-label="Saldo financeiro nos últimos 30 dias")
    end
  end

  describe "propriedades de consistência" do
    property "qualquer days válido de tarefas aparece no label de tarefas", %{conn: conn} do
      check all(days <- StreamData.member_of(["7", "14", "30"])) do
        {:ok, view, _html} = live(conn, ~p"/dashboard")

        view
        |> form("#task-filters", %{"filters" => %{"days" => days}})
        |> render_change()

        assert has_element?(view, "#ops-card-tasks-open", "#{days}d")
        assert has_element?(view, "#ops-card-tasks-total", "#{days}d")
      end
    end

    property "qualquer days válido de finanças aparece nos labels financeiros", %{conn: conn} do
      check all(days <- StreamData.member_of(["7", "30", "90"])) do
        {:ok, view, _html} = live(conn, ~p"/dashboard")

        view
        |> form("#finance-filters", %{"filters" => %{"days" => days}})
        |> render_change()

        assert has_element?(view, "#ops-card-finances-total", "#{days}d")
        assert has_element?(view, "#ops-card-finances-balance", "#{days}d")
      end
    end
  end
end
