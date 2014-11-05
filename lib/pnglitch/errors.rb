module PNGlitch

  class DataSizeError < StandardError
    def initialize over, expected
      over_size = digit_format over
      expected_size = digit_format expected
      message = <<-EOL.gsub(/^\s*/, '')
        The size of your data goes over #{over_size}.
        It should be expected to be #{expected_size} actually when it's
        a normal formatted PNG file.
        PNGlitch raised this error to avoid the attack known as
        "zip bomb". If you are sure that the PNG image is safe, 
        please set manually your own upper size limit as the variable
        of PNGlitch#open.
      EOL
      message = ["\e[31m", message, "\e[0m"].join if STDOUT.tty?  # color red
      message = ['size of decompressed data is too large', "\n\n", message, "\n"].join
      super message
    end

    def digit_format digit  # :nodoc:
      digit.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,") + ' bytes'
    end
    private :digit_format
  end

  class FormatError < StandardError
    def initialize message = nil
      m = 'passed file seems different from PNG file.'
      m = [m, message].join(' ') unless message.nil?
      super m
    end
  end

end
