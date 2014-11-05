module PNGlitch

  class SizeError < StandardError
    def initialize name, size
      @datlimit = digit_format DEFAULT_LIMIT_OF_DECOMPRESSED_FILE_SIZE
      @memlimit = digit_format DEFAULT_LIMIT_OF_MEMORY_USAGE
      @size = digit_format size
      @name = name
      message = self.get_message
      message = ["\e[31m", message, "\e[0m"].join if STDOUT.tty?  # color red
      message = ['size of %s goes over the limit' % name, "\n\n", message, "\n"].join
      super message
    end

    def get_message
      raise NotImplementedError.new 'use the inherited class instead'
    end

    def digit_format digit  # :nodoc:
      mb = 1024 ** 2
      gb = 1024 ** 3
      case digit
      when 0..(mb - 1)
        digit.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,") + 'bytes'
      when mb..(gb - 1)
        num = digit.to_f / mb
        temp = num % 1 == 0.0 ? '%d MB' : '%.1f MB'
        temp % num
      else
        num = digit.to_f / gb
        temp = num % 1 == 0.0 ? '%d GB' : '%.1f GB'
        temp % num
      end
    end
    private :digit_format
  end

  class FileSizeError < SizeError
    def get_message
      message = <<-EOL.gsub(/^\s*/, '')
        Your data reached the file size limit, it goes over #{@size}.
        PNGlitch will set this limit to avoid the attack known as "zip bomb".
        By default, the limit for decompressed data (kept in Tempfile) is set 
        as #{@datlimit}. If you are sure that the PNG image is safe, please set
        manually your own limit values as the variable of PNGlitch#open.
      EOL
      message
    end
  end

  class MemorySizeError < SizeError
    def get_message
      message = <<-EOL.gsub(/^\s*/, '')
        Your data reached the memory size limit, it goes over #{@size}.
        Some of methods in PNGlitch will seek to treat a bunch of data into one
        String instance. To avoid this error, please use methods like 
        `each_scanline', or use IO instead of String through methods like
        `glitch_as_io'.
        By default, the limit for memory usage is set as #{@memlimit}. You can also
        set manually your own limit values as the variable of PNGlitch#open.
      EOL
      message
    end
  end

end
