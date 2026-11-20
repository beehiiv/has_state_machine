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
      rescue ::RubyIndexer::Index::NonExistingNamespaceError
        nil
      end

      def class_entries(name)
        return [] unless name && index

        entries = resolve_entries(name)
        entries.select { |entry| class_entry?(entry) }
      end

      def method_entries(owner_name, method_name)
        return [] unless index && owner_name && method_name

        Array(index.resolve_method(method_name, owner_name))
      end

      private

      attr_reader :index

      def resolve_entries(name)
        entries = Array(index[name])
        entries.any?(::RubyIndexer::Entry::UnresolvedConstantAlias) ? Array(index.resolve(name, [])) : entries
      end

      def class_entry?(entry, seen = [])
        case entry
        when ::RubyIndexer::Entry::Class then true
        when ::RubyIndexer::Entry::ConstantAlias
          target = entry.target
          return false if seen.include?(target)

          seen << target
          resolve_entries(target).any? { |target_entry| class_entry?(target_entry, seen) }
        when ::RubyIndexer::Entry then false
        else true # test doubles
        end
      end
    end
  end
end
