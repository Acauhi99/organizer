defmodule Storybook.Domain.Finance.OperationsPanel do
  use PhoenixStorybook.Story, :component

  alias Flop.Meta
  alias OrganizerWeb.DashboardLive.Components.FinanceOperationsPanel

  def function, do: &FinanceOperationsPanel.finance_operations_panel/1
  def render_source, do: :function
  def container, do: :iframe

  def variations do
    [
      %Variation{
        id: :empty_state,
        description: "Sem lancamentos no periodo",
        attributes: %{
          streams: %{finances: []},
          finance_filters: base_filters(),
          finance_meta: meta_for(1, 1, 0, 10),
          category_suggestions: %{income: [], expense: [], all: []},
          ops_counts: zero_counts(),
          finance_visible_count: 0
        }
      },
      %Variation{
        id: :loaded_state,
        description: "Lista preenchida com paginacao explicita",
        attributes: %{
          streams: %{finances: finance_rows()},
          finance_filters: Map.put(base_filters(), :category, "Moradia"),
          finance_meta: meta_for(2, 4, 34, 10),
          category_suggestions: %{income: ["Salario"], expense: ["Moradia"], all: ["Moradia"]},
          ops_counts: %{
            finances_total: 34,
            finances_income_total: 11,
            finances_expense_total: 23,
            finances_income_cents: 850_000,
            finances_expense_cents: 490_000
          },
          finance_visible_count: 2
        }
      },
      %Variation{
        id: :loading_more,
        description: "Estado de carregamento incremental visivel",
        attributes: %{
          streams: %{finances: finance_rows()},
          finance_filters: base_filters(),
          finance_meta: meta_for(1, 3, 24, 10),
          category_suggestions: %{income: [], expense: [], all: []},
          ops_counts: %{
            finances_total: 24,
            finances_income_total: 8,
            finances_expense_total: 16,
            finances_income_cents: 640_000,
            finances_expense_cents: 370_000
          },
          finance_visible_count: 2,
          finance_loading_more?: true
        }
      }
    ]
  end

  defp finance_rows do
    [
      {"finances-1001",
       %{
         id: 1001,
         kind: :expense,
         expense_profile: :fixed,
         payment_method: :credit,
         installment_number: 3,
         installments_count: 12,
         amount_cents: 159_900,
         category: "Moradia",
         description: "Aluguel",
         occurred_on: Date.utc_today()
       }},
      {"finances-1002",
       %{
         id: 1002,
         kind: :income,
         expense_profile: nil,
         payment_method: :pix,
         installment_number: nil,
         installments_count: nil,
         amount_cents: 420_000,
         category: "Salario",
         description: "Folha mensal",
         occurred_on: Date.add(Date.utc_today(), -1)
       }}
    ]
  end

  defp base_filters do
    %{
      period_mode: "rolling",
      days: "30",
      month: "",
      occurred_on: "",
      occurred_from: "",
      occurred_to: "",
      weekday: "all",
      sort_by: "date_desc",
      kind: "all",
      expense_profile: "all",
      payment_method: "all",
      category: "",
      q: "",
      min_amount_cents: "",
      max_amount_cents: ""
    }
  end

  defp zero_counts do
    %{
      finances_total: 0,
      finances_income_total: 0,
      finances_expense_total: 0,
      finances_income_cents: 0,
      finances_expense_cents: 0
    }
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
