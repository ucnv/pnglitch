module PNGlitch

  # Filter represents the filtering functions that is defined in PNG spec.
  #
  class Filter

    NONE    = 0
    SUB     = 1
    UP      = 2
    AVERAGE = 3
    PAETH   = 4

    @@types = Filter.constants.sort_by {|c| const_get c }.collect(&:downcase)

    #
    # Guesses and retuens the filter type as a number.
    #
    def self.guess filter_type
      type = nil
      if filter_type.is_a?(Numeric) && filter_type.between?(NONE, PAETH)
        type = filter_type.to_i
      elsif filter_type.is_a?(String) && filter_type =~ /^[0-4]$/
        type = filter_type.to_i
      else
        type = @@types.collect{|c| c.to_s[0] }.index(filter_type.to_s[0].downcase)
      end
      type
    end

    attr_reader :filter_type
    attr_accessor :encoder, :decoder

    def initialize filter_type, sample_size
      @filter_type = Filter.guess(filter_type) || 0
      @filter_type_name = @@types[@filter_type]
      @sample_size = sample_size
      @encoder = self.method ('encode_%s' % @filter_type_name.to_s).to_sym
      @decoder = self.method ('decode_%s' % @filter_type_name.to_s).to_sym
    end

    #
    # Filter with a specified filter type.
    #
    def encode data, prev_data = nil
      @encoder.call data.dup, prev_data
    end

    #
    # Reconstruct with a specified filter type.
    #
    def decode data, prev_data = nil
      @decoder.call data.dup, prev_data
    end

    private

    def encode_none data, prev # :nodoc:
      data
    end

    def decode_none data, prev # :nodoc:
      data
    end

    def encode_sub data, prev # :nodoc:
      # Filt(x) = Orig(x) - Orig(a)
      data.size.times.reverse_each do |i|
        next if i < @sample_size
        x = data.getbyte i
        a = data.getbyte i - @sample_size
        data.setbyte i, (x - a) & 0xff
      end
      data
    end

    def decode_sub data, prev # :nodoc:
      # Recon(x) = Filt(x) + Recon(a)
      data.size.times do |i|
        next if i < @sample_size
        x = data.getbyte i
        a = data.getbyte i - @sample_size
        data.setbyte i, (x + a) & 0xff
      end
      data
    end

    def encode_up data, prev # :nodoc:
      # Filt(x) = Orig(x) - Orig(b)
      return data if prev.nil?
      data.size.times.reverse_each do |i|
        x = data.getbyte i
        b = prev.getbyte i
        data.setbyte i, (x - b) & 0xff
      end
      data
    end

    def decode_up data, prev # :nodoc:
      # Recon(x) = Filt(x) + Recon(b)
      return data if prev.nil?
      data.size.times do |i|
        x = data.getbyte i
        b = prev.getbyte i
        data.setbyte i, (x + b) & 0xff
      end
      data
    end

    def decode_average data, prev # :nodoc:
      # Recon(x) = Filt(x) + floor((Recon(a) + Recon(b)) / 2)
      data.size.times do |i|
        x = data.getbyte i
        a = i >= @sample_size ? data.getbyte(i - @sample_size) : 0
        b = !prev.nil? ? prev.getbyte(i) : 0
        data.setbyte i, (x + ((a + b) / 2)) & 0xff
      end
      data
    end

    def encode_average data, prev # :nodoc:
      # Filt(x) = Orig(x) - floor((Orig(a) + Orig(b)) / 2)
      data.size.times.reverse_each do |i|
        x = data.getbyte i
        a = i >= @sample_size ? data.getbyte(i - @sample_size) : 0
        b = !prev.nil? ? prev.getbyte(i) : 0
        data.setbyte i, (x - ((a + b) / 2)) & 0xff
      end
      data
    end

    def encode_paeth data, prev # :nodoc:
      # Filt(x) = Orig(x) - PaethPredictor(Orig(a), Orig(b), Orig(c))
      #
      # PaethPredictor(a, b, c)
      #   p = a + b - c
      #   pa = abs(p - a)
      #   pb = abs(p - b)
      #   pc = abs(p - c)
      #   if pa <= pb and pa <= pc then Pr = a
      #   else if pb <= pc then Pr = b
      #   else Pr = c
      #   return Pr
      data.size.times.reverse_each do |i|
        x = data.getbyte i
        is_a_exist = i >= @sample_size
        is_b_exist = !prev.nil?
        a = is_a_exist ? data.getbyte(i - @sample_size) : 0
        b = is_b_exist ? prev.getbyte(i) : 0
        c = is_a_exist && is_b_exist ? prev.getbyte(i - @sample_size) : 0
        p = a + b - c
        pa = (p - a).abs
        pb = (p - b).abs
        pc = (p - c).abs
        pr = pa <= pb && pa <= pc ? a : pb <= pc ? b : c
        data.setbyte i, (x - pr) & 0xff
      end
      data
    end

    def decode_paeth data, prev # :nodoc:
      # Recon(x) = Filt(x) + PaethPredictor(Recon(a), Recon(b), Recon(c))
      data.size.times do |i|
        x = data.getbyte i
        is_a_exist = i >= @sample_size
        is_b_exist = !prev.nil?
        a = is_a_exist ? data.getbyte(i - @sample_size) : 0
        b = is_b_exist ? prev.getbyte(i) : 0
        c = is_a_exist && is_b_exist ? prev.getbyte(i - @sample_size) : 0
        p = a + b - c
        pa = (p - a).abs
        pb = (p - b).abs
        pc = (p - c).abs
        pr = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
        data.setbyte i, (x + pr) & 0xff
      end
      data
    end
  end
end
