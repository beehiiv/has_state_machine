# frozen_string_literal: true

module RubyLsp
  module HasStateMachine
    # Isolates RubyIndexer::Index queries so a future Rubydex backend is a localized swap.
    class IndexAdapter
      def initialize(index)
        @index = index
      end

      def ready_for_ancestry?(superclass_name)
        return false unless index&.respond_to?(:linearized_ancestors_of) && index.respond_to?(:indexed?)
        return false if index.respond_to?(:initial_indexing_completed) && !index.initial_indexing_completed

        index.indexed?(superclass_name)
      end

      # Returns nil when class_name is not yet indexed (e.g. an unsaved file).
      def ancestors_of(class_name)
        return unless index&.respond_to?(:linearized_ancestors_of)

        index.linearized_ancestors_of(class_name)
      rescue => error
        return if non_existing_namespace_error?(error)

        raise
      end

      def class_entries(name)
        return [] unless name && index

        entries = resolve_entries(name)
        entries.select { |entry| class_entry?(entry) }
      end

      def method_entries(owner_name, method_name)
        return [] unless index && owner_name && method_name

        if index.respond_to?(:resolve_method)
          return Array(index.resolve_method(method_name, owner_name))
        end

        Array(index[method_name]).select { |entry| entry_owner_name(entry) == owner_name }
      end

      private

      attr_reader :index

      def resolve_entries(name)
        entries = Array(index[name])
        return entries if entries.empty?
        return entries unless unresolved_alias_present?(entries) && index.respond_to?(:resolve)

        Array(index.resolve(name, []))
      end

      def unresolved_alias_present?(entries)
        return false unless defined?(::RubyIndexer::Entry::UnresolvedConstantAlias)

        entries.any?(::RubyIndexer::Entry::UnresolvedConstantAlias)
      end

      def class_entry?(entry, seen = [])
        return true unless defined?(::RubyIndexer::Entry) && entry.is_a?(::RubyIndexer::Entry)
        return true if entry.is_a?(::RubyIndexer::Entry::Class)

        if defined?(::RubyIndexer::Entry::ConstantAlias) && entry.is_a?(::RubyIndexer::Entry::ConstantAlias)
          target = entry.target
          return false if seen.include?(target)

          seen << target
          return resolve_entries(target).any? { |target_entry| class_entry?(target_entry, seen) }
        end

        false
      end

      def entry_owner_name(entry)
        owner = entry.owner if entry.respond_to?(:owner)
        owner.name if owner.respond_to?(:name)
      end

      def non_existing_namespace_error?(error)
        defined?(::RubyIndexer::Index::NonExistingNamespaceError) &&
          error.is_a?(::RubyIndexer::Index::NonExistingNamespaceError)
      end
    end
  end
end
