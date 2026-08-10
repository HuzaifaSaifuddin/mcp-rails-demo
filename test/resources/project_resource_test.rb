require "test_helper"

class ProjectResourceTest < ActiveSupport::TestCase
  test "returns the project when the current user owns it" do
    Current.session = users(:one).sessions.create!
    project = projects(:website_redesign)

    result = ProjectResource.contents(id: project.id, server_context: nil)

    assert_instance_of MCP::Resource::TextContents, result
    assert_equal "project://#{project.id}", result.uri
    assert_equal "application/json", result.mime_type

    payload = JSON.parse(result.text)
    assert_equal project.id, payload["id"]
    assert_equal project.name, payload["name"]
    assert_equal project.description, payload["description"]
    assert_equal project.status, payload["status"]
  end

  test "returns only the explicit public fields, not the raw record" do
    Current.session = users(:one).sessions.create!
    project = projects(:website_redesign)

    result = ProjectResource.contents(id: project.id, server_context: nil)
    payload = JSON.parse(result.text)

    assert_equal %w[id name description status], payload.keys
  end

  test "raises resource not found for another user's project" do
    Current.session = users(:one).sessions.create!
    other_project = projects(:other_user_website)

    error = assert_raises(MCP::Server::ResourceNotFoundError) do
      ProjectResource.contents(id: other_project.id, server_context: nil)
    end
    assert_equal "project://#{other_project.id}", error.error_data[:uri]
  end

  test "raises resource not found for a project id that does not exist" do
    Current.session = users(:one).sessions.create!

    assert_raises(MCP::Server::ResourceNotFoundError) do
      ProjectResource.contents(id: 0, server_context: nil)
    end
  end

  test "raises resource not found when there is no authenticated user" do
    Current.session = nil
    project = projects(:website_redesign)

    assert_raises(MCP::Server::ResourceNotFoundError) do
      ProjectResource.contents(id: project.id, server_context: nil)
    end
  end

  test "an owner can still read their own archived project by id" do
    Current.session = users(:one).sessions.create!
    archived = projects(:archived_website)

    result = ProjectResource.contents(id: archived.id, server_context: nil)

    payload = JSON.parse(result.text)
    assert_equal "archived", payload["status"]
  end
end
