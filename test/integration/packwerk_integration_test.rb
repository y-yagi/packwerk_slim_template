# frozen_string_literal: true

require "test_helper"

class PackwerkIntegrationTest < Minitest::Test
  def test_parser_implements_packwerk_interface
    parser = PackwerkSlim::Parser.new
    assert_respond_to parser, :call
    assert_includes PackwerkSlim::Parser.included_modules, Packwerk::Parsers::ParserInterface
  end

  def test_full_slim_to_ast_conversion
    slim_content = <<~SLIM
      h1 Title
      = User.find(1)
      - if Admin.check?
        p= Admin.name
    SLIM

    io = StringIO.new(slim_content)
    parser = PackwerkSlim::Parser.new

    ast = parser.call(io: io, file_path: "test.slim")

    # Verify AST is valid Ruby AST
    assert_kind_of Parser::AST::Node, ast

    # Convert AST back to source to verify it contains our constants
    source = ast.loc.expression.source_buffer.source
    assert_match(/User/, source)
    assert_match(/Admin/, source)
  end

  def test_factory_integration
    factory = Packwerk::Parsers::Factory.instance

    # Test Slim parser is registered
    slim_parser = factory.for_path("views/test.slim")
    assert_instance_of PackwerkSlim::Parser, slim_parser

    # Test existing parsers still work
    ruby_parser = factory.for_path("models/user.rb")
    assert_instance_of Packwerk::Parsers::Ruby, ruby_parser

    erb_parser = factory.for_path("views/index.html.erb")
    assert_instance_of Packwerk::Parsers::Erb, erb_parser
  end

  def test_error_handling_raises_packwerk_parse_error
    slim_content = "= 1 +"

    io = StringIO.new(slim_content)
    parser = PackwerkSlim::Parser.new

    error = assert_raises(Packwerk::Parsers::ParseError) do
      parser.call(io: io, file_path: "bad.slim")
    end

    assert_match(/bad\.slim/, error.message)
  end
end
