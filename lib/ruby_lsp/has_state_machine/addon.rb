# frozen_string_literal: true

require "ruby_lsp/addon"

require "has_state_machine/version"
require_relative "definition"

::RubyLsp::Addon.depend_on_ruby_lsp!(">= 0.18.0", "< 1.0") if ::RubyLsp::Addon.respond_to?(:depend_on_ruby_lsp!)

module RubyLsp
  module HasStateMachine
    class Addon < ::RubyLsp::Addon
      def activate(global_state, outgoing_queue)
        @global_state = global_state
        @rails_client = register_rails_server_addon(outgoing_queue)
      end

      def deactivate
        @global_state = nil
        @rails_client = nil
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
          index: @global_state&.index,
          rails_client: @rails_client
        )
      end

      private

      def register_rails_server_addon(outgoing_queue)
        register_rails_runner_client
      rescue => error
        handle_rails_registration_error(outgoing_queue, error)
      end

      def register_rails_runner_client
        rails_addon = ::RubyLsp::Addon.get("Ruby LSP Rails", ">= 0") if ::RubyLsp::Addon.respond_to?(:get)
        return unless rails_addon&.respond_to?(:rails_runner_client)

        client = rails_addon.rails_runner_client
        return unless client.respond_to?(:register_server_addon)

        client.register_server_addon(File.expand_path("rails_server_addon.rb", __dir__))
        client
      end

      def handle_rails_registration_error(outgoing_queue, error)
        unless addon_not_found?(error)
          log(outgoing_queue, "Has State Machine Ruby LSP Rails integration unavailable: #{error.message}")
        end

        nil
      end

      def addon_not_found?(error)
        if defined?(::RubyLsp::Addon::AddonNotFoundError)
          return true if error.is_a?(::RubyLsp::Addon::AddonNotFoundError)
        end

        error.class.name&.end_with?("AddonNotFoundError")
      end

      def log(outgoing_queue, message)
        return if outgoing_queue.nil? || outgoing_queue.closed?
        return unless defined?(::RubyLsp::Notification)

        outgoing_queue << ::RubyLsp::Notification.window_log_message(message)
      end
    end
  end
end
