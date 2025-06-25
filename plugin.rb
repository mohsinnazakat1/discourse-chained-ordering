# frozen_string_literal: true
# name: discourse-chained-ordering
# about: Adds support for chained ordering of topics using multiple sort criteria
# version: 0.1.0
# authors: Ahsan
# url: https://github.com/yourusername/discourse-chained-ordering
# required_version: 2.7.0

enabled_site_setting :chained_ordering_enabled

# Load the extension module - this will handle all the logic
require_relative "lib/chained_ordering_extension"