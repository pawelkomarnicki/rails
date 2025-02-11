# frozen_string_literal: true

gem "minitest"
require "minitest"
require "rails/test_unit/runner"

task default: :test

desc "Run all tests in test folder except system ones"
task :test do
  if ENV.key?("TEST")
    Rails::TestUnit::Runner.rake_run([ENV["TEST"]])
  else
    Rails::TestUnit::Runner.rake_run
  end
end

namespace :test do
  task :prepare do
    # Placeholder task for other Railtie and plugins to enhance.
    # If used with Active Record, this task runs before the database schema is synchronized.
  end

  task run: %w[test]

  desc "Reset the database and run `bin/rails test`"
  task :db do
    success = system({ "RAILS_ENV" => ENV.fetch("RAILS_ENV", "test") }, "rake", "db:test:prepare", "test")
    success || exit(false)
  end

  Rails::TestUnit::Runner::TEST_FOLDERS.each do |name|
    task name => "test:prepare" do
      Rails::TestUnit::Runner.rake_run(["test/#{name}"])
    end
  end

  task all: "test:prepare" do
    Rails::TestUnit::Runner.rake_run(["test/**/*_test.rb"])
  end

  task generators: "test:prepare" do
    Rails::TestUnit::Runner.rake_run(["test/lib/generators"])
  end

  task units: "test:prepare" do
    Rails::TestUnit::Runner.rake_run(["test/models", "test/helpers", "test/unit"])
  end

  task functionals: "test:prepare" do
    Rails::TestUnit::Runner.rake_run(["test/controllers", "test/mailers", "test/functional"])
  end

  task system: "test:prepare" do
    Rails::TestUnit::Runner.rake_run(["test/system"])
  end
end
