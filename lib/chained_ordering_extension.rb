  # frozen_string_literal: true

module ::ChainedOrderingExtension
  def self.apply_chained_ordering(result, options)
    order_option = options[:order]
    sort_dir = (options[:ascending] == "true") ? "ASC" : "DESC"
    return nil unless order_option.is_a?(Array)
    order_clauses = order_option.map do |order_field|
      sort_column = ::TopicQuery::SORTABLE_MAPPING[order_field] || "default"
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
    result.order(order_clauses.join(", "))
  end
end

# Register the plugin ordering logic
DiscoursePluginRegistry.register_modifier(:topic_query_apply_ordering_result) do |result, order_option, sort_dir, options, topic_query|
  ::ChainedOrderingExtension.apply_chained_ordering(result, options)
end

# Patch the validator to allow array for :order
after_initialize do
  ::TopicQuery.validators[:order] = lambda { |x| Array === x || String === x }
end