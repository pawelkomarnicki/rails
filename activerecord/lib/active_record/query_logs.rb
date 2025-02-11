# frozen_string_literal: true

require "active_support/core_ext/module/attribute_accessors_per_thread"
require "active_record/query_logs_formatter"

module ActiveRecord
  # = Active Record Query Logs
  #
  # Automatically append comments to SQL queries with runtime information tags. This can be used to trace troublesome
  # SQL statements back to the application code that generated these statements.
  #
  # Query logs can be enabled via Rails configuration in <tt>config/application.rb</tt> or an initializer:
  #
  #     config.active_record.query_log_tags_enabled = true
  #
  # By default the name of the application, the name and action of the controller, or the name of the job are logged.
  # The default format is {SQLCommenter}[https://open-telemetry.github.io/opentelemetry-sqlcommenter/].
  # The tags shown in a query comment can be configured via Rails configuration:
  #
  #     config.active_record.query_log_tags = [ :application, :controller, :action, :job ]
  #
  # Active Record defines default tags available for use:
  #
  # * +application+
  # * +pid+
  # * +socket+
  # * +db_host+
  # * +database+
  #
  # Action Controller adds default tags when loaded:
  #
  # * +controller+
  # * +action+
  # * +namespaced_controller+
  #
  # Active Job adds default tags when loaded:
  #
  # * +job+
  #
  # New comment tags can be defined by adding them in a +Hash+ to the tags +Array+. Tags can have dynamic content by
  # setting a +Proc+ or lambda value in the +Hash+, and can reference any value stored by Rails in the +context+ object.
  # ActiveSupport::CurrentAttributes can be used to store application values. Tags with +nil+ values are
  # omitted from the query comment.
  #
  # Escaping is performed on the string returned, however untrusted user input should not be used.
  #
  # Example:
  #
  #     config.active_record.query_log_tags = [
  #       :namespaced_controller,
  #       :action,
  #       :job,
  #       {
  #         request_id: ->(context) { context[:controller]&.request&.request_id },
  #         job_id: ->(context) { context[:job]&.job_id },
  #         tenant_id: -> { Current.tenant&.id },
  #         static: "value",
  #       },
  #     ]
  #
  # By default the name of the application, the name and action of the controller, or the name of the job are logged
  # using the {SQLCommenter}[https://open-telemetry.github.io/opentelemetry-sqlcommenter/] format. This can be changed
  # via {config.active_record.query_log_tags_format}[https://guides.rubyonrails.org/configuring.html#config-active-record-query-log-tags-format]
  #
  # Tag comments can be prepended to the query:
  #
  #    ActiveRecord::QueryLogs.prepend_comment = true
  #
  # For applications where the content will not change during the lifetime of
  # the request or job execution, the tags can be cached for reuse in every query:
  #
  #    config.active_record.cache_query_log_tags = true
  module QueryLogs
    mattr_accessor :taggings, instance_accessor: false, default: {}
    mattr_accessor :tags, instance_accessor: false, default: [ :application ]
    mattr_accessor :prepend_comment, instance_accessor: false, default: false
    mattr_accessor :cache_query_log_tags, instance_accessor: false, default: false
    mattr_accessor :tags_formatter, instance_accessor: false
    thread_mattr_accessor :cached_comment, instance_accessor: false

    class << self
      def call(sql) # :nodoc:
        if comment.blank?
          sql
        elsif prepend_comment
          "#{self.comment} #{sql}"
        else
          "#{sql} #{self.comment}"
        end
      end

      def clear_cache # :nodoc:
        self.cached_comment = nil
      end

      # Updates the formatter to be what the passed in format is.
      def update_formatter(format)
        self.tags_formatter =
          case format
          when :legacy
            LegacyFormatter.new
          when :sqlcommenter
            SQLCommenter.new
          else
            raise ArgumentError, "Formatter is unsupported: #{formatter}"
          end
      end

      ActiveSupport::ExecutionContext.after_change { ActiveRecord::QueryLogs.clear_cache }

      private
        # Returns an SQL comment +String+ containing the query log tags.
        # Sets and returns a cached comment if <tt>cache_query_log_tags</tt> is +true+.
        def comment
          if cache_query_log_tags
            self.cached_comment ||= uncached_comment
          else
            uncached_comment
          end
        end

        def formatter
          self.tags_formatter || self.update_formatter(:legacy)
        end

        def uncached_comment
          content = tag_content
          if content.present?
            "/*#{escape_sql_comment(content)}*/"
          end
        end

        def escape_sql_comment(content)
          # Sanitize a string to appear within a SQL comment
          # For compatibility, this also surrounding "/*+", "/*", and "*/"
          # charcacters, possibly with single surrounding space.
          # Then follows that by replacing any internal "*/" or "/ *" with
          # "* /" or "/ *"
          comment = content.to_s.dup
          comment.gsub!(%r{\A\s*/\*\+?\s?|\s?\*/\s*\Z}, "")
          comment.gsub!("*/", "* /")
          comment.gsub!("/*", "/ *")
          comment
        end

        def tag_content
          context = ActiveSupport::ExecutionContext.to_h

          pairs = tags.flat_map { |i| [*i] }.filter_map do |tag|
            key, handler = tag
            handler ||= taggings[key]

            val = if handler.nil?
              context[key]
            elsif handler.respond_to?(:call)
              if handler.arity == 0
                handler.call
              else
                handler.call(context)
              end
            else
              handler
            end
            [key, val] unless val.nil?
          end
          self.formatter.format(pairs)
        end
    end
  end
end
