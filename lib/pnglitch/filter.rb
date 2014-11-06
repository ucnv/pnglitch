module PNGlitch

  # Filter represents the filtering functions that is defined in PNG spec.
  #
  class Filter

    NONE    = 0
    SUB     = 1
    UP      = 2
    AVERAGE = 3
    PAETH   = 4

    #
    # Guesses and retuens the filter type as a number.
    #
    def self.guess filter_type
      type = nil
      if filter_type.is_a?(Numeric) && filter_type.between?(NONE, PAETH)
        type = filter_type.to_i
      elsif filter_type.to_s =~ /[0-4]/
        type = filter_type.to_i
      else
        type = ['n', 's', 'u', 'a', 'p'].index(filter_type.to_s[0])
      end
      type
    end

    attr_reader :filter_type
    attr_accessor :encoder, :decoder

    def initialize filter_type, pixel_size
      @filter_type = Filter.guess filter_type || 0
      @filter_type_name = [:none, :sub, :up, :average, :paeth][@filter_type]
      @pixel_size = pixel_size
      @encoder = self.method ('encode_%s' % @filter_type_name.to_s).to_sym
      @decoder = self.method ('decode_%s' % @filter_type_name.to_s).to_sym
    end

    #
    # Filter with a specified filter type.
    #
    def encode data, prev_data = nil
      @encoder.call data, prev_data
    end

    #
    # Reconstruct with a specified filter type.
    #
    def decode data, prev_data = nil
      @decoder.call data, prev_data
    end

    private

    def encode_none data, prev # :nodoc:
      data
    end

    def encode_sub data, prev # :nodoc:
      # Filt(x) = Orig(x) - Orig(a)
      d = data.dup
      d.size.times.reverse_each do |i|
        next if i < @pixel_size
        x = d.getbyte i
        a = d.getbyte i - @pixel_size
        d.setbyte i, (x - a) & 0xff
      end
      d
    end

    def encode_up data, prev # :nodoc:
      # Filt(x) = Orig(x) - Orig(b)
      return data if prev.nil?
      d = data.dup
      d.size.times.reverse_each do |i|
        x = d.getbyte i
        b = prev.getbyte i
        d.setbyte i, (x - b) & 0xff
      end
      d
    end

    def encode_average data, prev # :nodoc:
      # Filt(x) = Orig(x) - floor((Orig(a) + Orig(b)) / 2)
      d = data.dup
      d.size.times.reverse_each do |i|
        x = d.getbyte i
        a = i >= @pixel_size ? d.getbyte(i - @pixel_size) : 0
        b = !prev.nil? ? prev.getbyte(i) : 0
        d.setbyte i, (x - ((a + b) / 2)) & 0xff
      end
      d
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
      d = data.dup
      d.size.times.reverse_each do |i|
        x = d.getbyte i
        is_a_exist = i >= @pixel_size
        is_b_exist = !prev.nil?
        a = is_a_exist ? d.getbyte(i - @pixel_size) : 0
        b = is_b_exist ? prev.getbyte(i) : 0
        c = is_a_exist && is_b_exist ? prev.getbyte(i - @pixel_size) : 0
        p = a + b - c
        pa = (p - a).abs
        pb = (p - b).abs
        pc = (p - c).abs
        pr = pa <= pb && pa <= pc ? a : pb <= pc ? b : c
        d.setbyte i, (x - pr) & 0xff
      end
      d
    end

    def decode_none data, prev # :nodoc:
      data
    end

    def decode_sub data, prev # :nodoc:
      # Recon(x) = Filt(x) + Recon(a)
      d = data.dup
      d.size.times do |i|
        next if i < @pixel_size
        x = d.getbyte i
        a = d.getbyte i - @pixel_size
        d.setbyte i, (x + a) & 0xff
      end
      d
    end

    def decode_up data, prev # :nodoc:
      # Recon(x) = Filt(x) + Recon(b)
      return data if prev.nil?
      d = data.dup
      d.size.times do |i|
        x = d.getbyte i
        b = prev.getbyte i
        d.setbyte i, (x + b) & 0xff
      end
      d
    end

    def decode_average data, prev # :nodoc:
      # Recon(x) = Filt(x) + floor((Recon(a) + Recon(b)) / 2)
      d = data.dup
      d.size.times do |i|
        x = d.getbyte i
        a = i >= @pixel_size ? d.getbyte(i - @pixel_size) : 0
        b = !prev.nil? ? prev.getbyte(i) : 0
        d.setbyte i, (x + ((a + b) / 2)) & 0xff
      end
      d
    end

    def decode_paeth data, prev # :nodoc:
      # Recon(x) = Filt(x) + PaethPredictor(Recon(a), Recon(b), Recon(c))
      d = data.dup
      d.size.times do |i|
        x = d.getbyte i
        is_a_exist = i >= @pixel_size
        is_b_exist = !prev.nil?
        a = is_a_exist ? d.getbyte(i - @pixel_size) : 0
        b = is_b_exist ? prev.getbyte(i) : 0
        c = is_a_exist && is_b_exist ? prev.getbyte(i - @pixel_size) : 0
        p = a + b - c
        pa = (p - a).abs
        pb = (p - b).abs
        pc = (p - c).abs
        pr = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
        d.setbyte i, (x + pr) & 0xff
      end
      d
    end
  end
end
