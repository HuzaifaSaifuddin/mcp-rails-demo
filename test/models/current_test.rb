require "test_helper"

class CurrentTest < ActiveSupport::TestCase
  test "user resolves from a browser session" do
    Current.session = users(:one).sessions.create!

    assert_equal users(:one), Current.user
  end

  test "user resolves from an api_token, with no Session record involved" do
    token = ApiToken.generate!(user: users(:one))
    Current.api_token = token

    assert_equal users(:one), Current.user
    assert_equal 0, users(:one).sessions.count
  end

  test "user is nil when neither session nor api_token is set" do
    assert_nil Current.user
  end

  test "session takes precedence over api_token when both are set" do
    Current.session = users(:one).sessions.create!
    Current.api_token = ApiToken.generate!(user: users(:two))

    assert_equal users(:one), Current.user
  end
end
