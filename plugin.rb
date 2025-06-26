# frozen_string_literal: true

# name: discourse-chained-ordering
# about: Enables chained ordering functionality for Discourse topics
# version: 1.0.0
# authors: Ahsan
# url: https://github.com/yourusername/discourse-chained-ordering
# required_version: 2.7.0

enabled_site_setting :chained_ordering_enabled

after_initialize do
  # Patch the TopicQuery class to support chained ordering
  TopicQuery.class_eval do
    # Clear the cached validators to force reload
    @validators = nil
    
    # Override the validators class method
    def self.validators
      Rails.logger.info "Custom Plugin: Chained Ordering -> Validators class method called"
      @validators ||=
        begin
          int = lambda { |x| Integer === x || (String === x && x.match?(/\A-?[0-9]+\z/)) }
          zero_up_to_max_int = lambda { |x| int.call(x) && x.to_i.between?(0, PG_MAX_INT) }
          one_up_to_one_hundred = lambda { |x| int.call(x) && x.to_i.between?(1, 100) }
          array_or_string = lambda { |x| Array === x || String === x }
          string = lambda { |x| String === x }
          true_or_false = lambda { |x| x == true || x == false || x == "true" || x == "false" }

          # Match the original order exactly - this is crucial
          {
            page: zero_up_to_max_int,
            per_page: one_up_to_one_hundred,
            before: zero_up_to_max_int,
            bumped_before: zero_up_to_max_int,
            topic_ids: array_or_string,
            category: string,
            order: array_or_string,  # Modified to accept arrays
            ascending: true_or_false,
            min_posts: zero_up_to_max_int,
            max_posts: zero_up_to_max_int,
            status: string,
            filter: string,
            state: string,
            search: string,
            q: string,
            f: string,
            subset: string,
            group_name: string,
            tags: array_or_string,
            match_all_tags: true_or_false,
            no_subcategories: true_or_false,
            no_tags: true_or_false,
            exclude_tag: string,
          }
        end
    end

    # Override apply_ordering with better error handling
    def apply_ordering(result, options = {})
      Rails.logger.info "Custom Plugin: Chained Ordering -> apply_ordering method called"
      begin
        order_option = options[:order]
        sort_dir = (options[:ascending] == "true") ? "ASC" : "DESC"

        # Only process arrays if the feature is enabled
        if SiteSetting.chained_ordering_enabled && order_option.is_a?(Array)
          order_clauses = []
          
          order_option.each do |order_field|
            next if order_field.blank?
            
            sort_column = SORTABLE_MAPPING[order_field.to_s] || "default"
            sort_column = "bumped_at" if sort_column == "default"
            
            case sort_column
            when "category_id"
              order_clauses << "CASE WHEN categories.id = #{SiteSetting.uncategorized_category_id.to_i} THEN '' ELSE categories.name END #{sort_dir}"
            when "op_likes"
              order_clauses << "(SELECT like_count FROM posts p3 WHERE p3.topic_id = topics.id AND p3.post_number = 1) #{sort_dir}"
            else
              if sort_column.start_with?("custom_fields")
                field = sort_column.split(".")[1]
                order_clauses << "(SELECT CASE WHEN EXISTS (SELECT true FROM topic_custom_fields tcf WHERE tcf.topic_id::integer = topics.id::integer AND tcf.name = '#{field}') THEN (SELECT value::integer FROM topic_custom_fields tcf WHERE tcf.topic_id::integer = topics.id::integer AND tcf.name = '#{field}') ELSE 0 END) #{sort_dir}"
              else
                order_clauses << "topics.#{sort_column} #{sort_dir}"
              end
            end
          end
          
          return result.order(order_clauses.join(", ")) unless order_clauses.empty?
        end

        # Call the original method for single orders or when feature is disabled
        super
      rescue => e
        Rails.logger.error "Chained ordering error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        # Fall back to original method on any error
        super
      end
    end
  end
end