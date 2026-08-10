class SearchProjectsTool < MCP::Tool
  tool_name "search_projects"
  title "Search Projects"
  description "Search the current user's projects by name"

  input_schema(
    properties: {
      message: { type: "string", description: "Project name to search for" }
    },
    required: [ "message" ]
  )

  def self.call(message:, server_context:)
    user = Current.user

    return MCP::Tool::Response.new(
      [ { type: "text", text: "Not authorized: no authenticated user." } ],
      error: true
    ) if user.nil?

    projects = user.projects
                   .active
                   .search(message)
                   .limit(20)

    data = projects.map do |project|
      {
        id: project.id,
        name: project.name,
        status: project.status
      }
    end

    MCP::Tool::Response.new(
      [ { type: "text", text: data.map { |p| "#{p[:id]}: #{p[:name]}" }.join("\n").presence || "No projects found." } ],
      structured_content: { projects: data }
    )
  end
end
