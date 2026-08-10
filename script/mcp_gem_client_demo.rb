#!/usr/bin/env ruby
# frozen_string_literal: true

# Unlike script/mcp_client_demo.rb (raw Net::HTTP, representing "any external
# client"), this uses the mcp gem's own client SDK - MCP::Client::HTTP as the
# transport, MCP::Client as the protocol layer - the same gem this whole app
# uses to build the *server* side, just the other half of it.
#
# Usage:
#   BASE_URL=http://localhost:3000 TOKEN=<bearer token> ruby script/mcp_gem_client_demo.rb

require "mcp"

BASE_URL = ENV.fetch("BASE_URL", "http://localhost:3000")
TOKEN = ENV.fetch("TOKEN")

transport = MCP::Client::HTTP.new(
  url: "#{BASE_URL}/mcp",
  headers: { "Authorization" => "Bearer #{TOKEN}" }
)
client = MCP::Client.new(transport: transport)

# Registers a handler for a server-initiated request - the half of the
# protocol script/mcp_client_demo.rb never touches. Our server never sends
# `elicitation/create` (nothing in SearchProjectsTool/ProjectResource asks the
# client for input), so this never actually fires against this app - it's
# here to show the mechanism exists and how a client would answer it.
# (MCP::Client#on_sampling also exists, but sampling/createMessage is
# deprecated as of protocol version 2026-07-28 per SEP-2577, so this uses
# elicitation instead.)
client.on_elicitation do |params|
  puts "  [server asked the client for input: #{params.inspect}]"
  { action: "decline" }
end

puts "=== connect (initialize handshake) ==="
init_result = client.connect(client_info: { name: "mcp_gem_client_demo", version: "0.0.1" }, capabilities: {})
puts "server: #{init_result["serverInfo"]["name"]} v#{init_result["serverInfo"]["version"]}, protocol #{init_result["protocolVersion"]}"

puts "\n=== list_tools ==="
tools = client.list_tools
tools.tools.each { |tool| puts "- #{tool.name}: #{tool.description}" }

puts "\n=== call_tool search_projects ==="
result = client.call_tool(name: "search_projects", arguments: { message: "Website" })
puts result.inspect

puts "\n=== read_resource project://1 ==="
contents = client.read_resource(uri: "project://1")
puts contents.inspect

puts "\n=== read_resource project://4 (another user's project) - expect a raised ServerError ==="
begin
  client.read_resource(uri: "project://4")
  puts "BUG: should have raised"
rescue MCP::Client::ServerError => e
  puts "raised MCP::Client::ServerError as expected: code=#{e.code} message=#{e.message.inspect}"
end

puts "\n=== call_tool search_projects with a missing required argument ==="
puts "(this is a tool-level failure, not a protocol error - the gem returns it normally, isError: true, rather than raising)"
result = client.call_tool(name: "search_projects", arguments: {})
puts result.inspect
