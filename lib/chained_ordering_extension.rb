# frozen_string_literal: true

after_initialize do
  # Patch the TopicQuery class to support chained ordering
  TopicQuery.class_eval do
    # Update the validator to allow arrays for the order parameter
    @validators = nil  # Clear cached validators
    
    def self.validators
      @validators ||=
        begin
          int = lambda { |x| Integer === x || (String === x && x.match?(/\A-?[0-9]+\z/)) }
          zero_up_to_max_int = lambda { |x| int.call(x) && x.to_i.between?(0, PG_MAX_INT) }
          one_up_to_one_hundred = lambda { |x| int.call(x) && x.to_i.between?(1, 100) }
          array_or_string = lambda { |x| Array === x || String === x }
          string = lambda { |x| String === x }
          true_or_false = lambda { |x| x == true || x == false || x == "true" || x == "false" }

          {
            page: zero_up_to_max_int,
            per_page: one_up_to_one_hundred,
            before: zero_up_to_max_int,
            bumped_before: zero_up_to_max_int,
            topic_ids: array_or_string,
            category: string,
            order: array_or_string,  # This now allows arrays
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

    # Override the apply_ordering method to support chained ordering
    def apply_ordering(result, options = {})
      order_option = options[:order]
      sort_dir = (options[:ascending] == "true") ? "ASC" : "DESC"

      # If order_option is an array, apply chained ordering
      if order_option.is_a?(Array)
        order_clauses = order_option.map do |order_field|
          sort_column = SORTABLE_MAPPING[order_field] || "default"
          if sort_column == "default"
            sort_column = "bumped_at"
          end
          if sort_column == "category_id"
            "CASE WHEN categories.id = #{SiteSetting.uncategorized_category_id.to_i} THEN '' ELSE categories.name END #{sort_dir}"
          elsif sort_column == "op_likes"
            "(SELECT like_count FROM posts p3 WHERE p3.topic_id = topics.id AND p3.post_number = 1) #{sort_dir}"
          elsif sort_column.start_with?("custom_fields")
            field = sort_column.split(".")[1]
            "(SELECT CASE WHEN EXISTS (SELECT true FROM topic_custom_fields tcf WHERE tcf.topic_id::integer = topics.id::integer AND tcf.name = '#{field}') THEN (SELECT value::integer FROM topic_custom_fields tcf WHERE tcf.topic_id::integer = topics.id::integer AND tcf.name = '#{field}') ELSE 0 END) #{sort_dir}"
          else
            "topics.#{sort_column} #{sort_dir}"
          end
        end
        return result.order(order_clauses.join(", "))
      end

      # Fall back to original behavior for non-array orders
      new_result =
        DiscoursePluginRegistry.apply_modifier(
          :topic_query_apply_ordering_result,
          result,
          order_option,
          sort_dir,
          options,
          self,
        )
      return new_result if !new_result.nil? && new_result != result
      
      sort_column = SORTABLE_MAPPING[order_option] || "default"

      # If we are sorting in the default order desc, we should consider including pinned
      # topics. Otherwise, just use bumped_at.
      if sort_column == "default"
        if sort_dir == "DESC"
          # If something requires a custom order, for example "unread" which sorts the least read
          # to the top, do nothing
          return result if options[:unordered]
        end
        sort_column = "bumped_at"
      end

      # If we are sorting by category, actually use the name
      if sort_column == "category_id"
        # TODO forces a table scan, slow
        return result.references(:categories).order(<<~SQL)
          CASE WHEN categories.id = #{SiteSetting.uncategorized_category_id.to_i} THEN '' ELSE categories.name END #{sort_dir}
        SQL
      end

      if sort_column == "op_likes"
        return(
          result.includes(:first_post).order(
            "(SELECT like_count FROM posts p3 WHERE p3.topic_id = topics.id AND p3.post_number = 1) #{sort_dir}",
          )
        )
      end

      if sort_column.start_with?("custom_fields")
        field = sort_column.split(".")[1]
        return(
          result.order(
            "(SELECT CASE WHEN EXISTS (SELECT true FROM topic_custom_fields tcf WHERE tcf.topic_id::integer = topics.id::integer AND tcf.name = '#{field}') THEN (SELECT value::integer FROM topic_custom_fields tcf WHERE tcf.topic_id::integer = topics.id::integer AND tcf.name = '#{field}') ELSE 0 END) #{sort_dir}",
          )
        )
      end

      result.order("topics.#{sort_column} #{sort_dir}")
    end
  end
end