class ProjectResource < MCP::ResourceTemplate
  resource_template_name "project"
  uri_template "project://{id}"

  def self.contents(id:, server_context:)
    raise MCP::Server::ResourceNotFoundError.new("project://#{id}") if Current.user.nil?

    project = Current.user.projects.find(id)

    MCP::Resource::TextContents.new(
      text: JSON.generate(
        id: project.id,
        name: project.name,
        description: project.description,
        status: project.status
      ),
      uri: "project://#{id}",
      mime_type: "application/json"
    )
  rescue ActiveRecord::RecordNotFound
    raise MCP::Server::ResourceNotFoundError.new("project://#{id}")
  end
end
