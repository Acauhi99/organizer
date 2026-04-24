defmodule Organizer.DateSupport do
  @moduledoc """
  Shared date formatting/parsing helpers with pt-BR support.
  """

  @type date_value :: Date.t() | String.t() | nil

  @spec parse_date(date_value()) :: {:ok, Date.t()} | :error
  def parse_date(nil), do: :error
  def parse_date(%Date{} = date), do: {:ok, date}

  def parse_date(value) when is_binary(value) do
    cleaned = String.trim(value)

    cond do
      cleaned == "" ->
        :error

      String.contains?(cleaned, "/") ->
        parse_pt_br_date(cleaned)

      true ->
        case Date.from_iso8601(cleaned) do
          {:ok, date} -> {:ok, date}
          _ -> :error
        end
    end
  end

  def parse_date(_value), do: :error

  @spec format_pt_br(Date.t() | nil | any()) :: String.t()
  def format_pt_br(nil), do: ""

  def format_pt_br(%Date{} = date) do
    day = date.day |> Integer.to_string() |> String.pad_leading(2, "0")
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{day}/#{month}/#{date.year}"
  end

  def format_pt_br(_value), do: ""

  @spec parse_month_year(String.t() | nil) :: {:ok, {Date.t(), Date.t()}} | :error
  def parse_month_year(nil), do: :error

  def parse_month_year(value) when is_binary(value) do
    cleaned = String.trim(value)

    case Regex.run(~r/^(\d{2})\/(\d{4})$/, cleaned) do
      [_, month_str, year_str] ->
        with {month, ""} <- Integer.parse(month_str),
             {year, ""} <- Integer.parse(year_str),
             true <- month >= 1 and month <= 12,
             {:ok, start_on} <- Date.new(year, month, 1),
             {:ok, end_on} <- next_month_start(start_on) do
          {:ok, {start_on, Date.add(end_on, -1)}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def parse_month_year(_value), do: :error

  @spec format_month_year(Date.t() | nil | any()) :: String.t()
  def format_month_year(nil), do: ""

  def format_month_year(%Date{} = date) do
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{month}/#{date.year}"
  end

  def format_month_year(_value), do: ""

  defp parse_pt_br_date(value) do
    case String.split(value, "/", parts: 3) do
      [day_str, month_str, year_str] ->
        with {day, ""} <- Integer.parse(day_str),
             {month, ""} <- Integer.parse(month_str),
             {year, ""} <- Integer.parse(year_str),
             {:ok, date} <- Date.new(year, month, day) do
          {:ok, date}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp next_month_start(%Date{year: year, month: 12}) do
    Date.new(year + 1, 1, 1)
  end

  defp next_month_start(%Date{year: year, month: month}) do
    Date.new(year, month + 1, 1)
  end
end
