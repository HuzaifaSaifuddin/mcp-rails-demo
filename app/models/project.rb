class Project < ApplicationRecord
  has_many :tasks, dependent: :destroy

  enum :status, { active: 0, archived: 1 }, default: :active

  validates :name, presence: true, length: { maximum: 140 }

  scope :active, -> { where(status: :active) }
  scope :search, ->(query) { where("name ILIKE :q", q: "%#{sanitize_sql_like(query)}%") if query.present? }
end
