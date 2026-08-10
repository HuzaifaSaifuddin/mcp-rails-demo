require "test_helper"

class McpAuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @headers = { "Accept" => "application/json, text/event-stream" }
    @body = { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "0.0.1" } } }
  end

  test "rejects a request with no Authorization header" do
    post "/mcp", params: @body, headers: @headers, as: :json

    assert_response :unauthorized
    assert_equal "Bearer", response.headers["WWW-Authenticate"]
  end

  test "rejects a request with an invalid bearer token" do
    post "/mcp", params: @body, headers: @headers.merge("Authorization" => "Bearer not-a-real-token"), as: :json

    assert_response :unauthorized
  end

  test "rejects a request with a revoked bearer token" do
    token = ApiToken.generate!(user: users(:one))
    token.revoke!

    post "/mcp", params: @body, headers: @headers.merge("Authorization" => "Bearer #{token.plaintext_token}"), as: :json

    assert_response :unauthorized
  end

  test "rejects a non-Bearer authorization scheme" do
    token = ApiToken.generate!(user: users(:one))

    post "/mcp", params: @body, headers: @headers.merge("Authorization" => "Basic #{token.plaintext_token}"), as: :json

    assert_response :unauthorized
  end

  test "allows a request with a valid bearer token and touches last_used_at" do
    token = ApiToken.generate!(user: users(:one))
    assert_nil token.last_used_at

    post "/mcp", params: @body, headers: @headers.merge("Authorization" => "Bearer #{token.plaintext_token}"), as: :json

    assert_response :success
    result = JSON.parse(response.body)["result"]
    assert_equal "mcp-rails-demo", result["serverInfo"]["name"]
    assert token.reload.last_used_at.present?
  end

  test "the token that created a session can keep using it" do
    owner = ApiToken.generate!(user: users(:one))
    session_id = initialize_session(owner)

    post "/mcp", params: ping_body, headers: mcp_headers(owner, session_id), as: :json

    assert_response :success
  end

  test "a different, validly-authenticated token cannot replay another caller's session id" do
    owner = ApiToken.generate!(user: users(:one))
    session_id = initialize_session(owner)

    intruder = ApiToken.generate!(user: users(:two))
    post "/mcp", params: ping_body, headers: mcp_headers(intruder, session_id), as: :json

    assert_response :forbidden
  end

  private

  def initialize_session(token)
    post "/mcp", params: @body, headers: mcp_headers(token), as: :json
    response.headers["mcp-session-id"]
  end

  def ping_body
    { jsonrpc: "2.0", id: 2, method: "ping", params: {} }
  end

  def mcp_headers(token, session_id = nil)
    headers = @headers.merge("Authorization" => "Bearer #{token.plaintext_token}")
    headers["Mcp-Session-Id"] = session_id if session_id
    headers
  end
end
