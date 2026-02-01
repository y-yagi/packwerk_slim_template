# frozen_string_literal: true

require "packwerk"
require "stringio"

module PackwerkSlim
  class Parser
    include Packwerk::Parsers::ParserInterface

    def initialize(ruby_parser: Packwerk::Parsers::Ruby.new)
      @ruby_parser = ruby_parser
    end

    def call(io:, file_path:)
      slim_content = io.read
      result = SlimConverter.convert(slim_content, file_path: file_path)

      # If no Ruby code extracted, return nil (Packwerk will skip)
      return nil if result.ruby_code.empty?

      @ruby_parser.call(
        io: StringIO.new(result.ruby_code),
        file_path: file_path
      )
    rescue Slim::Parser::SyntaxError => e
      parse_result = Packwerk::Parsers::ParseResult.new(
        file: file_path,
        message: "#{file_path} - Slim syntax error at line #{e.lineno}: #{e.message}"
      )
      raise Packwerk::Parsers::ParseError, parse_result
    rescue Packwerk::Parsers::ParseError => e
      if e.message.include?(file_path)
        raise
      else
        parse_result = Packwerk::Parsers::ParseResult.new(
          file: file_path,
          message: "#{file_path} - #{e.message}"
        )
        raise Packwerk::Parsers::ParseError, parse_result
      end
    end
  end
end

module PackwerkSlim
  module FactoryExtension
    SLIM_REGEX = /\.slim\Z/

    def for_path(path)
      return @slim_parser ||= PackwerkSlim::Parser.new if SLIM_REGEX.match?(path)

      super
    end
  end
end

Packwerk::Parsers::Factory.prepend(PackwerkSlim::FactoryExtension)
