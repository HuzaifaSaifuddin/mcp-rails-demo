require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:website_redesign)
    @task = tasks(:wireframes)
  end

  test "show renders a task" do
    get task_url(@task)
    assert_response :success
  end

  test "new requires a project" do
    get new_project_task_url(@project)
    assert_response :success
  end

  test "create with valid params" do
    assert_difference "@project.tasks.count", 1 do
      post project_tasks_url(@project), params: { task: { title: "New task", status: "pending" } }
    end
    assert_redirected_to project_url(@project)
  end

  test "create with invalid params does not save" do
    assert_no_difference "Task.count" do
      post project_tasks_url(@project), params: { task: { title: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "update with valid params" do
    patch task_url(@task), params: { task: { status: "done" } }
    assert_redirected_to project_url(@task.project)
    assert_equal "done", @task.reload.status
  end

  test "destroy removes the task" do
    assert_difference "Task.count", -1 do
      delete task_url(@task)
    end
    assert_redirected_to project_url(@project)
  end
end
