# frozen_string_literal: true

require "ruby_lsp/addon"

# Ruby LSP 0.27 replaces RubyIndexer with Rubydex; revisit once Rubydex DSL indexing lands.
::RubyLsp::Addon.depend_on_ruby_lsp!(">= 0.23.0", "< 0.27.0") if ::RubyLsp::Addon.respond_to?(:depend_on_ruby_lsp!)

require "has_state_machine/version"
require_relative "definition"
require_relative "indexing_enhancement"

module RubyLsp
  module HasStateMachine
    class Addon < ::RubyLsp::Addon
      def activate(global_state, outgoing_queue)
        @global_state = global_state

        log(outgoing_queue, "Activating Has State Machine Ruby LSP add-on v#{version}")
      end

      def deactivate
        @global_state = nil
        NamespaceRegistry.clear
      end

      def name
        "Has State Machine"
      end

      def version
        ::HasStateMachine::VERSION
      end

      def create_definition_listener(response_builder, uri, node_context, dispatcher)
        Definition.new(
          response_builder,
          uri,
          node_context,
          dispatcher,
          index: @global_state&.index
        )
      end

      # Ruby LSP re-indexes CHANGED files before invoking file-watcher add-ons,
      # so only DELETED files need explicit eviction here.
      def workspace_did_change_watched_files(changes)
        deleted = ::RubyLsp::Constant::FileChangeType::DELETED
        changes.each do |change|
          NamespaceRegistry.instance.clear_uri(change[:uri]) if change[:type] == deleted
        end
      end

      private

      def log(outgoing_queue, message)
        return if outgoing_queue.nil? || outgoing_queue.closed?

        outgoing_queue << ::RubyLsp::Notification.window_log_message(message)
      end
    end
  end
end
