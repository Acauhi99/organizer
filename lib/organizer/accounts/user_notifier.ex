defmodule Organizer.Accounts.UserNotifier do
  require Logger

  import Swoosh.Email

  alias Organizer.Mailer

  # Delivers the email using the application mailer.
  # Returns {:ok, email} on success or logs and returns {:ok, email} on failure
  # to prevent cascading failures while keeping the return shape consistent.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Organizer", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        {:ok, email}

      {:error, reason} ->
        Logger.warning("Failed to deliver email to #{recipient}: #{inspect(reason)}")

        {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Instruções para alterar e-mail", """

    ==============================

    Olá #{user.email},

    Você pode alterar seu e-mail acessando a URL abaixo:

    #{url}

    Se você não solicitou essa alteração, ignore este e-mail.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Instruções para redefinir senha", """

    ==============================

    Olá #{user.email},

    Você pode redefinir sua senha acessando a URL abaixo:

    #{url}

    Se você não solicitou este e-mail, ignore esta mensagem.

    ==============================
    """)
  end
end
