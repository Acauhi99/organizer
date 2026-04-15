defmodule Organizer.Accounts.UserNotifier do
  import Swoosh.Email

  alias Organizer.Mailer
  alias Organizer.Accounts.User

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Organizer", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
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
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Instruções de acesso", """

    ==============================

    Olá #{user.email},

    Você pode entrar na sua conta acessando a URL abaixo:

    #{url}

    Se você não solicitou este e-mail, ignore esta mensagem.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Instruções de confirmação", """

    ==============================

    Olá #{user.email},

    Você pode confirmar sua conta acessando a URL abaixo:

    #{url}

    Se você não criou uma conta conosco, ignore esta mensagem.

    ==============================
    """)
  end
end
