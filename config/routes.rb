Rails.application.routes.draw do
  root "projects#index"

  resource :session
  resource :registration, only: %i[new create]
  resources :passwords, param: :token

  resources :projects do
    resources :tasks, shallow: true
  end

  get "up" => "rails/health#show", as: :rails_health_check

  mcp_server = MCP::Server.new(
    name: "mcp-rails-demo",
    version: "1.0.0",
    tools: [ SearchProjectsTool ],
    resource_templates: [ ProjectResource ]
  )

  mcp_transport = MCP::Server::Transports::StreamableHTTPTransport.new(
    mcp_server
  )

  mount mcp_transport => "/mcp"
end
