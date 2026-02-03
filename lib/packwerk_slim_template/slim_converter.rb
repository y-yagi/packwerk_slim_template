# frozen_string_literal: true

require "slim"

module PackwerkSlimTemplate
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

    CONTROL_FLOW_CONTINUATIONS = %w[elsif else when rescue ensure].freeze

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

    def extract_ruby_nodes(node, slim_line = 1, next_node: nil)
      return unless node.is_a?(Array)

      case node.first
      when :multi
        process_sequence(node[1..], slim_line)
      when :slim
        handle_slim_node(node, slim_line, next_node: next_node)
      when :html
        process_sequence(node[1..], slim_line)
      end
    end

    def handle_slim_node(node, slim_line, next_node: nil)
      case node[1]
      when :output
        # [:slim, :output, escape, code, content]
        code = node[3]
        add_ruby_snippet(code, slim_line) if code && !code.empty?

        nested_nodes = node.length > 4 ? node[4..] : nil
        has_block_content = nested_nodes&.any? { |child| significant_child_node?(child) }

        # Process nested content if present
        process_sequence(nested_nodes, slim_line + 1) if nested_nodes

        add_ruby_snippet("end", slim_line + (nested_nodes&.length || 0)) if has_block_content
      when :control
        # [:slim, :control, code, content]
        code = node[2]
        add_ruby_snippet(code, slim_line) if code && !code.empty?

        # Process nested content (at index 3)
        if node[3]
          extract_ruby_nodes(node[3], slim_line + 1)

          if should_close_control_block?(code, next_node)
            add_ruby_snippet("end", slim_line)
          end
        end
      end
    end

    def process_sequence(nodes, base_line)
      return unless nodes

      nodes.each_with_index do |child, idx|
        next_node = next_significant_node(nodes, idx)
        extract_ruby_nodes(child, base_line + idx, next_node: next_node)
      end
    end

    def next_significant_node(nodes, current_index)
      return nil unless nodes

      (current_index + 1).upto(nodes.length - 1) do |idx|
        node = nodes[idx]
        return node unless newline_node?(node)
      end
      nil
    end

    def newline_node?(node)
      node.is_a?(Array) && node.first == :newline
    end

    def should_close_control_block?(code, next_node)
      return false if code.nil? || code.empty?

      !control_flow_continuation?(next_node)
    end

    def control_flow_continuation?(node)
      return false unless node.is_a?(Array)
      return false unless node.first == :slim && node[1] == :control

      keyword = leading_keyword(node[2])
      CONTROL_FLOW_CONTINUATIONS.include?(keyword)
    end

    def leading_keyword(code)
      code.to_s.strip.split(/\s+/, 2).first
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
