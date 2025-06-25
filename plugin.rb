# frozen_string_literal: true

# name: discourse-chained-ordering
# about: Enables chained ordering functionality for Discourse topics
# version: 1.0.0
# authors: Ahsan
# url: https://github.com/yourusername/discourse-chained-ordering
# required_version: 2.7.0

enabled_site_setting :chained_ordering_enabled


after_initialize do
  require_relative "lib/chained_ordering_extension"
end