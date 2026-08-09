# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

demo_user = User.find_or_create_by!(email_address: "demo@example.com") do |u|
  u.password = "password"
  u.password_confirmation = "password"
end

other_user = User.find_or_create_by!(email_address: "other@example.com") do |u|
  u.password = "password"
  u.password_confirmation = "password"
end

website = demo_user.projects.find_or_create_by!(name: "Website Redesign") do |p|
  p.description = "Refresh the marketing site ahead of the Q4 launch"
  p.status = :active
end

mobile = demo_user.projects.find_or_create_by!(name: "Mobile App") do |p|
  p.description = "iOS/Android client for existing customers"
  p.status = :active
end

demo_user.projects.find_or_create_by!(name: "Legacy Migration") do |p|
  p.description = "Sunsetting the old system"
  p.status = :archived
end

other_user.projects.find_or_create_by!(name: "Marketing Site") do |p|
  p.description = "A project owned by a different user, to demonstrate authorization"
  p.status = :active
end

website.tasks.find_or_create_by!(title: "Create wireframes") do |t|
  t.description = "Low-fidelity wireframes for the homepage"
  t.status = :done
  t.due_date = 10.days.ago.to_date
end

website.tasks.find_or_create_by!(title: "Write homepage copy") do |t|
  t.status = :in_progress
  t.due_date = 5.days.from_now.to_date
end

website.tasks.find_or_create_by!(title: "Fix broken checkout") do |t|
  t.description = "Customers report a 500 on payment submit"
  t.status = :pending
  t.due_date = 5.days.ago.to_date
end

mobile.tasks.find_or_create_by!(title: "Set up CI pipeline") do |t|
  t.status = :pending
  t.due_date = 10.days.from_now.to_date
end

mobile.tasks.find_or_create_by!(title: "Design onboarding flow") do |t|
  t.status = :pending
end
