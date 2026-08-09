require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:website_redesign)
    sign_in_as users(:one)
  end

  test "unauthenticated requests are redirected to sign in" do
    sign_out
    get projects_url
    assert_redirected_to new_session_url
  end

  test "index lists only the current user's projects" do
    get projects_url
    assert_response :success
    assert_select "a", text: @project.name
    assert_select "a", { text: projects(:legacy_migration).name, count: 0 }
  end

  test "index filters by search query" do
    get projects_url, params: { q: "website" }
    assert_response :success
    assert_match @project.name, response.body
    assert_no_match projects(:mobile_app).name, response.body
  end

  test "show renders a project and its tasks" do
    get project_url(@project)
    assert_response :success
  end

  test "show on another user's project is not found" do
    get project_url(projects(:legacy_migration))
    assert_response :not_found
  end

  test "create with valid params" do
    assert_difference "Project.count", 1 do
      post projects_url, params: { project: { name: "New Project", description: "desc", status: "active" } }
    end
    assert_equal users(:one), Project.last.user
    assert_redirected_to project_url(Project.last)
  end

  test "create with invalid params does not save" do
    assert_no_difference "Project.count" do
      post projects_url, params: { project: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "update with valid params" do
    patch project_url(@project), params: { project: { name: "Renamed" } }
    assert_redirected_to project_url(@project)
    assert_equal "Renamed", @project.reload.name
  end

  test "update on another user's project is not found" do
    patch project_url(projects(:legacy_migration)), params: { project: { name: "Hijacked" } }
    assert_response :not_found
  end

  test "destroy removes the project and its tasks" do
    assert_difference "Project.count", -1 do
      assert_difference "Task.count", -@project.tasks.count do
        delete project_url(@project)
      end
    end
    assert_redirected_to projects_url
  end

  test "destroy on another user's project is not found" do
    delete project_url(projects(:legacy_migration))
    assert_response :not_found
  end
end
