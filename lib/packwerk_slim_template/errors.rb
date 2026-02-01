# frozen_string_literal: true

module PackwerkSlimTemplate
  class Error < StandardError; end

  class SlimSyntaxError < Error
    attr_reader :file_path, :line_number, :column

    def initialize(message, file_path:, line_number: nil, column: nil)
      @file_path = file_path
      @line_number = line_number
      @column = column
      super(formatted_message(message))
    end

    private

    def formatted_message(msg)
      location = [@file_path, @line_number, @column].compact.join(":")
      "#{location} - #{msg}"
    end
  end

  class ParseError < Error; end
end
