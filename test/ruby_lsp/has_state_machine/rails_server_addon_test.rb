# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/has_state_machine/rails_server_addon"

class RubyLsp::HasStateMachine::RailsServerAddonTest < ActiveSupport::TestCase
  def teardown
    Object.send(:remove_const, :RubyLspRailsServerAddonCustomPost) if Object.const_defined?(:RubyLspRailsServerAddonCustomPost)
    Object.send(:remove_const, :RubyLspRailsServerAddonEagerPost) if Object.const_defined?(:RubyLspRailsServerAddonEagerPost)
    Object.send(:remove_const, :RubyLspRailsServerAddonNotAModel) if Object.const_defined?(:RubyLspRailsServerAddonNotAModel)
    super
  end

  describe "#model_for_workflow_namespace" do
    it "constantizes conventional workflow namespaces without eager loading Rails" do
      result = without_eager_load do
        addon.send(:model_for_workflow_namespace, "Workflow::Post")
      end

      assert_equal({name: "Post"}, result)
    end

    it "ignores conventional constants that are not Active Record models" do
      Object.const_set(
        :RubyLspRailsServerAddonNotAModel,
        Module.new do
          define_singleton_method(:workflow_namespace) do
            "Workflow::RubyLspRailsServerAddonNotAModel"
          end
        end
      )

      result = addon.send(:conventional_model_for_workflow_namespace, "Workflow::RubyLspRailsServerAddonNotAModel")

      assert_nil result
    end

    it "finds loaded models with non-conventional workflow namespaces without eager loading Rails" do
      Object.const_set(
        :RubyLspRailsServerAddonCustomPost,
        Class.new(ApplicationRecord) do
          define_singleton_method(:workflow_namespace) do
            "Publishing::Post"
          end
        end
      )

      result = without_eager_load do
        addon.send(:model_for_workflow_namespace, "Publishing::Post")
      end

      assert_equal({name: "RubyLspRailsServerAddonCustomPost"}, result)
    end

    it "eager loads only as a fallback for unloaded non-conventional workflow namespaces" do
      result = with_eager_load_defining_model do
        addon.send(:model_for_workflow_namespace, "Publishing::EagerPost")
      end

      assert_equal({name: "RubyLspRailsServerAddonEagerPost"}, result)
    end
  end

  private

  def addon
    @addon ||= RubyLsp::HasStateMachine::RailsServerAddon.allocate
  end

  def without_eager_load(&block)
    with_eager_load(-> { flunk "expected lookup to avoid eager loading Rails" }, &block)
  end

  def with_eager_load_defining_model(&block)
    with_eager_load(-> { define_eager_post }, &block)
  end

  def with_eager_load(replacement)
    application = Rails.application
    singleton_class = class << application; self; end
    original = application.method(:eager_load!)

    singleton_class.define_method(:eager_load!) { replacement.call }
    yield
  ensure
    singleton_class.define_method(:eager_load!) { |*args, &block| original.call(*args, &block) }
  end

  def define_eager_post
    return if Object.const_defined?(:RubyLspRailsServerAddonEagerPost)

    Object.const_set(
      :RubyLspRailsServerAddonEagerPost,
      Class.new(ApplicationRecord) do
        define_singleton_method(:workflow_namespace) do
          "Publishing::EagerPost"
        end
      end
    )
  end
end
