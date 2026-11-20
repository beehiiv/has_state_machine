# frozen_string_literal: true

module RubyLsp
  module HasStateMachine
    # Isolates RubyIndexer::Index queries so a future Rubydex backend is a localized swap.
    class IndexAdapter
      def initialize(index)
        @index = index
      end

      def ready_for_ancestry?(superclass_name)
        return false if index.respond_to?(:initial_indexing_completed) && !index.initial_indexing_completed

        indexed?(superclass_name)
      end

      def indexed?(name)
        return false unless name && index&.respond_to?(:indexed?)

        index.indexed?(name)
      end

      # Walks Entry::Class#parent_class directly instead of calling
      # RubyIndexer::Index#linearized_ancestors_of: HasStateMachine::State inherits
      # from String, and any gem monkeypatching String with a non-module constant
      # mixin causes linearized_ancestors_of to raise and cache a truncated ancestor list.
      def subclass_of?(class_name, target_ancestor)
        return false unless class_name && index

        current = class_name
        seen = {}

        while current && !seen[current]
          return true if current == target_ancestor

          seen[current] = true
          entry = superclass_entry(current)
          return false unless entry

          parent = entry.parent_class
          return false if parent.nil? || parent == "::Object"

          current = resolve_parent_name(parent, entry.nesting)
        end

        false
      end

      def module_only?(name)
        return false unless name && index

        entries = resolve_entries(name)
        entries.any? && entries.all?(::RubyIndexer::Entry::Module)
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

      def superclass_entry(name)
        entries = resolve_entries(name).grep(::RubyIndexer::Entry::Class)
        entries.find { |entry| entry.parent_class && entry.parent_class != "::Object" } || entries.first
      end

      def resolve_parent_name(parent_name, nesting)
        entry = index.resolve(parent_name, nesting[0...-1])&.first
        resolve_constant_name(entry.name) if entry
      end

      def resolve_constant_name(name, seen = {})
        return if seen[name]

        entries = resolve_entries(name)
        return if entries.empty?

        entry = entries.first
        if entry.is_a?(::RubyIndexer::Entry::ConstantAlias)
          seen[name] = true
          resolve_constant_name(entry.target, seen) || entry.target
        else
          entry.name
        end
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
