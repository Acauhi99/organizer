defmodule OrganizerWeb.Storybook do
  use PhoenixStorybook,
    otp_app: :organizer,
    content_path: Path.expand("../../storybook", __DIR__),
    css_path: "/assets/css/app.css",
    js_path: "/assets/js/app.js"
end
