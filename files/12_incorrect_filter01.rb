require 'pnglitch'
PNGlitch.open('png.png') do |p|
  p.each_scanline do |l|
    l.register_filter_encoder do |data, prev|
      data.size.times.reverse_each do |i|
        x = data.getbyte(i)
        v = prev ? prev.getbyte(i - 1) : 0
        data.setbyte(i, (x - v) & 0xff)
      end
      data
    end
  end
  p.output 'png-incorrect-filter01.png'
end
