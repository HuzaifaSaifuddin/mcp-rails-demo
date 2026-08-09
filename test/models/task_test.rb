require "test_helper"

class TaskTest < ActiveSupport::TestCase
  test "invalid without a title" do
    task = Task.new(project: projects(:website_redesign))
    assert_not task.valid?
    assert_includes task.errors[:title], "can't be blank"
  end

  test "invalid without a project" do
    task = Task.new(title: "Orphan task")
    assert_not task.valid?
    assert_includes task.errors[:project], "must exist"
  end

  test "defaults to pending status" do
    assert_equal "pending", Task.new.status
  end

  test ".overdue excludes done tasks even if past due" do
    assert_includes Task.overdue, tasks(:overdue_checkout_fix)
    assert_not_includes Task.overdue, tasks(:wireframes)
  end

  test ".overdue excludes tasks without a due date" do
    task = Task.create!(project: projects(:mobile_app), title: "No due date")
    assert_not_includes Task.overdue, task
  end

  test ".open excludes done tasks" do
    assert_includes Task.open, tasks(:overdue_checkout_fix)
    assert_not_includes Task.open, tasks(:wireframes)
  end
end
