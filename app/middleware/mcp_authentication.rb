class McpAuthentication
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    api_token = ApiToken.authenticate(bearer_token(request))

    if api_token
      api_token.touch(:last_used_at)
      Current.api_token = api_token

      status, headers, body = @app.call(env)
      # A new Mcp-Session-Id in the response means this request just created
      # the session (only handle_initialization sets this header) - record
      # who owns it so session_request_validator can enforce that later.
      if (session_id = headers["mcp-session-id"])
        McpSessionOwnership.remember(session_id, api_token.id)
      end
      [ status, headers, body ]
    else
      unauthorized_response
    end
  end

  private

  def bearer_token(request)
    scheme, token = request.get_header("HTTP_AUTHORIZATION")&.split(" ", 2)
    token if scheme&.casecmp?("Bearer")
  end

  def unauthorized_response
    body = { error: "unauthorized" }.to_json
    [
      401,
      { "Content-Type" => "application/json", "Content-Length" => body.bytesize.to_s, "WWW-Authenticate" => "Bearer" },
      [ body ]
    ]
  end
end
