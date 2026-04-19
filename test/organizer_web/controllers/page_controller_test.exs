defmodule OrganizerWeb.PageControllerTest do
  use OrganizerWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~
             "Cole dados no chat copy/paste"
  end
end
