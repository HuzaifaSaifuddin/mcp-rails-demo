class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :tasks, through: :projects

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
