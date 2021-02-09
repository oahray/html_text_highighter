class ColorPalette
  class << self
    def generate_unique_color (existing_colors)
      new_color =  "%06x" % (rand * 0xffffff)
      if existing_colors.has_key?(new_color.to_sym)
        return self.generate_unique_color
      end
      new_color
    end

    def mix (color1, color2)
      color1 = rgb_to_cymk(color1);
      color2 = rgb_to_cymk(color2)
      c = (color1[:c] + color2[:c])/2;
      y = (color1[:m] + color2[:m])/2;
      m = (color1[:y] + color2[:y])/2;
      k = (color1[:k] + color2[:k])/2;
      a = (color1[:a] + color2[:a])/2;
      color = { c:c, y:m, m:m, k:k, a:a}
      color = "#{cymk_to_rgb(color)}"
    end

    private

    def cymk_to_rgb (color)
      key = color[:k]
      r = color[:c] * (1.0 - key) + key
      g = color[:m] * (1.0 - key) + key
      b = color[:y] * (1.0 - key) + key
      r = ((1.0 - r) * 255.0 + 0.5).round
      g = ((1.0 - g) * 255.0 + 0.5).round
      b = ((1.0 - b) * 255.0 + 0.5).round
      color = [r,g,b].map {|pigment| pigment.to_i.to_s(16)}.join("")
    end

    def rgb_to_cymk(color)
      hex_color = color.gsub('#','')
      rgba = hex_color.scan(/../).map {|color| color.hex}
      cyan, magenta, yellow = rgba.map {|pigment| 255 - pigment}
      black = [cyan, magenta, yellow].min.to_f
      black_complement = 255 - black
      c = (cyan - black)/black_complement
      m = (magenta - black)/black_complement
      y = (yellow  - black)/black_complement

      { c:c, m:m, y:y, k:black/255, a:rgba[3] || 1}
    end
  end
end

class StringToHTML
  attr_accessor :content, :highlights, :existing_colors
  def initialize(content, highlights)
    @content = content
    @highlights = highlights.sort_by {|highlight| highlight[:start_word] }
    # @highlights_array = []
    @existing_colors = {}
  end

  def apply
    assign_colors
    flatten_highlights
    format_paragraphs
    add_highlights
    content
  end

  private

  def add_highlights
    split_into_words

    @highlights_array.each do |highlight|
      next if highlight[:start_word].nil?
      from = highlight[:start_word]
      to = highlight[:end_word] - 1 || highlight[:start_word]
      comment = highlight[:comment] || ""
      color_code = highlight[:color_code]
      if spans_multiple_paragraphs?(highlight)
        handle_multiparagraph_highlight(highlight)
      end

      add_span(from, to, comment, color_code)
    end

    join_with_space
  end

  def add_span(from, to, comment, color_code)
    if is_paragraph_start?(content[from])
      @content[from] = content[from].sub("<p>", "<p>#{opening_span_tag(comment, color_code)}")
    else
      @content[from] = "#{opening_span_tag(comment, color_code)}#{content[from]}"
    end
    @content[to] = "#{content[to]}</span>"
  end

  def additional_paragraphs(highlight)
    (highlight[:start_word]..highlight[:end_word]).to_a & @paragraph_indexes
  end

  def assign_colors
    @highlights = highlights.map do |highlight|
      highlight[:color_code] = unique_color
      highlight
    end
  end

  def color_exists?(color_code)
    existing_colors.has_key?(color_code.to_sym)
  end

  def flatten_highlights
    colors = {}
    @highlights_array = highlights.map.with_index do |highlight, index|
      next_highlight = highlights[index + 1] || {}
      first = (highlight[:start_word]..highlight[:end_word]).to_a
      second = next_highlight&.empty? ? [] : (next_highlight[:start_word]..next_highlight[:end_word])&.to_a

      if has_overlap?(first, second)
        overlap_sub_array = get_overlap(first, second)
        first_sub_array = first - overlap_sub_array
        last_sub_array = second - overlap_sub_array
        colors[highlight[:color_code].to_sym] = true
        colors[next_highlight[:color_code].to_sym] = true
        [{
          start_word: first_sub_array[0],
          end_word: first_sub_array[first_sub_array.length - 1] + 1,
          color_code: highlight[:color_code],
          comment: highlight[:comment]
        }, {
          start_word: overlap_sub_array[0],
          end_word: overlap_sub_array[overlap_sub_array.length - 1] + 1,
          # Given that html spans to not overlap each other by default,
          # we mix the colors to give the semblance of overlap.
          color_code: mix_colors(highlight[:color_code], next_highlight[:color_code]),
          # Concatenate as a simple solution, as we'd need real css
          # to effectively display multiple tooltips on one element
          comment: "#{highlight[:comment]}  #{next_highlight[:comment]}"
        }, {
          start_word: last_sub_array[0],
          end_word: last_sub_array[last_sub_array.length - 1],
          color_code: next_highlight[:color_code],
          comment: next_highlight[:comment]
        }]
      elsif !colors.has_key?(highlight[:color_code].to_sym)
        highlight
      end
    end.compact.flatten
  end

  def format_paragraphs
    split_paragraphs
    @content = content.map {|paragraph| "<p>#{paragraph}</p>"}
    join_with_space
  end

  def get_overlap(first_range, second_range)
    first_range & second_range
  end

  def handle_multiparagraph_highlight(highlight)
    other_paragraphs = additional_paragraphs(highlight)
    start_indexes = [highlight[:start_word]] + other_paragraphs
    stop_indexes = other_paragraphs + [highlight[:end_word]]
    pairs = start_indexes.zip(stop_indexes)
    pairs.each do |pair|
      add_span(pair[0], pair[1] - 1, highlight[:comment], highlight[:color_code])
    end
  end

  def has_overlap?(first_array, second_array)
    get_overlap(first_array, second_array).length > 0
  end

  def is_paragraph_start?(word)
    word.match(/\<p\>/)
  end

  def join_with_space
    @content = content.join(" ")
  end

  def mix_colors(first_color, second_color)
    ColorPalette.mix(first_color, second_color)
  end

  def opening_span_tag(comment, color_code)
    "<span style='background-color: ##{color_code}; padding: 0 0.2em; margin: 0 -0.2em' class='tooltip' title='#{comment}'>"
  end

  def set_paragraph_sizes
    @paragraph_sizes ||= content.map { |paragraph| paragraph.split(" ").length }
  end

  def set_paragraph_indexes
    @paragraph_indexes ||= @paragraph_sizes.map.with_index {|size, index| @paragraph_sizes[0, index].reduce(:+) || 0 }
  end

  def spans_multiple_paragraphs?(highlight)
    !additional_paragraphs(highlight).empty?
  end

  def split_paragraphs
    @content = content.split("\n\n")
    set_paragraph_sizes
    set_paragraph_indexes
    content
  end

  def split_into_words
    @content = content.split(" ")
  end

  def unique_color
    new_color =  ColorPalette.generate_unique_color(@existing_colors)
    @existing_colors[new_color.to_sym] = new_color
    new_color
  end
end
