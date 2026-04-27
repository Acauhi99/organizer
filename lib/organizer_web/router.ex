defmodule OrganizerWeb.Router do
  use OrganizerWeb, :router

  import OrganizerWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {OrganizerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :put_secure_browser_headers
    plug :fetch_session
    plug :fetch_current_scope_for_user
  end

  scope "/", OrganizerWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/account-links/accept/:token", AccountLinkController, :accept
  end

  scope "/", OrganizerWeb do
    pipe_through :browser

    live_session :authenticated, on_mount: {OrganizerWeb.UserAuth, :authenticated} do
      live "/finances", DashboardLive, :finances
      live "/tasks", DashboardLive, :tasks
      live "/account-links", AccountLinkLive, :index
      live "/account-links/invite", AccountLinkLive, :new_invite
      live "/account-links/:link_id", SharedFinanceLive, :show
      live "/account-links/:link_id/settlement", SettlementLive, :show
    end
  end

  scope "/api/v1", OrganizerWeb.API.V1 do
    pipe_through [:api, :require_authenticated_api_user]

    get "/tasks", TaskController, :index
    post "/tasks", TaskController, :create
    get "/tasks/:id", TaskController, :show
    put "/tasks/:id", TaskController, :update
    delete "/tasks/:id", TaskController, :delete

    get "/finance-entries", FinanceEntryController, :index
    post "/finance-entries", FinanceEntryController, :create
    get "/finance-entries/:id", FinanceEntryController, :show
    put "/finance-entries/:id", FinanceEntryController, :update
    delete "/finance-entries/:id", FinanceEntryController, :delete

    get "/fixed-costs", FixedCostController, :index
    post "/fixed-costs", FixedCostController, :create
    get "/fixed-costs/:id", FixedCostController, :show
    put "/fixed-costs/:id", FixedCostController, :update
    delete "/fixed-costs/:id", FixedCostController, :delete

    get "/important-dates", ImportantDateController, :index
    post "/important-dates", ImportantDateController, :create
    get "/important-dates/:id", ImportantDateController, :show
    put "/important-dates/:id", ImportantDateController, :update
    delete "/important-dates/:id", ImportantDateController, :delete
  end

  # Other scopes may use custom stacks.
  # scope "/api", OrganizerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:organizer, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/finances", metrics: OrganizerWeb.Telemetry
    end
  end

  ## Authentication routes

  scope "/", OrganizerWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", OrganizerWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
  end

  scope "/", OrganizerWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    post "/users/log-in", UserSessionController, :create
    get "/users/auth/google", UserGoogleOAuthController, :request
    get "/users/auth/google/callback", UserGoogleOAuthController, :callback
    delete "/users/log-out", UserSessionController, :delete
  end
end
