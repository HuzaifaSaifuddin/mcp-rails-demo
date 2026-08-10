#!/usr/bin/env ruby
# frozen_string_literal: true

# A minimal, standalone MCP client - no Rails, no gem dependency beyond the
# stdlib - that drives the app's /mcp endpoint over real Streamable HTTP to
# prove the full stack works end to end: client -> HTTP -> Rails -> MCP
# server -> search_projects/project resource -> Rails scopes -> ActiveRecord
# -> the real database, plus the auth/authorization/invalid-input paths.
#
# Usage:
#   BASE_URL=http://127.0.0.1:3099 TOKEN=<bearer token> \
#     OWN_PROJECT_NAME_FRAGMENT=Website OTHER_PROJECT_ID=4 \
#     ruby script/mcp_client_demo.rb

require "net/http"
require "uri"
require "json"

BASE_URL = ENV.fetch("BASE_URL", "http://127.0.0.1:3099")
TOKEN = ENV.fetch("TOKEN")
OWN_PROJECT_NAME_FRAGMENT = ENV.fetch("OWN_PROJECT_NAME_FRAGMENT", "Website")
OTHER_PROJECT_ID = Integer(ENV.fetch("OTHER_PROJECT_ID"))

class McpClient
  attr_reader :session_id

  def initialize(base_url:, token:)
    @uri = URI.join(base_url, "/mcp")
    @token = token
    @next_id = 0
    @session_id = nil
  end

  def call(method, params = {}, auth: true)
    @next_id += 1
    body = { jsonrpc: "2.0", id: @next_id, method: method, params: params }

    request = Net::HTTP::Post.new(@uri)
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json, text/event-stream"
    request["Authorization"] = "Bearer #{@token}" if auth
    request["Mcp-Session-Id"] = @session_id if @session_id
    request.body = JSON.generate(body)

    response = Net::HTTP.start(@uri.host, @uri.port) { |http| http.request(request) }

    @session_id ||= response["Mcp-Session-Id"]

    [ response, parse_rpc_body(response) ]
  end

  private

  # The transport may answer with a single application/json body, or with
  # text/event-stream framing (one or more "data: <json>" lines) - a real
  # client has to handle both.
  def parse_rpc_body(response)
    return nil if response.body.nil? || response.body.empty?

    if response["Content-Type"].to_s.include?("text/event-stream")
      data_lines = response.body.each_line.select { |line| line.start_with?("data: ") }
      JSON.parse(data_lines.last.delete_prefix("data: ")) if data_lines.any?
    else
      JSON.parse(response.body)
    end
  end
end

def check(description)
  print "#{description}... "
  ok, detail = yield
  puts ok ? "PASS" : "FAIL - #{detail}"
  ok
end

results = []
client = McpClient.new(base_url: BASE_URL, token: TOKEN)

results << check("1. initialize the MCP connection") do
  response, body = client.call("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "mcp_client_demo", version: "0.0.1" } })
  ok = response.code == "200" && body.dig("result", "serverInfo", "name") == "mcp-rails-demo" && client.session_id
  [ ok, body.inspect ]
end

results << check("2. discover the search_projects tool and project resource template") do
  _, tools_body = client.call("tools/list")
  _, templates_body = client.call("resources/templates/list")
  tool_names = tools_body.dig("result", "tools")&.map { |t| t["name"] }
  template_uris = templates_body.dig("result", "resourceTemplates")&.map { |t| t["uriTemplate"] }
  ok = tool_names&.include?("search_projects") && template_uris&.include?("project://{id}")
  [ ok, "tools=#{tool_names.inspect} templates=#{template_uris.inspect}" ]
end

discovered_project_id = nil
results << check("3. call search_projects and get real data back") do
  _, body = client.call("tools/call", { name: "search_projects", arguments: { message: OWN_PROJECT_NAME_FRAGMENT } })
  result = body["result"]
  projects = result&.dig("structuredContent", "projects")
  discovered_project_id = projects&.first&.dig("id")
  ok = result && result["isError"] == false && projects&.any? { |p| p["name"].include?(OWN_PROJECT_NAME_FRAGMENT) }
  [ ok, body.inspect ]
end

results << check("4. read a real project://<id> resource for a project search just found") do
  _, body = client.call("resources/read", { uri: "project://#{discovered_project_id}" })
  contents = body.dig("result", "contents", 0)
  payload = contents && JSON.parse(contents["text"])
  ok = payload && payload["id"] == discovered_project_id
  [ ok, body.inspect ]
end

results << check("5. verify authentication - no credentials are rejected") do
  response, _ = client.call("tools/list", {}, auth: false)
  [ response.code == "401", "status=#{response.code}" ]
end

results << check("6. verify authorization - another user's project is not found, not leaked") do
  _, body = client.call("resources/read", { uri: "project://#{OTHER_PROJECT_ID}" })
  error = body["error"]
  ok = error && error["code"] == -32602 && error["message"].include?("not found")
  [ ok, body.inspect ]
end

results << check("7. verify invalid input handling - missing required tool argument") do
  _, body = client.call("tools/call", { name: "search_projects", arguments: {} })
  result = body["result"]
  ok = result && result["isError"] == true && result.dig("content", 0, "text").to_s.include?("Missing required")
  [ ok, body.inspect ]
end

puts
if results.all?
  puts "All #{results.size} Stage 8 checks passed."
  exit 0
else
  puts "#{results.count(false)} of #{results.size} checks FAILED."
  exit 1
end
