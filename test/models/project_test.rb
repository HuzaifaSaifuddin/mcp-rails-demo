require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "invalid without a name" do
    project = Project.new(description: "x")
    assert_not project.valid?
    assert_includes project.errors[:name], "can't be blank"
  end

  test "defaults to active status" do
    assert_equal "active", Project.new.status
  end

  test "destroying a project destroys its tasks" do
    project = projects(:website_redesign)
    assert_difference "Task.count", -project.tasks.count do
      project.destroy
    end
  end

  test ".active returns only active projects" do
    assert_includes Project.active, projects(:website_redesign)
    assert_not_includes Project.active, projects(:legacy_migration)
  end

  test ".search matches on name, case-insensitively" do
    assert_includes Project.search("website"), projects(:website_redesign)
    assert_not_includes Project.search("website"), projects(:mobile_app)
  end

  test ".search with a blank query returns everything" do
    assert_equal Project.count, Project.search(nil).count
    assert_equal Project.count, Project.search("").count
  end
end
