require 'pathname'
require 'stringio'
require 'tempfile'
require 'zlib'
require 'pnglitch/errors'
require 'pnglitch/filter'
require 'pnglitch/scanline'
require 'pnglitch/base'

# PNGlitch is a Ruby library to manipulate PNG images, solely for the purpose to "glitch" them.
#
# Since PNG has CRC checksum in the spec, the viewer applications always detect it
# and reject to display broken PNGs. It is why a simple glitching with a text or binary editor
# gets easily failed, differently from images like JPEG.
# This library provides the fix to take the total failure of glitching out, and to keep 
# your PNG undead.
#
# Also it provides options to generate varied glitch results.
#
# = Synopsis
#
#    p = PNGlitch.open '/path/to/your/image.png'
#    p.glitch do |data|
#      data.gsub /\d/, 'x'
#    end
#    p.save '/path/to/broken/image.png'
#    p.close
#
# The code above can be written with a block like below:
#
#    PNGlitch.open('/path/to/your/image.png') do |p|
#      p.glitch do |data|
#        data.gsub /\d/, 'x'
#      end
#      p.save '/path/to/broken/image.png'
#    end
#
# == States
#
# Put very simply, the encoding process of PNG is like:
#
#    +----------+    +---------------+    +-----------------+    +----------------+
#    | Raw data | -> | Filtered data | -> | Compressed data | -> | Formatted file |
#    +----------+    +---------------+    +-----------------+    +----------------+
#
# It shows that there are two states between raw data and a result file, and it means there are 
# two states possible to glitch. This library provides to choose of the state to glitch.
#
# == Scanlines and filters
#
# The five filter types are defined in the spec for optimizing PNG compression. It must be
# the most important factor behind the representation of glitch results. Each filter has 
# different effect.
# In this library we can select the filter type so that generating all possible effects
# in PNG glitch.
#
#
module PNGlitch
  VERSION = '0.0.0'

  DEFAULT_LIMIT_OF_DECOMPRESSED_FILE_SIZE = 16 * 1024 ** 3
  DEFAULT_LIMIT_OF_MEMORY_USAGE           =  4 * 1024 ** 3

  class << self

    #
    # Opens a passed PNG file and returns Base instance.
    #
    #   png = PNGltch.open infile
    #   png.glitch do |data|
    #     data.gsub /\d/, 'x'
    #   end
    #   png.close
    #
    # +open+ will generate Tempfile internally and you should make sure to call +close+
    # method on the end of operations for removing tempfiles.
    #
    # Same as File.open, it can take a block and will automatically close.
    # An example bellow is same as above one.
    #
    #   PNGlitch.open(infile) do |png|
    #     png.glitch do |data|
    #       data.gsub /\d/, 'x'
    #     end
    #   end
    #
    # Optionally it can take arguments to limit the usage of memory and disk.
    # By default, the limit of memory usage is 4GB, and of decompressed file size is 16GB.
    # If a process goes over the limit, an error will be thrown. Those options can be
    # set with hash keys :limit_of_decompressed_file_size and :limit_of_memory_usage like:
    #
    #   png = PNGlitch.open(
    #     infile,
    #     limit_of_decompressed_file_size: 20 * 1024 ** 3,
    #     limit_of_memory_usage: 6 * 1024 ** 3
    #   )
    #
    def open file, options = {}
      options[:limit_of_decompressed_file_size] ||= DEFAULT_LIMIT_OF_DECOMPRESSED_FILE_SIZE
      options[:limit_of_memory_usage] ||= DEFAULT_LIMIT_OF_MEMORY_USAGE
      base = Base.new(
        file,
        options[:limit_of_decompressed_file_size],
        options[:limit_of_memory_usage]
      )
      if block_given?
        begin
          block = Proc.new
          if block.arity == 0
            base.instance_eval &block
          else
            block.call base
          end
        ensure
          base.close
        end
      else
        base
      end
    end
  end

end
