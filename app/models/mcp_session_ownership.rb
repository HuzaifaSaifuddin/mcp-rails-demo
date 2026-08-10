# Tracks which ApiToken established each MCP session, so
# StreamableHTTPTransport's session_request_validator can reject a request
# that presents a valid bearer token but a session id it didn't create -
# e.g. a leaked Mcp-Session-Id replayed by a different caller.
#
# In-memory and process-local by design, matching StreamableHTTPTransport's
# own session storage: sessions don't survive a restart or exist outside
# this process, so neither should the record of who owns them.
class McpSessionOwnership
  MUTEX = Mutex.new
  OWNERS = {}
  private_constant :MUTEX, :OWNERS

  class << self
    def remember(session_id, api_token_id)
      MUTEX.synchronize { OWNERS[session_id] = api_token_id }
    end

    def owned_by?(session_id, api_token_id)
      MUTEX.synchronize { OWNERS[session_id] } == api_token_id
    end
  end
end
