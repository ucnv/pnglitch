require 'pnglitch'

count = 0
infiles = %w(lena.png lena-alpha.png)
infiles.each do |infile|
  alpha = /alpha/ =~ infile
  [false, true].each do |compress|
    [false, true].each do |interlace|
      if interlace
        system("convert -interlace plane %s tmp.png" % infile)
        infile = 'tmp.png'
      end
      [:optimized, :sub, :up, :average, :paeth].each do |filter|
        [:replace, :transpose, :defect].each do |method|
          count += 1
          png = PNGlitch.open infile
          png.change_all_filters filter unless filter == :optimized
          options = [filter.to_s]
          options << 'alpha' if alpha
          options << 'interlace' if interlace
          options << 'compress' if compress
          options << method.to_s
          outfile = "lena-%02d-%s.png" % [count, options.join('-')]
          process = lambda do |data, range|
            case method
            when :replace
              range.times do
                data[rand(data.size)] = 'x'
              end
              data
            when :transpose
              x = data.size / 4
              data[0, x] + data[x * 2, x] + data[x * 1, x] + data[x * 3..-1]
            when :defect
              range.times do
                data[rand(data.size)] = ''
              end
              data
            end
          end
          unless compress
            png.glitch do |data|
              process.call data, 150
            end
          else
            png.glitch_after_compress do |data|
              process.call data, 10
            end
          end
          png.save outfile
          png.close
        end
      end
    end
  end
end
system "rm tmp.png"
