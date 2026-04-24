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
    test "cards de tarefas exibem labels corretos ao montar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tasks")

      assert has_element?(view, "#task-ops-card-open", "14d")
      assert has_element?(view, "#task-ops-card-total", "14d")
    end

    test "cards de finanças exibem labels corretos ao montar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")

      assert has_element?(view, "#finance-ops-card-total", "30d")
      assert has_element?(view, "#finance-ops-card-balance", "30d")
    end
  end

  describe "atualização dos labels por filtro" do
    test "filtro de tarefas atualiza cards de tarefas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tasks")

      view
      |> form("#task-filters", %{"filters" => %{"days" => "7"}})
      |> render_change()

      assert has_element?(view, "#task-ops-card-open", "7d")
      assert has_element?(view, "#task-ops-card-total", "7d")
    end

    test "filtro de finanças atualiza cards financeiros", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/finances")

      view
      |> form("#finance-filters", %{"filters" => %{"days" => "90"}})
      |> render_change()

      assert has_element?(view, "#finance-ops-card-total", "90d")
      assert has_element?(view, "#finance-ops-card-balance", "90d")
    end
  end

  describe "aria-label dos cards" do
    test "cards têm aria-label descritivo", %{conn: conn} do
      {:ok, _view, tasks_html} = live(conn, ~p"/tasks")
      {:ok, _view, finances_html} = live(conn, ~p"/finances")

      assert tasks_html =~ ~s(aria-label="Tarefas abertas nos últimos 14 dias")
      assert tasks_html =~ ~s(aria-label="Tarefas no filtro nos últimos 14 dias")
      assert finances_html =~ ~s(aria-label="Lançamentos no filtro nos últimos 30 dias")
      assert finances_html =~ ~s(aria-label="Saldo financeiro nos últimos 30 dias")
    end
  end

  describe "propriedades de consistência" do
    property "qualquer days válido de tarefas aparece no label de tarefas", %{conn: conn} do
      check all(days <- StreamData.member_of(["7", "14", "30"])) do
        {:ok, view, _html} = live(conn, ~p"/tasks")

        view
        |> form("#task-filters", %{"filters" => %{"days" => days}})
        |> render_change()

        assert has_element?(view, "#task-ops-card-open", "#{days}d")
        assert has_element?(view, "#task-ops-card-total", "#{days}d")
      end
    end

    property "qualquer days válido de finanças aparece nos labels financeiros", %{conn: conn} do
      check all(days <- StreamData.member_of(["7", "30", "90", "365"])) do
        {:ok, view, _html} = live(conn, ~p"/finances")

        view
        |> form("#finance-filters", %{"filters" => %{"days" => days}})
        |> render_change()

        assert has_element?(view, "#finance-ops-card-total", "#{days}d")
        assert has_element?(view, "#finance-ops-card-balance", "#{days}d")
      end
    end
  end
end
