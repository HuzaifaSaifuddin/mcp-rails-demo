require "test_helper"

class SearchProjectsToolTest < ActiveSupport::TestCase
  test "rejects the call when there is no authenticated user" do
    Current.session = nil

    response = SearchProjectsTool.call(message: "Website", server_context: nil)

    assert response.error?
    assert_match(/not authorized/i, response.content.first[:text])
  end

  test "only returns the current user's projects, even when another user's project name matches" do
    Current.session = users(:one).sessions.create!

    response = SearchProjectsTool.call(message: "Website", server_context: nil)

    ids = response.structured_content[:projects].map { |p| p[:id] }
    assert_equal [ projects(:website_redesign).id ], ids
    refute_includes ids, projects(:other_user_website).id
  end

  test "excludes the current user's own archived projects" do
    Current.session = users(:one).sessions.create!

    response = SearchProjectsTool.call(message: "Website", server_context: nil)

    ids = response.structured_content[:projects].map { |p| p[:id] }
    refute_includes ids, projects(:archived_website).id
  end

  test "a blank query returns all of the current user's active projects" do
    Current.session = users(:one).sessions.create!

    response = SearchProjectsTool.call(message: "", server_context: nil)

    ids = response.structured_content[:projects].map { |p| p[:id] }.sort
    expected = [ projects(:website_redesign).id, projects(:mobile_app).id ].sort
    assert_equal expected, ids
  end

  test "returns a structured, explicit representation rather than the raw record" do
    Current.session = users(:one).sessions.create!

    response = SearchProjectsTool.call(message: "Website", server_context: nil)

    project = response.structured_content[:projects].first
    assert_equal %i[id name status], project.keys
  end

  test "returns a friendly message when nothing matches" do
    Current.session = users(:one).sessions.create!

    response = SearchProjectsTool.call(message: "no-such-project", server_context: nil)

    refute response.error?
    assert_equal "No projects found.", response.content.first[:text]
    assert_equal [], response.structured_content[:projects]
  end
end
