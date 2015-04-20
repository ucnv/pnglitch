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
# = Usage
#
# == Simple glitch
# 
#    png = PNGlitch.open '/path/to/your/image.png'
#    png.glitch do |data|
#      data.gsub /\d/, 'x'
#    end
#    png.save '/path/to/broken/image.png'
#    png.close
#
# The code above can be written with a block like below:
#
#    PNGlitch.open('/path/to/your/image.png') do |png|
#      png.glitch do |data|
#        data.gsub /\d/, 'x'
#      end
#      png.save '/path/to/broken/image.png'
#    end
#
# The +glitch+ method treats the decompressed data into one String instance. It will be
# very convenient, but please note that it could take a huge size of memory. For example,
# a normal PNG image in 4000 x 3000 pixels makes over 48 MB of decompressed data.
# In case that the memory usage becomes a concern, it can be written to use IO instead of
# String.
#
#    PNGlitch.open('/path/to/your/image.png') do |png|
#      buf = 2 ** 18
#      png.glitch_as_io do |io|
#        until io.eof? do
#          d = io.read(buf)
#          io.pos -= d.size
#          io.print(d.gsub(/\d/, 'x'))
#        end
#      end
#      png.save '/path/to/broken/image.png'
#    end
#
# PNGlitch also provides to manipulate with each scanline.
#
#    PNGlitch.open('/path/to/your/image.png') do |png|
#      png.each_scanline do |scanline|
#        scanline.gsub! /\d/, 'x'
#      end
#      png.save '/path/to/broken/image.png'
#    end
#
# Depending a viewer application, the result of the first example using +glitch+ can be
# detected as unopenable, because of breaking the filter type bytes (Most applications
# will ignore it, but I found the library in java.awt get failed). The operation with
# +each_scanline+ will be more careful for memory usage and the file itself.
# It is a polite way, but is slower than the rude +glitch+.
#
#
# == Scanlines and filter types
#
# Scanline consists of data of pixels and a filter type value.
#
# To change the data of pixels, use +Scanline#replace_data+.
#
#    png.each_scanline do |scanline|
#      data = scanline.data
#      scanline.replace_data(data.gsub(/\d/, 'x'))
#    end
#
# Or +Scanline#gsub!+ works like +String#gsub!+
#
#    png.each_scanline do |scanline|
#      scanline.gsub! /\d/, 'x'
#    end
#
# Filter is a tiny function for optimizing PNG compression. It can be set different types
# with each scanline. The five filter types are defined in the spec, are named +None+,
# +Sub+, +Up+, +Average+ and +Paeth+ (+None+ means no filter, this filter type makes "raw"
# data). Internally five digits (0-4) correspond them.
#
# The filter types must be the most important factor behind the representation of glitch
# results. Each filter type has different effect.
#
# Generally in PNG file, scanlines has a variety of filter types on each, as in a
# convertion by image processing applications (like Photoshop or ImageMagick) they try to
# apply a proper filter type with each scanline.
#
# You can check the values like:
#
#    puts png.filter_types
#
# With +each_scanline+, we can reach the filter types particularly.
#
#    png.each_scanline do |scanline|
#      puts scanline.filter_type
#      scanline.change_filter 3
#    end
#
# The example above puts all filter types in 3 (type +Average+). +change_filter+ will
# apply new filter type values correctly. It computes filters and makes the PNG well
# formatted, and any glitch won't get happened. It also means the output image should
# completely look the same as the input one.
#
# However glitches will reveal the difference of the filter types.
#
#    PNGlitch.open(infile) do |png|
#      png.each_scanline do |scanline|
#        scanline.change_filter 3
#      end
#      png.glitch do |data|
#        data.gsub /\d/, 'x'
#      end
#      png.save outfile1
#    end
#    
#    PNGlitch.open(infile) do |png|
#      png.each_scanline do |scanline|
#        scanline.change_filter 4
#      end
#      png.glitch do |data|
#        data.gsub /\d/, 'x'
#      end
#      png.save outfile2
#    end
#
# With the results of the example above, obviously we can recognize the filter types make
# a big difference. The filter is distinct and interesting thing in PNG glitching.
# To put all filter type in a same value before glitching, we would see the signature
# taste of each filter type. (Note that +change_filter+ may be a little bit slow, image
# processing libraries like ImageMagick also have an option to put all filter type in
# same ones and they may process faster.)
#
# This library provides a simple method to change the filter type so that generating all
# possible effects in PNG glitch.
#
# PNGlitch also provides to make the filter types wrong. Following example swaps the
# filter types but remains data unchanged. It means to put a wrong filter type applied.
#
#    png.each_scanline do |scanline|
#      scanline.graft rand(4)
#    end
#
# Additionally, it is possible to break the filter function. Registering a (wrong) filter
# function like below, we can make glitches with an algorithmic touch.
#
#    png.each_scanline do |scanline|
#      scanline.register_filter_encoder do |data, prev|
#        data.size.times.reverse_each do |i|
#          x = data.getbyte(i)
#          v = prev ? prev.getbyte((i - 5).abs) : 0
#          data.setbyte(i, (x - v) & 0xff)
#        end
#        data
#      end
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
# It shows that there are two states between raw data and a result file, and it means there
# are two states possible to glitch. This library provides to choose of the state to glitch.
#
# All examples cited thus far are operations to "filtered data". On the other hand, PNGlitch
# can touch the "compressed data" through +glitch_after_compress+ method:
#
#     png.glitch_after_compress do |data|
#       data[rand(data.size)] = 'x'
#       data
#     end
#
# Glitch against the compressed data makes slightly different pictures from other results.
# But sometimes this scratch could break the compression and make the file unopenable.
#
module PNGlitch
  VERSION = '0.0.2'

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
    # Under normal conditions, the size of the decompressed data of PNG image becomes
    # <tt>(1 + image_width * sample_size) * image_height</tt> in bytes (mostly over 4 times
    # the amount of pixels).
    # To avoid the attack known as "zip bomb", PNGlitch will throw an error when
    # decompressed data goes over twice the expected size. If it's sure that the passed
    # file is safe, the upper limit of decompressed data size can be set in +open+'s option
    # in bytes.
    # Like:
    #
    #   PNGlitch.open(infile, limit_of_decompressed_data_size: 1024 ** 3)
    #
    def open file, options = {}
      base = Base.new file, options[:limit_of_decompressed_data_size]
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
