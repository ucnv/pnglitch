module PNGlitch

  # Base is the class that represents the interface for PNGlitch functions.
  #
  # It will be initialized through PNGlitch#open and be a mainly used instance.
  #
  class Base

    attr_reader :width, :height, :sample_size, :is_compressed_data_modified
    attr_accessor :head_data, :tail_data, :compressed_data, :filtered_data, :idat_chunk_size

    #
    # Instanciate the class with the passed +file+
    #
    def initialize file, limit_of_decompressed_data_size = nil
      path = Pathname.new file
      @head_data = StringIO.new
      @tail_data = StringIO.new
      @compressed_data = Tempfile.new 'compressed', encoding: 'ascii-8bit'
      @filtered_data = Tempfile.new 'filtered', encoding: 'ascii-8bit'
      @idat_chunk_size = nil

      open(path, 'rb') do |io|
        idat_sizes = []
        @head_data << io.read(8) # signature
        while bytes = io.read(8)
          length, type = bytes.unpack 'Na*'
          if type == 'IHDR'
            ihdr = {
              width:              io.read(4).unpack('N').first,
              height:             io.read(4).unpack('N').first,
              bit_depth:          io.read(1).unpack('C').first,
              color_type:         io.read(1).unpack('C').first,
              compression_method: io.read(1).unpack('C').first,
              filter_method:      io.read(1).unpack('C').first,
              interlace_method:   io.read(1).unpack('C').first,
            }
            @width = ihdr[:width]
            @height = ihdr[:height]
            @interlace = ihdr[:interlace_method]
            @sample_size = {0 => 1, 2 => 3, 3 => 1, 4 => 2, 6 => 4}[ihdr[:color_type]]
            io.pos -= 13
          end
          if type == 'IDAT'
            @compressed_data << io.read(length)
            idat_sizes << length
            io.pos += 4 # crc
          else
            target_io = @compressed_data.pos == 0 ? @head_data : @tail_data
            target_io << bytes
            target_io << io.read(length + 4)
          end
        end
        @idat_chunk_size = idat_sizes.first if idat_sizes.size > 1
      end
      if @compressed_data.size == 0
        raise FormatError.new path.to_s
      end
      @head_data.rewind
      @tail_data.rewind
      @compressed_data.rewind
      decompressed_size = 0
      expected_size = (1 + @width * @sample_size) * @height
      expected_size = limit_of_decompressed_data_size unless limit_of_decompressed_data_size.nil?
      z = Zlib::Inflate.new
      z.inflate(@compressed_data.read) do |chunk|
        decompressed_size += chunk.size
        # raise error when the data size goes over 2 times the usually expected size
        if decompressed_size > expected_size * 2
          z.close
          self.close
          raise DataSizeError.new path.to_s, decompressed_size, expected_size
        end
        @filtered_data << chunk
      end
      z.close
      @compressed_data.rewind
      @filtered_data.rewind
      @is_compressed_data_modified = false
    end

    #
    # Explicit file close.
    #
    # It will close tempfiles that used internally.
    #
    def close
      @compressed_data.close
      @filtered_data.close
      self
    end

    #
    # Returns an array of each scanline's filter type value.
    #
    def filter_types
      types = []
      wrap_with_rewind(@filtered_data) do
        scanline_positions.each do |pos|
          @filtered_data.pos = pos
          byte = @filtered_data.read 1
          types << byte.unpack('C').first
        end
      end
      types
    end

    #
    # Manipulates the filtered (decompressed) data as String.
    #
    # To set a glitched result, return the modified value in the block.
    #
    # Example:
    #
    #   p = PNGlitch.open 'path/to/your/image.png'
    #   p.glitch do |data|
    #     data.gsub /\d/, 'x'
    #   end
    #   p.save 'path/to/broken/image.png'
    #   p.close
    #
    # This operation has the potential to damage filter type bytes. The damage will be a cause of
    # glitching but some viewer applications might deny to process those results.
    # To be polite to the filter types, use +each_scanline+ instead.
    #
    # Since this method sets the decompressed data into String, it may use a massive amount of 
    # memory. To decrease the memory usage, treat the data as IO through +glitch_as_io+ instead.
    #
    def glitch &block   # :yield: data
      warn_if_compressed_data_modified

      wrap_with_rewind(@filtered_data) do
        result = yield @filtered_data.read
        @filtered_data.rewind
        @filtered_data << result
        truncate_io @filtered_data
      end
      compress
      self
    end

    #
    # Manipulates the filtered (decompressed) data as IO.
    #
    def glitch_as_io &block # :yield: data
      warn_if_compressed_data_modified

      wrap_with_rewind(@filtered_data) do
        yield @filtered_data
      end
      compress
      self
    end

    #
    # Manipulates the after-compressed data as String.
    #
    # To set a glitched result, return the modified value in the block.
    #
    # Once the compressed data is glitched, PNGlitch will warn about modifications to
    # filtered (decompressed) data because this method does not decompress the glitched 
    # compressed data again. It means that calling +glitch+ after +glitch_after_compress+ 
    # will make the result overwritten and forgotten.
    #
    # This operation will often destroy PNG image completely.
    #
    def glitch_after_compress &block   # :yield: data
      wrap_with_rewind(@compressed_data) do
        result = yield @compressed_data.read
        @compressed_data.rewind
        @compressed_data << result
        truncate_io @compressed_data
      end
      @is_compressed_data_modified = true
      self
    end

    #
    # Manipulates the after-compressed data as IO.
    #
    def glitch_after_compress_as_io &block # :yield: data
      wrap_with_rewind(@compressed_data) do
        yield @compressed_data
      end
      @is_compressed_data_modified = true
      self
    end

    #
    # (Re-)computes the filtering methods on each scanline.
    #
    def apply_filters prev_filters = nil, filter_codecs = nil
      prev_filters = filter_types if prev_filters.nil?
      filter_codecs = [] if filter_codecs.nil?
      current_filters = []
      prev = nil
      line_sizes = []
      scanline_positions.push(@filtered_data.size).inject do |m, n|
        line_sizes << n - m - 1
        n
      end
      wrap_with_rewind(@filtered_data) do
        # decode all scanlines
        prev_filters.each_with_index do |type, i|
          byte = @filtered_data.read 1
          current_filters << byte.unpack('C').first
          line_size = line_sizes[i]
          line = @filtered_data.read line_size
          filter = Filter.new type, @sample_size
          if filter_codecs[i] && filter_codecs[i][:decoder]
            filter.decoder = filter_codecs[i][:decoder]
          end
          if !prev.nil? && @interlace_pass_count.include?(i + 1)  # make sure prev to be nil if interlace pass is changed
            prev = nil
          end
          decoded = filter.decode line, prev
          @filtered_data.pos -= line_size
          @filtered_data << decoded
          prev = decoded
        end
        # encode all
        filter_codecs.reverse!
        line_sizes.reverse!
        data_amount = @filtered_data.pos # should be eof
        ref = data_amount
        current_filters.reverse_each.with_index do |type, i|
          line_size = line_sizes[i]
          ref -= line_size + 1
          @filtered_data.pos = ref + 1
          line = @filtered_data.read line_size
          prev = nil
          if !line_sizes[i + 1].nil?
            @filtered_data.pos = ref - line_size
            prev = @filtered_data.read line_size
          end
          # make sure prev to be nil if interlace pass is changed
          if @interlace_pass_count.include?(current_filters.size - i)
            prev = nil
          end
          filter = Filter.new type, @sample_size
          if filter_codecs[i] && filter_codecs[i][:encoder]
            filter.encoder = filter_codecs[i][:encoder]
          end
          encoded = filter.encode line, prev
          @filtered_data.pos = ref + 1
          @filtered_data << encoded
        end
      end
    end

    #
    # Re-compress the filtered data.
    #
    # All arguments are for Zlib. See the document of Zlib::Deflate.new for more detail.
    #
    def compress(
      level = Zlib::DEFAULT_COMPRESSION,
      window_bits = Zlib::MAX_WBITS,
      mem_level = Zlib::DEF_MEM_LEVEL,
      strategy = Zlib::DEFAULT_STRATEGY
    )
      wrap_with_rewind(@compressed_data, @filtered_data) do
        z = Zlib::Deflate.new level, window_bits, mem_level, strategy
        until @filtered_data.eof? do
          buffer_size = 2 ** 16
          flush = Zlib::NO_FLUSH
          flush = Zlib::FINISH if @filtered_data.size - @filtered_data.pos < buffer_size
          @compressed_data << z.deflate(@filtered_data.read(buffer_size), flush)
        end
        z.finish
        z.close
        truncate_io @compressed_data
      end
      @is_compressed_data_modified = false
      self
    end

    #
    # Process each scanlines.
    #
    # It takes a block with a parameter. The parameter must be an instance of
    # PNGlitch::Scanline and it provides ways to edit the filter type and the data
    # of the scanlines. Normally it iterates the number of the PNG image height.
    #
    # Here is some examples:
    #
    #   pnglitch.each_scanline do |line|
    #     line.gsub!(/\w/, '0') # replace all alphabetical chars in data
    #   end
    #
    #   pnglicth.each_scanline do |line|
    #     line.change_filter 3  # change all filter to 3, data will get re-filtering (it won't be a glitch)
    #   end
    #
    #   pnglicth.each_scanline do |line|
    #     line.graft 3          # change all filter to 3 and data remains (it will be a glitch)
    #   end
    #
    # See PNGlitch::Scanline for more details.
    #
    # This method is safer than +glitch+ but will be a little bit slow.
    #
    # -----
    #
    # Please note that +each_scanline+ will apply the filters *after* the loop. It means
    # a following example doesn't work as expected.
    #
    #   pnglicth.each_scanline do |line|
    #     line.change_filter 3
    #     line.gsub! /\d/, 'x'  # wants to glitch after changing filters.
    #   end
    #
    # To glitch after applying the new filter types, it should be called separately like:
    #
    #   pnglicth.each_scanline do |line|
    #     line.change_filter 3
    #   end
    #   pnglicth.each_scanline do |line|
    #     line.gsub! /\d/, 'x'
    #   end
    #
    def each_scanline # :yield: scanline
      return enum_for :each_scanline unless block_given?
      prev_filters = self.filter_types
      is_refilter_needed = false
      filter_codecs = []
      wrap_with_rewind(@filtered_data) do
        at = 0
        scanline_positions.push(@filtered_data.size).inject do |pos, delimit|
          scanline = Scanline.new @filtered_data, pos, (delimit - pos - 1), at
          yield scanline
          if fabricate_scanline(scanline, prev_filters, filter_codecs)
            is_refilter_needed = true
          end
          at += 1
          delimit
        end
      end
      apply_filters(prev_filters, filter_codecs) if is_refilter_needed
      compress
      self
    end

    #
    # Access particular scanline(s) at passed +index_or_range+.
    #
    # It returns a single Scanline or an array of Scanline.
    #
    def scanline_at index_or_range
      base = self
      prev_filters = self.filter_types
      filter_codecs = Array.new(prev_filters.size)
      scanlines = []
      index_or_range = self.filter_types.size - 1 if index_or_range == -1
      range = index_or_range.is_a?(Range) ? index_or_range : [index_or_range]

      at = 0
      scanline_positions.push(@filtered_data.size).inject do |pos, delimit|
        if range.include? at
          s = Scanline.new(@filtered_data, pos, (delimit - pos - 1), at) do |scanline|
            if base.fabricate_scanline(scanline, prev_filters, filter_codecs)
              base.apply_filters(prev_filters, filter_codecs)
            end
            base.compress
          end
          scanlines << s
        end
        at += 1
        delimit
      end
      scanlines.size <= 1 ? scanlines.first : scanlines
    end

    def fabricate_scanline scanline, prev_filters, filter_codecs # :nodoc:
      at = scanline.index
      is_refilter_needed = false
      unless scanline.prev_filter_type.nil?
        is_refilter_needed = true
      else
        prev_filters[at] = scanline.filter_type
      end
      codec = filter_codecs[at] = scanline.filter_codec
      if !codec[:encoder].nil? || !codec[:decoder].nil?
        is_refilter_needed = true
      end
      is_refilter_needed
    end

    #
    # Changes filter type values to passed +filter_type+ in all scanlines
    #
    def change_all_filters filter_type
      each_scanline do |line|
        line.change_filter filter_type
      end
      compress
      self
    end

    #
    # Checks if it is interlaced.
    #
    def interlaced?
      @interlace == 1
    end

    #
    # Rewrites the width value.
    #
    def width= w
      @head_data.pos = 8
      while bytes = @head_data.read(8)
        length, type = bytes.unpack 'Na*'
        if type == 'IHDR'
          @head_data << [w].pack('N')
          @head_data.pos -= 4
          data = @head_data.read length
          @head_data << [Zlib.crc32(data, Zlib.crc32(type))].pack('N')
          break
        end
      end
      @head_data.rewind
      w
    end

    #
    # Rewrites the height value.
    #
    def height= h
      @head_data.pos = 8
      while bytes = @head_data.read(8)
        length, type = bytes.unpack 'Na*'
        if type == 'IHDR'
          @head_data.pos += 4
          @head_data << [h].pack('N')
          @head_data.pos -= 8
          data = @head_data.read length
          @head_data << [Zlib.crc32(data, Zlib.crc32(type))].pack('N')
          @head_data.rewind
          break
        end
      end
      @head_data.rewind
      h
    end

    #
    # Save to the +file+.
    #
    def save file
      wrap_with_rewind(@head_data, @tail_data, @compressed_data) do
        open(file, 'w') do |io|
          io << @head_data.read
          chunk_size = @idat_chunk_size || @compressed_data.size
          type = 'IDAT'
          until @compressed_data.eof? do
            data = @compressed_data.read(chunk_size)
            io << [data.size].pack('N')
            io << type
            io << data
            io << [Zlib.crc32(data, Zlib.crc32(type))].pack('N')
          end
          io << @tail_data.read
        end
      end
      self
    end

    alias output save

    private

    # Truncates IO's data from current position.
    def truncate_io io
      eof = io.pos
      io.truncate eof
    end

    # Rewinds given IOs before and after the block.
    def wrap_with_rewind *io, &block
      io.each do |i|
        i.rewind
      end
      yield
      io.each do |i|
        i.rewind
      end
    end

    # Calculate positions of scanlines
    def scanline_positions
      scanline_pos = [0]
      amount = @filtered_data.size
      @interlace_pass_count = []
      if self.interlaced?
        # Adam7
        # Pass 1
        v = 1 + (@width / 8.0).ceil * @sample_size
        (@height / 8.0).ceil.times do
          scanline_pos << scanline_pos.last + v
        end
        @interlace_pass_count << scanline_pos.size
        # Pass 2
        v = 1 + ((@width - 4) / 8.0).ceil * @sample_size
        (@height / 8.0).ceil.times do
          scanline_pos << scanline_pos.last + v
        end
        @interlace_pass_count << scanline_pos.size
        # Pass 3
        v = 1 + (@width / 4.0).ceil * @sample_size
        ((@height - 4) / 8.0).ceil.times do
          scanline_pos << scanline_pos.last + v
        end
        @interlace_pass_count << scanline_pos.size
        # Pass 4
        v = 1 + ((@width - 2) / 4.0).ceil * @sample_size
        (@height / 4.0).ceil.times do
          scanline_pos << scanline_pos.last + v
        end
        @interlace_pass_count << scanline_pos.size
        # Pass 5
        v = 1 + (@width / 2.0).ceil * @sample_size
        ((@height - 2) / 4.0).ceil.times do
          scanline_pos << scanline_pos.last + v
        end
        @interlace_pass_count << scanline_pos.size
        # Pass 6
        v = 1 + ((@width - 1) / 2.0).ceil * @sample_size
        (@height / 2.0).ceil.times do
          scanline_pos << scanline_pos.last + v
        end
        @interlace_pass_count << scanline_pos.size
        # Pass 7
        v = 1 + @width * @sample_size
        ((@height - 1) / 2.0).ceil.times do
          scanline_pos << scanline_pos.last + v
        end
        scanline_pos.pop  # no need to keep last position
      end
      loop do
        v = scanline_pos.last + (1 + @width * @sample_size)
        break if v >= amount
        scanline_pos << v
      end
      scanline_pos
    end

    # Makes warning
    def warn_if_compressed_data_modified # :nodoc:
      if @is_compressed_data_modified
        trace = caller_locations 1, 2
        message = <<-EOL.gsub(/^\s*/, '')
          WARNING: `#{trace.first.label}' is called after a modification to the compressed data.
          With this operation, your changes on the compressed data will be reverted.
          Note that a modification to the compressed data does not reflect to the 
          filtered (decompressed) data.
          It's happened around #{trace.last.to_s}
        EOL
        message = ["\e[33m",  message, "\e[0m"].join if STDOUT.tty?  # color yellow
        warn ["\n", message, "\n"].join
      end
    end
  end
end
