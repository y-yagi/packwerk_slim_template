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
end
