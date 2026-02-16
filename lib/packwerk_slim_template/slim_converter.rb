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

      normalized_content = normalize_slim_content(@slim_content)
      ast = parse_slim(normalized_content)
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

    def normalize_slim_content(content)
      content.lines.map do |line|
        line.sub(/^(\s*)#\{/, '\\1| #{')
      end.join
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
        code = sanitize_output_code(node[3])
        nested_nodes = node.length > 4 ? node[4..] : nil
        has_block_content = nested_nodes&.any? { |child| significant_child_node?(child) }
        block_delimiter = block_delimiter_for(code)

        if code && !code.empty? && !comment_code?(code)
          if has_block_content && block_delimiter.nil?
            code = ensure_block_delimiter(code)
            block_delimiter = block_delimiter_for(code)
          end
          add_ruby_snippet(code, slim_line)
        else
          block_delimiter = nil
        end

        # Process nested content if present
        process_sequence(nested_nodes, slim_line + 1) if nested_nodes

        if block_delimiter
          closing_line = slim_line + (nested_nodes&.length || 0)
          add_ruby_snippet(closing_token_for(block_delimiter), closing_line)
        end
      when :control
        # [:slim, :control, code, content]
        code = node[2]
        return if comment_code?(code)
        add_ruby_snippet(code, slim_line) if code && !code.empty?

        # Process nested content (at index 3)
        if node[3]
          has_block_content = significant_child_node?(node[3])
          extract_ruby_nodes(node[3], slim_line + 1)

          if has_block_content && should_close_control_block?(code, next_node)
            add_ruby_snippet("end", slim_line)
          end
        end
      when :text
        extract_text_interpolations(node[3], slim_line)
      when :embedded
        handle_embedded_node(node, slim_line)
      end
    end

    def handle_embedded_node(node, slim_line)
      engine = node[2]
      return unless engine.to_s == "ruby"

      body = node[3]
      embedded_lines = extract_embedded_ruby_lines(body)
      embedded_lines.each do |code_line, offset|
        next if code_line.empty?

        add_ruby_snippet(code_line, slim_line + offset)
      end
    end

    def comment_code?(code)
      code.to_s.strip.start_with?("#")
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

    def extract_text_interpolations(text_node, slim_line)
      return unless text_node

      traverse_text_nodes(text_node, slim_line)
    end

    def traverse_text_nodes(node, slim_line)
      return unless node.is_a?(Array)

      if node.first == :slim && node[1] == :interpolate
        extract_interpolation_expressions(node[2]).each do |code|
          next if code.empty? || comment_code?(code)

          add_ruby_snippet(code, slim_line)
        end
      elsif node.first == :multi
        node[1..].each { |child| traverse_text_nodes(child, slim_line) }
      else
        node.each { |child| traverse_text_nodes(child, slim_line) if child.is_a?(Array) }
      end
    end

    def sanitize_output_code(code)
      return code if code.to_s.empty?

      leading_whitespace = code[/\A\s*/] || ""
      trimmed = code.lstrip
      sanitized = strip_unbalanced_quote_prefix(trimmed)
      sanitized = ensure_keyword_argument_value(sanitized)

      return code if sanitized == trimmed

      "#{leading_whitespace}#{sanitized}"
    end

    def strip_unbalanced_quote_prefix(code)
      return code if code.empty?

      quote = code[0]
      return code unless ["'", '"'].include?(quote)

      remainder = code[1..] || ""
      return code if remainder.include?(quote)

      remainder.lstrip
    end

    def ensure_keyword_argument_value(code)
      return code if code.empty?

      has_trailing_newline = code.end_with?("\n")
      stripped = code.rstrip
      return code if stripped.empty?

      if stripped.match?(/(?:\b|::)[A-Za-z_]\w*:\z/)
        updated = "#{stripped} nil"
        return has_trailing_newline ? "#{updated}\n" : updated
      end

      code
    end

    def extract_interpolation_expressions(raw_code)
      code = raw_code.to_s
      return [] unless code.include?('#{')

      expressions = []
      idx = 0

      while idx < code.length
        if code[idx, 2] == '#{'
          idx += 2
          depth = 1
          buffer = +''

          while idx < code.length && depth.positive?
            char = code[idx]

            if char == '{'
              depth += 1
              buffer << char
            elsif char == '}'
              depth -= 1
              if depth.zero?
                expressions << buffer.strip
                buffer = +''
              else
                buffer << char
              end
            else
              buffer << char
            end

            idx += 1
          end
        else
          idx += 1
        end
      end

      expressions
    end

    def extract_embedded_ruby_lines(node)
      text = flatten_text_content(node)
      return [] if text.empty?

      raw_lines = []
      line_offset = 0

      text.split("\n", -1).each_with_index do |segment, idx|
        line_offset += 1 if idx.positive?
        trimmed = segment.rstrip
        next if trimmed.strip.empty?

        raw_lines << { text: trimmed, offset: line_offset }
      end

      return [] if raw_lines.empty?

      min_indent = raw_lines.map { |entry| leading_whitespace(entry[:text]) }.min || 0

      raw_lines.map do |entry|
        normalized = entry[:text]
        normalized = normalized[min_indent..] || "" if min_indent.positive?
        [normalized.rstrip, entry[:offset]]
      end
    end

    def flatten_text_content(node)
      return "" if node.nil?
      return node.to_s unless node.is_a?(Array)

      case node.first
      when :multi
        node[1..].map { |child| flatten_text_content(child) }.join
      when :newline
        "\n"
      when :static
        node[1].to_s
      when :slim
        subtype = node[1]
        case subtype
        when :text
          flatten_text_content(node[3])
        when :interpolate
          node[2].to_s
        else
          node[2..].map { |child| flatten_text_content(child) }.join
        end
      else
        node[1..].map { |child| flatten_text_content(child) }.join
      end
    end

    def leading_whitespace(text)
      (text[/^\s*/] || "").length
    end

    def ensure_block_delimiter(code)
      newline = code.end_with?("\n")
      stripped = code.rstrip
      return code if stripped.empty?
      return code if block_delimiter_for(stripped)

      updated = "#{stripped} do"
      newline ? "#{updated}\n" : updated
    end

    def block_delimiter_for(code)
      return nil if code.to_s.empty?

      stripped = code.rstrip
      detection_target = stripped.sub(/\s+#.*\z/, "")
      return nil if detection_target.empty?

      return :curly if detection_target.match?(/\{\s*\z/)
      return :do if detection_target.match?(/\bdo(\s*\|.*\|)?\s*\z/)

      nil
    end

    def closing_token_for(delimiter)
      delimiter == :curly ? "}" : "end"
    end
  end
end
