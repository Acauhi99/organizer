defmodule OrganizerWeb.ErrorHTMLTest do
  use OrganizerWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    html = render_to_string(OrganizerWeb.ErrorHTML, "404", "html", [])
    assert html =~ "Essa página saiu da rota."
    assert html =~ "Voltar para início"
  end

  test "unknown route renders with root layout assets", %{conn: conn} do
    conn = get(conn, "/asda")
    html = html_response(conn, 404)

    assert html =~ ~s(lang="pt-BR")
    assert html =~ "/assets/css/app.css"
    assert html =~ "error-404-page"
  end

  test "renders 500.html" do
    html = render_to_string(OrganizerWeb.ErrorHTML, "500", "html", [])
    assert html =~ "Instabilidade temporária no servidor."
    assert html =~ "Reautenticar sessão"
  end

  test "renders 401.html" do
    html = render_to_string(OrganizerWeb.ErrorHTML, "401", "html", [])
    assert html =~ "Você precisa autenticar sua sessão."
    assert html =~ "Entrar na conta"
  end

  test "renders 403.html" do
    html = render_to_string(OrganizerWeb.ErrorHTML, "403", "html", [])
    assert html =~ "Você não tem permissão para esta ação."
    assert html =~ "Trocar de conta"
  end

  test "renders 422.html" do
    html = render_to_string(OrganizerWeb.ErrorHTML, "422", "html", [])
    assert html =~ "Não foi possível processar essa solicitação."
    assert html =~ "Revisar no início"
  end

  test "renders 503.html" do
    html = render_to_string(OrganizerWeb.ErrorHTML, "503", "html", [])
    assert html =~ "Serviço temporariamente indisponível."
    assert html =~ "Tentar novamente"
  end
end
