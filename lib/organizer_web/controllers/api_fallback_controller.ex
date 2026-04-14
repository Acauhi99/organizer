defmodule OrganizerWeb.ApiFallbackController do
  use OrganizerWeb, :controller

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: "unauthorized", message: "authentication required"}})
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{code: "not_found", message: "resource not found"}})
  end

  def call(conn, {:error, {:validation, details}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "validation_error", details: details}})
  end

  def call(conn, {:error, _reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: %{code: "internal_error", message: "internal server error"}})
  end
end
