defmodule Storybook.Core.Pagination do
  use PhoenixStorybook.Story, :component

  alias Flop.Meta

  def function, do: &OrganizerWeb.CoreComponents.pagination/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :single_page,
        description: "Paginacao com poucos resultados",
        attributes: %{
          meta: meta_for(1, 1, 8, 10),
          path: "/dev/storybook"
        }
      },
      %Variation{
        id: :middle_page,
        description: "Paginacao em lista longa (pagina intermediaria)",
        attributes: %{
          meta: meta_for(4, 9, 86, 10),
          path: "/dev/storybook"
        }
      },
      %Variation{
        id: :last_page,
        description: "Paginacao no fim da lista",
        attributes: %{
          meta: meta_for(9, 9, 86, 10),
          path: "/dev/storybook"
        }
      }
    ]
  end

  defp meta_for(current_page, total_pages, total_count, page_size) do
    %Meta{
      current_page: current_page,
      current_offset: (current_page - 1) * page_size,
      total_pages: total_pages,
      total_count: total_count,
      page_size: page_size,
      previous_page: if(current_page > 1, do: current_page - 1, else: nil),
      next_page: if(current_page < total_pages, do: current_page + 1, else: nil),
      has_previous_page?: current_page > 1,
      has_next_page?: current_page < total_pages
    }
  end
end
