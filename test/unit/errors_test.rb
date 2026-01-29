# frozen_string_literal: true

require "test_helper"

class ErrorsTest < Minitest::Test
  def test_slim_syntax_error_with_all_attributes
    error = PackwerkSlim::SlimSyntaxError.new(
      "Invalid syntax",
      file_path: "app/views/test.slim",
      line_number: 15,
      column: 8
    )

    assert_equal "app/views/test.slim", error.file_path
    assert_equal 15, error.line_number
    assert_equal 8, error.column
    assert_equal "app/views/test.slim:15:8 - Invalid syntax", error.message
  end

  def test_slim_syntax_error_without_column
    error = PackwerkSlim::SlimSyntaxError.new(
      "Missing end tag",
      file_path: "app/views/test.slim",
      line_number: 20
    )

    assert_equal "app/views/test.slim", error.file_path
    assert_equal 20, error.line_number
    assert_nil error.column
    assert_equal "app/views/test.slim:20 - Missing end tag", error.message
  end

  def test_slim_syntax_error_with_only_file_path
    error = PackwerkSlim::SlimSyntaxError.new(
      "Parse failed",
      file_path: "app/views/test.slim"
    )

    assert_equal "app/views/test.slim", error.file_path
    assert_nil error.line_number
    assert_nil error.column
    assert_equal "app/views/test.slim - Parse failed", error.message
  end
end
