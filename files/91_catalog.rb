count = 0
result = []
infiles = %w(boat.png boat-alpha.png)
infiles.each do |infile|
  alpha = /alpha/ =~ infile
  [false, true].each do |compress|
    [false, true].each do |interlace|
      [:optimized, :sub, :up, :average, :paeth].each do |filter|
        [:replace, :transpose, :defect].each do |method|
          count += 1
          options = [filter.to_s]
          options << 'alpha' if alpha
          options << 'interlace' if interlace
          options << 'compress' if compress
          options << method.to_s
          outfile = "boat-%03d-%s.png" % [count, options.join('-')]
          meta = {
            file: outfile,
            method: method,
            filter: filter,
            interlace: interlace,
            alpha: alpha,
            compress: compress
          }
          template = <<-TEMP
      <figure class="catalog">
        <img src="files/blank.png" data-src="files/#{meta[:file]}" alt="">
        <figcaption>Figure B.#{count}) Glitched PNG<br>
          Glitch method: #{meta[:method].to_s.capitalize } /
          Filter: #{meta[:filter].to_s.capitalize }  /
          Interlace: #{meta[:interlace] ? 'Interlaced' : 'None'} /
          Glitched on: #{meta[:compress] ? 'Compressed data' : 'Filtered data'}
        </figcaption>
      </figure>
          TEMP

          result << template.dup

        end
      end
    end
  end
end

puts result.join("\n")
