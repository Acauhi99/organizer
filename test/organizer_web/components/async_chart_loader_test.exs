defmodule OrganizerWeb.Components.AsyncChartLoaderTest do
  use OrganizerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Phoenix.Component
  alias OrganizerWeb.Components.AsyncChartLoader

  describe "async_chart_loader/1" do
    test "renders loading skeleton when loading is true" do
      assigns = %{chart_id: "test-chart", chart_type: :progress, loading: true, chart_svg: nil}

      html =
        rendered_to_string(~H"""
        <AsyncChartLoader.async_chart_loader
          chart_id={@chart_id}
          chart_type={@chart_type}
          loading={@loading}
          chart_svg={@chart_svg}
        />
        """)

      assert html =~ "test-chart"
      assert html =~ "grid gap-3 p-4"
      assert html =~ "skeleton-bar"
    end

    test "renders chart when loaded and chart_svg is present" do
      chart_svg = "<svg>test chart</svg>"

      assigns = %{
        chart_id: "test-chart",
        chart_type: :progress,
        loading: false,
        chart_svg: chart_svg
      }

      html =
        rendered_to_string(~H"""
        <AsyncChartLoader.async_chart_loader
          chart_id={@chart_id}
          chart_type={@chart_type}
          loading={@loading}
          chart_svg={@chart_svg}
        />
        """)

      assert html =~ "test-chart"
      assert html =~ "contex-plot"
      assert html =~ "test chart"
    end

    test "renders empty state when loaded but no chart_svg" do
      assigns = %{chart_id: "test-chart", chart_type: :progress, loading: false, chart_svg: nil}

      html =
        rendered_to_string(~H"""
        <AsyncChartLoader.async_chart_loader
          chart_id={@chart_id}
          chart_type={@chart_type}
          loading={@loading}
          chart_svg={@chart_svg}
        />
        """)

      assert html =~ "test-chart"
      assert html =~ "border-dashed"
      assert html =~ "Dados insuficientes"
    end

    test "does not render skeleton when not loading" do
      assigns = %{chart_id: "test-chart", chart_type: :progress, loading: false, chart_svg: nil}

      html =
        rendered_to_string(~H"""
        <AsyncChartLoader.async_chart_loader
          chart_id={@chart_id}
          chart_type={@chart_type}
          loading={@loading}
          chart_svg={@chart_svg}
        />
        """)

      refute html =~ "grid gap-3 p-4"
    end

    test "does not render chart when loading" do
      chart_svg = "<svg>test chart</svg>"

      assigns = %{
        chart_id: "test-chart",
        chart_type: :progress,
        loading: true,
        chart_svg: chart_svg
      }

      html =
        rendered_to_string(~H"""
        <AsyncChartLoader.async_chart_loader
          chart_id={@chart_id}
          chart_type={@chart_type}
          loading={@loading}
          chart_svg={@chart_svg}
        />
        """)

      refute html =~ "contex-plot"
      refute html =~ "test chart"
    end

    test "renders with custom chart_id" do
      assigns = %{
        chart_id: "custom-chart-123",
        chart_type: :finance_trend,
        loading: true,
        chart_svg: nil
      }

      html =
        rendered_to_string(~H"""
        <AsyncChartLoader.async_chart_loader
          chart_id={@chart_id}
          chart_type={@chart_type}
          loading={@loading}
          chart_svg={@chart_svg}
        />
        """)

      assert html =~ "custom-chart-123"
    end
  end
end
