require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "generate! persists a token and returns the plaintext value exactly once" do
    token = ApiToken.generate!(user: users(:one))

    assert token.persisted?
    assert_equal 64, token.plaintext_token.length
    assert_not_equal token.plaintext_token, token.token_digest

    reloaded = ApiToken.find(token.id)
    assert_nil reloaded.plaintext_token
  end

  test "requires a user" do
    token = ApiToken.new(token_digest: "x" * 64)
    assert_not token.valid?
    assert_includes token.errors[:user], "must exist"
  end

  test "requires a unique token_digest" do
    existing = ApiToken.generate!(user: users(:one))

    duplicate = ApiToken.new(user: users(:two), token_digest: existing.token_digest)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:token_digest], "has already been taken"
  end

  test "authenticate finds the token for the correct raw value" do
    token = ApiToken.generate!(user: users(:one))

    found = ApiToken.authenticate(token.plaintext_token)
    assert_equal token, found
  end

  test "authenticate returns nil for an incorrect raw value" do
    ApiToken.generate!(user: users(:one))

    assert_nil ApiToken.authenticate("not-the-right-token")
  end

  test "authenticate returns nil for blank or nil input" do
    assert_nil ApiToken.authenticate("")
    assert_nil ApiToken.authenticate(nil)
  end

  test "authenticate returns nil for a revoked token" do
    token = ApiToken.generate!(user: users(:one))
    token.revoke!

    assert_nil ApiToken.authenticate(token.plaintext_token)
  end

  test "revoke! sets revoked_at and revoked?" do
    token = ApiToken.generate!(user: users(:one))
    assert_not token.revoked?

    token.revoke!

    assert token.revoked?
    assert token.revoked_at.present?
  end

  test ".active scope excludes revoked tokens" do
    token = ApiToken.generate!(user: users(:one))
    assert_includes ApiToken.active, token

    token.revoke!

    assert_not_includes ApiToken.active, token
  end
end
