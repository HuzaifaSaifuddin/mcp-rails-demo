class Task < ApplicationRecord
  belongs_to :project

  enum :status, { pending: 0, in_progress: 1, done: 2 }, default: :pending

  validates :title, presence: true, length: { maximum: 140 }

  scope :overdue, -> { where.not(status: :done).where(due_date: ...Date.current) }
  scope :open, -> { where.not(status: :done) }
end
