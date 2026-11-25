# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "has_state_machine/lint/model_index"

RSpec.describe HasStateMachine::Lint::ModelIndex do
  subject(:index) { described_class.new(root, ["app/models/**/*.rb"]) }

  let(:root) { Dir.mktmpdir }

  after { FileUtils.remove_entry(root) }

  def write(path, source)
    FileUtils.mkdir_p(File.dirname(File.join(root, path)))
    File.write(File.join(root, path), source)
  end

  def attributes(source)
    index.attributes_for("app/models/subject.rb", source)
  end

  describe "the state column" do
    it "defaults to status" do
      expect(attributes("class A; has_state_machine states: %i[a]; end")).to eq(%w[status])
    end

    it "reads state_attribute and attribute as symbols or strings" do
      expect(attributes("class A; has_state_machine states: [], state_attribute: :phase; end")).to eq(%w[phase])
      expect(attributes("class A; has_state_machine states: [], attribute: \"phase\"; end")).to eq(%w[phase])
    end

    it "prefers state_attribute over attribute, like DefinitionBuilder" do
      source = "class A; has_state_machine states: [], attribute: :old, state_attribute: :phase; end"

      expect(attributes(source)).to eq(%w[phase])
    end

    it "uses the last value of a repeated option, like a Ruby hash" do
      source = "class A; has_state_machine states: [], attribute: :old, attribute: :phase; end"

      expect(attributes(source)).to eq(%w[phase])
    end

    it "collects every machine on a model" do
      source = <<~RUBY
        class A
          has_state_machine states: %i[a]
          has_state_machine states: %i[b], state_attribute: :marketing_status
          has_state_machine states: %i[c], state_attribute: :marketing_status
        end
      RUBY

      expect(attributes(source)).to eq(%w[marketing_status status])
    end

    it "skips a column it cannot read" do
      expect(attributes("class A; has_state_machine states: [], state_attribute: COLUMN; end")).to eq([])
      expect(attributes("class A; has_state_machine states: [], **OPTIONS; end")).to eq([])
    end
  end

  describe "machines from other files" do
    before do
      write("app/models/concerns/podcasts/trackable.rb", <<~RUBY)
        module Podcasts
          module Trackable
            extend ActiveSupport::Concern

            included do
              has_state_machine states: %i[draft live], attribute: :phase
            end
          end
        end
      RUBY
      write("app/models/post.rb", "class Post < ApplicationRecord\n  has_state_machine states: %i[draft]\nend\n")
    end

    it "follows a concern through the lexical scope" do
      source = "module Podcasts\n  class Show < ApplicationRecord\n    include Trackable\n  end\nend\n"

      expect(attributes(source)).to eq(%w[phase])
    end

    it "follows a compact or top-level constant" do
      expect(attributes("class Show < ApplicationRecord; include Podcasts::Trackable; end")).to eq(%w[phase])
      expect(attributes("class Show < ApplicationRecord; include ::Podcasts::Trackable; end")).to eq(%w[phase])
    end

    it "follows a parent class" do
      expect(attributes("class DummyPost < Post; end")).to eq(%w[status])
    end

    it "ignores dynamic and incomplete constant paths" do
      expect(attributes("class Show; include self::Trackable; end")).to eq([])
      expect(attributes("class Show; include Podcasts::")).to eq([])
    end

    it "survives an include cycle" do
      write("app/models/concerns/a.rb", "module A; include B; end")
      write("app/models/concerns/b.rb", "module B; include A; end")

      expect(attributes("class C; include A; end")).to eq([])
    end

    it "maps every file whose owners have a machine" do
      write("app/models/concerns/searchable.rb", "module Searchable; end")
      write("app/models/show.rb", "class Show < ApplicationRecord; include Searchable, Podcasts::Trackable; end")

      expect(index.attributes_by_file).to eq(
        "app/models/concerns/podcasts/trackable.rb" => %w[phase],
        "app/models/post.rb" => %w[status],
        "app/models/show.rb" => %w[phase]
      )
    end

    it "accepts overlapping glob patterns" do
      index = described_class.new(root, ["app/models/**/*.rb", "app/models/post.rb"])

      expect(index.attributes_by_file.keys).to eq(
        %w[app/models/concerns/podcasts/trackable.rb app/models/post.rb]
      )
    end
  end

  describe "freshness" do
    before { stub_const("#{described_class}::REFRESH_INTERVAL", 0) }

    it "prefers the buffer over the file on disk" do
      write("app/models/subject.rb", "class Subject; has_state_machine states: []; end")

      expect(attributes("class Subject; end")).to eq([])
    end

    it "changes the checksum when a parent gains a machine" do
      write("app/models/base.rb", "class Base; end")
      before = index.checksum

      write("app/models/base.rb", "class Base; has_state_machine states: [], attribute: :phase; end")
      File.utime(Time.now + 5, Time.now + 5, File.join(root, "app/models/base.rb"))

      expect(index.checksum).not_to eq(before)
      expect(attributes("class Child < Base; end")).to eq(%w[phase])
    end
  end
end
