# frozen_string_literal: true

require "digest"
require "prism"
require "set"

module HasStateMachine
  module Lint
    class ModelIndex
      DEFAULT_ATTRIBUTE = "status"
      REFRESH_INTERVAL = 1.0

      # `ancestors` holds [reference, lexical_scopes] pairs, resolved lazily because
      # the referenced constant may live in a file parsed later.
      Owner = Struct.new(:name, :file, :attributes, :ancestors)

      class << self
        def for(root, patterns)
          @indexes ||= {}
          @indexes[[root, patterns]] ||= new(root, patterns)
        end

        def owners_in(source, file)
          collector = Collector.new(file)
          Prism.parse(source).value.accept(collector)
          collector.owners
        end
      end

      def initialize(root, patterns)
        @root = root
        @patterns = patterns
        @mtimes = nil
        @owners_by_file = {}
      end

      # `source` may be an unsaved editor buffer, so its owners replace the on-disk copy of `file`.
      def attributes_for(file, source)
        refresh
        local = self.class.owners_in(source, file).group_by(&:name)
        lookup = ->(name) { @graph.fetch(name, []).reject { |owner| owner.file == file } + local.fetch(name, []) }

        local.keys.flat_map { |name| attributes_of(name, lookup) }.uniq.sort
      end

      def checksum
        refresh
        @checksum
      end

      def attributes_by_file
        refresh
        @attributes_by_file
      end

      private

      def refresh
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return if @checked_at && now - @checked_at < REFRESH_INTERVAL

        @checked_at = now
        mtimes = current_mtimes
        return if mtimes == @mtimes

        @owners_by_file = mtimes.to_h do |file, mtime|
          unchanged = @mtimes && @mtimes[file] == mtime
          [file, unchanged ? @owners_by_file[file] : parse(file)]
        end
        @mtimes = mtimes
        @graph = @owners_by_file.values.flatten.group_by(&:name)
        @attributes_by_file = resolve_all
        @checksum = Digest::SHA1.hexdigest(@attributes_by_file.to_a.inspect)
      end

      def current_mtimes
        Dir.glob(@patterns, base: @root).sort.uniq.filter_map do |file|
          [file, File.mtime(File.join(@root, file))]
        rescue Errno::ENOENT
          nil
        end.to_h
      end

      def parse(file)
        self.class.owners_in(File.read(File.join(@root, file)), file)
      end

      def resolve_all
        lookup = ->(name) { @graph.fetch(name, []) }
        resolved = Hash.new { |hash, file| hash[file] = [] }

        @graph.each do |name, owners|
          attributes = attributes_of(name, lookup)
          next if attributes.empty?

          owners.each { |owner| resolved[owner.file] |= attributes }
        end
        resolved.transform_values(&:sort).sort.to_h
      end

      def attributes_of(name, lookup, seen = Set.new)
        return [] unless seen.add?(name)

        lookup.call(name).flat_map do |owner|
          inherited = owner.ancestors.flat_map do |reference, scopes|
            attributes_of(resolve(reference, scopes, lookup), lookup, seen)
          end
          owner.attributes + inherited
        end.uniq
      end

      # Lexical lookup only: innermost scope first, then top level. Ruby also searches the
      # ancestors of each scope; models rarely depend on that for concerns or parents.
      def resolve(reference, scopes, lookup)
        return reference.delete_prefix("::") if reference.start_with?("::")

        candidates = scopes.reverse.map { |scope| "#{scope}::#{reference}" }
        candidates.find { |name| lookup.call(name).any? } || reference
      end

      class Collector < Prism::Visitor
        attr_reader :owners

        def initialize(file)
          super()
          @file = file
          @owners = []
          @stack = []
        end

        def visit_class_node(node)
          within(node, node.superclass) { super }
        end

        def visit_module_node(node)
          within(node, nil) { super }
        end

        def visit_call_node(node)
          owner = @stack.last
          record(owner, node) if owner && (node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode))
          super
        end

        private

        def within(node, superclass)
          path = constant_name(node.constant_path)
          return yield unless path

          outer_scopes = @stack.map(&:name)
          name = path.start_with?("::") ? path.delete_prefix("::") : [outer_scopes.last, path].compact.join("::")
          owner = Owner.new(name, @file, [], [])
          parent = constant_name(superclass)
          # A superclass resolves in the enclosing scope; the class body is not open yet.
          owner.ancestors << [parent, outer_scopes] if parent

          @owners << owner
          @stack.push(owner)
          begin
            yield
          ensure
            @stack.pop
          end
        end

        def record(owner, call)
          case call.name
          when :include, :prepend
            scopes = @stack.map(&:name)
            call.arguments&.arguments&.each do |argument|
              reference = constant_name(argument)
              owner.ancestors << [reference, scopes] if reference
            end
          when :has_state_machine
            attribute = state_attribute(call)
            owner.attributes << attribute if attribute
          end
        end

        # Dynamic columns are skipped rather than guessed.
        def state_attribute(call)
          arguments = call.arguments&.arguments || []
          elements = arguments
            .select { |argument| argument.is_a?(Prism::KeywordHashNode) || argument.is_a?(Prism::HashNode) }
            .flat_map(&:elements)
          options = elements.grep(Prism::AssocNode)
            .select { |pair| pair.key.is_a?(Prism::SymbolNode) }
            .to_h { |pair| [pair.key.unescaped, pair.value] }
          option = options["state_attribute"] || options["attribute"]

          return literal(option) if option
          return nil if elements.any?(Prism::AssocSplatNode)

          DEFAULT_ATTRIBUTE
        end

        def literal(node)
          node.unescaped if node.is_a?(Prism::SymbolNode) || node.is_a?(Prism::StringNode)
        end

        def constant_name(node)
          node.full_name if node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
        rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError,
          Prism::ConstantPathNode::MissingNodesInConstantPathError
          nil
        end
      end
    end
  end
end
