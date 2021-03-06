require File.join(File.dirname(__FILE__), 'boot')

RAILS_GEM_VERSION = '2.1.1' unless defined? RAILS_GEM_VERSION

# temporary until Rails bug fixed
require 'fix_locator_bug'

unless File.exist?(config_filename = Rails.root + '/config/database.yml')
  require 'fileutils'
  FileUtils.cp(config_filename + '.example', config_filename)
end

Rails::Initializer.run do |config|
  config.action_controller.session_store = :active_record_store
  config.action_controller.cache_store = :file_store, Rails.root + '/cache'
  config.log_path = File.join(File.dirname(__FILE__), "../log/#{RAILS_ENV}.log")
  config.database_configuration_file = File.expand_path(File.join(File.dirname(__FILE__), 'database.yml'))
  config.load_paths << Rails.root + '/app/sweepers'
  config.plugin_paths << Rails.root + '/plugins'
  # dependencies
  config.gem 'pdf-writer', :lib => 'pdf/writer'
  config.gem 'highline'
  config.gem 'mini_magick'
end

PHONE_HOME_FOR_VERSION_INFO = true unless defined? PHONE_HOME_FOR_VERSION_INFO
