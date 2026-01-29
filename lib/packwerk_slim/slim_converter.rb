# frozen_string_literal: true

require "slim"

module PackwerkSlim
  class LineMapper
    def initialize
      @mappings = {}
    end

    def add_mapping(ruby_line:, slim_line:, line_count: 1)
      @mappings[ruby_line] = { slim_line: slim_line, span: line_count }
    end

    def slim_line_for(ruby_line)
      mapping = @mappings.select { |k, v| k <= ruby_line && ruby_line < k + v[:span] }
                         .max_by { |k, _| k }
      mapping&.last&.dig(:slim_line)
    end

    def to_h
      @mappings
    end
  end


  class SlimConverter
    ConversionResult = Struct.new(:ruby_code, :line_mapper, :ruby_snippets)

    def self.convert(slim_content, file_path:)
      new(slim_content, file_path).convert
    end

    def initialize(slim_content, file_path)
      @slim_content = slim_content
      @file_path = file_path
      @line_mapper = LineMapper.new
      @ruby_snippets = []
      @current_ruby_line = 1
    end

    def convert
      return empty_result if @slim_content.empty?

      ast = parse_slim(@slim_content)
      extract_ruby_nodes(ast)

      ruby_code = @ruby_snippets.map { |s| s[:code] }.join("\n")

      ConversionResult.new(ruby_code, @line_mapper, @ruby_snippets)
    rescue Slim::Parser::SyntaxError => e
      raise SlimSyntaxError.new(
        e.message,
        file_path: @file_path,
        line_number: e.lineno
      )
    end

    private

    def empty_result
      ConversionResult.new("", @line_mapper, [])
    end

    def parse_slim(content)
      Slim::Parser.new.call(content)
    end

    def extract_ruby_nodes(node, slim_line = 1)
      return unless node.is_a?(Array)

      case node.first
      when :multi
        node[1..].each_with_index { |child, idx| extract_ruby_nodes(child, slim_line + idx) }
      when :slim
        handle_slim_node(node, slim_line)
      when :html
        node[1..].each_with_index { |child, idx| extract_ruby_nodes(child, slim_line + idx) }
      end
    end

    def handle_slim_node(node, slim_line)
      case node[1]
      when :output
        # [:slim, :output, escape, code, content]
        code = node[3]
        add_ruby_snippet(code, slim_line) if code && !code.empty?

        nested_nodes = node.length > 4 ? node[4..] : nil
        has_block_content = nested_nodes&.any? { |child| significant_child_node?(child) }

        # Process nested content if present
        if nested_nodes
          nested_nodes.each_with_index do |child, idx|
            extract_ruby_nodes(child, slim_line + idx + 1)
          end
        end

        add_ruby_snippet("end", slim_line + (nested_nodes&.length || 0)) if has_block_content
      when :control
        # [:slim, :control, code, content]
        code = node[2]
        add_ruby_snippet(code, slim_line) if code && !code.empty?

        # Process nested content (at index 3)
        if node[3]
          extract_ruby_nodes(node[3], slim_line + 1)
        end

        # Add closing 'end' for control structures
        add_ruby_snippet("end", slim_line)
      end
    end

    def add_ruby_snippet(code, slim_line)
      @line_mapper.add_mapping(
        ruby_line: @current_ruby_line,
        slim_line: slim_line
      )

      @ruby_snippets << { code: code, slim_line: slim_line, ruby_line: @current_ruby_line }
      @current_ruby_line += code.lines.count
    end

    def significant_child_node?(node)
      return false unless node.is_a?(Array)

      case node.first
      when :newline
        false
      when :multi
        node[1..].any? { |child| significant_child_node?(child) }
      else
        true
      end
    end
  end
end
