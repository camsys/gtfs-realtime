require 'bundler'

Bundler.require :default, :development

# If you're using all parts of Rails:
Combustion.initialize! :active_record
# Or, load just what you need:
# Combustion.initialize! :active_record, :action_controller

require 'rspec'
# If you're using Capybara:
# require 'capybara/rails'