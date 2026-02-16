# frozen_string_literal: true

require "test_helper"

class SlimConverterTest < Minitest::Test
  def test_convert_with_simple_output_tag
    slim_content = <<~SLIM
      h1 Title
      = User.find(1)
    SLIM

    result = PackwerkSlimTemplate::SlimConverter.convert(slim_content, file_path: "test.slim")

    assert_includes result.ruby_code, "User"
    assert_kind_of PackwerkSlimTemplate::LineMapper, result.line_mapper
  end

  def test_convert_with_control_flow
    slim_content = <<~SLIM
      - if Admin.authorized?
        p Welcome
    SLIM

    result = PackwerkSlimTemplate::SlimConverter.convert(slim_content, file_path: "test.slim")

    assert_includes result.ruby_code, "Admin"
  end

  def test_line_mapper_tracks_correspondence
    mapper = PackwerkSlimTemplate::LineMapper.new

    mapper.add_mapping(ruby_line: 1, slim_line: 5)
    mapper.add_mapping(ruby_line: 3, slim_line: 10)

    assert_equal 5, mapper.slim_line_for(1)
    assert_equal 10, mapper.slim_line_for(3)
  end

  def test_line_mapper_handles_unmapped_lines
    mapper = PackwerkSlimTemplate::LineMapper.new

    mapper.add_mapping(ruby_line: 1, slim_line: 5)

    # Line 2 not mapped, should return closest or nil
    assert_nil mapper.slim_line_for(99)
  end

  def test_convert_extracts_multiple_constants
    slim_content = <<~SLIM
      = User.name
      = Order.total
      - Product.all.each do |p|
        p= p.name
    SLIM

    result = PackwerkSlimTemplate::SlimConverter.convert(slim_content, file_path: "test.slim")

    assert_includes result.ruby_code, "User"
    assert_includes result.ruby_code, "Order"
    assert_includes result.ruby_code, "Product"
  end

  def test_convert_handles_if_else_chains
    slim_content = <<~SLIM
      - if Admin.authorized?
        = AdminDashboard.render
      - elsif Feature.enabled?
        = FeatureDashboard.render
      - else
        = GuestDashboard.render
    SLIM

    result = PackwerkSlimTemplate::SlimConverter.convert(slim_content, file_path: "conditional.slim")

    ruby_parser = Packwerk::Parsers::Ruby.new
    ast = ruby_parser.call(io: StringIO.new(result.ruby_code), file_path: "conditional.slim")

    assert_kind_of Parser::AST::Node, ast
    assert_includes result.ruby_code, "elsif"
    assert_includes result.ruby_code, "else"
  end

  def test_convert_adds_block_delimiter_for_output_with_children
    slim_content = <<~SLIM
      = link_to root_path, class: 'logo'
        span Logo
    SLIM

    result = PackwerkSlimTemplate::SlimConverter.convert(slim_content, file_path: "block_output.slim")

    assert_includes result.ruby_code, "link_to root_path, class: 'logo' do"

    ruby_parser = Packwerk::Parsers::Ruby.new
    ast = ruby_parser.call(io: StringIO.new(result.ruby_code), file_path: "block_output.slim")
    assert_kind_of Parser::AST::Node, ast
  end

  def test_convert_does_not_duplicate_existing_block_delimiter
    slim_content = <<~SLIM
      = link_to(root_path) do |link|
        span= link
    SLIM

    result = PackwerkSlimTemplate::SlimConverter.convert(slim_content, file_path: "existing_block.slim")

    link_lines = result.ruby_code.lines.select { |line| line.include?("link_to") }
    assert link_lines.any? { |line| line.include?("do |link|") }
    assert link_lines.none? { |line| line.include?("do do") }

    ruby_parser = Packwerk::Parsers::Ruby.new
    ast = ruby_parser.call(io: StringIO.new(result.ruby_code), file_path: "existing_block.slim")
    assert_kind_of Parser::AST::Node, ast
  end

  def test_convert_strips_unbalanced_quote_prefix_in_output
    slim_content = <<~SLIM
      =' link_to(user_path(@user))
    SLIM

    result = PackwerkSlimTemplate::SlimConverter.convert(slim_content, file_path: "prefixed_quote.slim")

    refute_includes result.ruby_code, "='"
    assert_includes result.ruby_code, "link_to(user_path(@user))"

    ruby_parser = Packwerk::Parsers::Ruby.new
    ast = ruby_parser.call(io: StringIO.new(result.ruby_code), file_path: "prefixed_quote.slim")
    assert_kind_of Parser::AST::Node, ast
  end

  def test_convert_handles_interpolation_only_text_lines
    slim_content = <<~'SLIM'
      td
        #{number_to_percentage(stats)}
    SLIM

    result = PackwerkSlimTemplate::SlimConverter.convert(slim_content, file_path: "interpolation_text.slim")

    assert_includes result.ruby_code, "number_to_percentage(stats)"

    ruby_parser = Packwerk::Parsers::Ruby.new
    ast = ruby_parser.call(io: StringIO.new(result.ruby_code), file_path: "interpolation_text.slim")
    assert_kind_of Parser::AST::Node, ast
  end

  def test_convert_handles_embedded_ruby_filters
    slim_content = <<~SLIM
      ruby:
        foo = find_foo

      = foo.name
    SLIM

    result = PackwerkSlimTemplate::SlimConverter.convert(slim_content, file_path: "embedded_ruby.slim")

    assert_includes result.ruby_code, "foo = find_foo"

    ruby_parser = Packwerk::Parsers::Ruby.new
    ast = ruby_parser.call(io: StringIO.new(result.ruby_code), file_path: "embedded_ruby.slim")
    assert_kind_of Parser::AST::Node, ast
  end

  def test_convert_completes_trailing_keyword_arguments
    slim_content = <<~SLIM
      = render 'label_tag', name:

      div
        = select_tag name
    SLIM

    result = PackwerkSlimTemplate::SlimConverter.convert(slim_content, file_path: "dangling_keyword.slim")

    assert_includes result.ruby_code, "render 'label_tag', name: nil"

    ruby_parser = Packwerk::Parsers::Ruby.new
    ast = ruby_parser.call(io: StringIO.new(result.ruby_code), file_path: "dangling_keyword.slim")
    assert_kind_of Parser::AST::Node, ast
  end

  def test_all_fixture_templates_are_parsable
    fixture_glob = File.expand_path("../fixtures/**/*.slim", __dir__)
    slim_files = Dir.glob(fixture_glob)
    refute_empty slim_files, "No Slim fixtures found under test/fixtures"

    ruby_parser = Packwerk::Parsers::Ruby.new

    slim_files.each do |file_path|
      slim_content = File.read(file_path)
      result = PackwerkSlimTemplate::SlimConverter.convert(slim_content, file_path: file_path)

      ast = ruby_parser.call(io: StringIO.new(result.ruby_code), file_path: file_path)
      assert_kind_of Parser::AST::Node, ast, "Ruby parsing failed for #{file_path}"
    end
  end
end
