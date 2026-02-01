# frozen_string_literal: true

require "test_helper"

class ParserTest < Minitest::Test
  def test_call_returns_valid_ruby_ast
    slim_content = <<~SLIM
      h1 Test
      = User.find(1)
    SLIM

    io = StringIO.new(slim_content)
    parser = PackwerkSlimTemplate::Parser.new

    ast = parser.call(io: io, file_path: "test.slim")

    assert_kind_of Parser::AST::Node, ast
  end

  def test_call_handles_partial_ruby_ast
    slim_content = <<~SLIM
      = form_with(model: author) do |form|
        div
          = form.label :name, style: "display: block"
          = form.text_field :name

        div
          = form.submit
    SLIM

    io = StringIO.new(slim_content)
    parser = PackwerkSlimTemplate::Parser.new

    ast = parser.call(io: io, file_path: "test.slim")

    assert_kind_of Parser::AST::Node, ast
  end

  def test_call_handles_empty_slim_file
    io = StringIO.new("")
    parser = PackwerkSlimTemplate::Parser.new

    ast = parser.call(io: io, file_path: "empty.slim")

    assert_nil ast
  end

  def test_factory_recognizes_slim_files
    factory = Packwerk::Parsers::Factory.instance

    parser = factory.for_path("app/views/test.slim")

    assert_instance_of PackwerkSlimTemplate::Parser, parser
  end

  def test_factory_still_recognizes_ruby_files
    factory = Packwerk::Parsers::Factory.instance
    parser = factory.for_path("app/models/user.rb")

    assert_instance_of Packwerk::Parsers::Ruby, parser
  end

  def test_factory_still_recognizes_erb_files
    factory = Packwerk::Parsers::Factory.instance
    parser = factory.for_path("app/views/index.html.erb")

    assert_instance_of Packwerk::Parsers::Erb, parser
  end
end
