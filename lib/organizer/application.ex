defmodule Organizer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      OrganizerWeb.Telemetry,
      Organizer.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:organizer, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:organizer, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Organizer.PubSub},
      # Task supervisor for async work (email delivery, etc.)
      {Task.Supervisor, name: Organizer.TaskSupervisor},
      # Analytics cache: GenServer + ETS for read-through caching
      {Organizer.Planning.AnalyticsCache, []},
      # Start a worker by calling: Organizer.Worker.start_link(arg)
      # {Organizer.Worker, arg},
      # Start to serve requests, typically the last entry
      OrganizerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Organizer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OrganizerWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
