class ApiToken < ApplicationRecord
  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil) }

  # Only populated on the instance returned by `generate!`, and only
  # ever held in memory - the raw token is never persisted or
  # retrievable again once this object is discarded.
  attr_accessor :plaintext_token

  class << self
    def generate!(user:, name: nil)
      raw_token = SecureRandom.hex(32)

      create!(user: user, name: name, token_digest: digest(raw_token)).tap do |api_token|
        api_token.plaintext_token = raw_token
      end
    end

    def authenticate(raw_token)
      return nil if raw_token.blank?

      active.find_by(token_digest: digest(raw_token))
    end

    private

    def digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def revoked?
    revoked_at.present?
  end
end
