defmodule OrganizerWeb.ErrorHTMLTest do
  use OrganizerWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    html = render_to_string(OrganizerWeb.ErrorHTML, "404", "html", [])
    assert html =~ "Página não encontrada"
    assert html =~ "Abrir finanças"
  end

  test "renders 500.html" do
    html = render_to_string(OrganizerWeb.ErrorHTML, "500", "html", [])
    assert html =~ "Falha interna temporária"
    assert html =~ "Entrar novamente"
  end
end
