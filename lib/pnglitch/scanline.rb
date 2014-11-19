module PNGlitch

  # Scanline is the class that represents a particular PNG image scanline.
  #
  # It consists of a filter type and a filtered pixel data.
  #
  class Scanline

    attr_reader :index, :filter_type, :prev_filter_type, :filter_codec

    #
    # Instanciate.
    #
    def initialize io, start_at, data_size, at
      @index = at
      @io = io
      @start_at = start_at
      @data_size = data_size

      pos = @io.pos
      @io.pos = @start_at
      @filter_type = @io.read(1).unpack('C').first
      @io.pos = pos

      @data = nil
      @prev_filter_type = nil
      @filter_codec = { encoder: nil, decoder: nil }

      if block_given?
        @callback = Proc.new
      end
    end

    #
    # Returns data of the scanline.
    #
    def data
      if @data.nil?
        pos = @io.pos
        @io.pos = @start_at + 1
        @data = @io.read @data_size
        @io.pos = pos
      end
      @data
    end

    #
    # Replaces data with given Regexp +pattern+ and +replacement+.
    #
    # It is same as <tt>scanline.replace_data(scanline.data.gsub(pattern, replacement))</tt>.
    # When the data size has changed, the data will be chopped or padded with null string
    # in original size.
    #
    def gsub! pattern, replacement
      self.replace_data self.data.gsub(pattern, replacement)
    end

    #
    # Replace the data with +new_data+.
    #
    # When its size has changed, the data will be chopped or padded with null string
    # in original size.
    #
    def replace_data new_data
      @data = new_data
      save
    end

    #
    # Replace the filter type with +new_filter+, and it will not compute the filters again.
    #
    # It means the scanline might get wrong filter type. It will be the efficient way to
    # break the PNG image.
    #
    def graft new_filter
      @filter_type = new_filter
      save
    end

    #
    # Replace the filter type with +new_filter+, and it will compute the filters again.
    #
    # This operation will be a legal way to change filter types.
    #
    def change_filter new_filter
      @prev_filter_type = @filter_type
      @filter_type = new_filter
      self.save
    end

    #
    # Registers a custom filter function to encode data.
    #
    # With this operation, it will be able to change filter encoding behavior despite 
    # the specified filter type value. It takes a Proc object or a block.
    #
    def register_filter_encoder encoder = nil, &block
      if !encoder.nil? && encoder.is_a?(Proc)
        @filter_codec[:encoder] = encoder
      elsif block_given?
        @filter_codec[:encoder] = block
      end
      save
    end

    #
    # Registers a custom filter function to decode data.
    #
    # With this operation, it will be able to change filter decoding behavior despite 
    # the specified filter type value. It takes a Proc object or a block.
    #
    def register_filter_decoder decoder = nil, &block
      if !decoder.nil? && decoder.is_a?(Proc)
        @filter_codec[:decoder] = decoder
      elsif block_given?
        @filter_codec[:decoder] = block
      end
      save
    end

    #
    # Save the changes.
    #
    def save
      pos = @io.pos
      @io.pos = @start_at
      @io << [Filter.guess(@filter_type)].pack('C')
      @io << self.data.slice(0, @data_size).ljust(@data_size, "\0")
      @io.pos = pos
      @callback.call(self) unless @callback.nil?
      self
    end

    alias data= replace_data
    alias filter_type= change_filter

  end
end
