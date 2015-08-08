require 'pnglitch'
PNGlitch.open('png.png') do |png|
  png.change_all_filters 4
  sample_size = png.sample_size
  png.each_scanline do |l|
    l.register_filter_encoder do |data, prev|
      data.size.times.reverse_each do |i|
        x = data.getbyte i
        is_a_exist = i >= sample_size
        is_b_exist = !prev.nil?
        a = is_a_exist ? data.getbyte(i - sample_size) : 0
        b = is_b_exist ? prev.getbyte(i) : 0
        c = is_a_exist && is_b_exist ? prev.getbyte(i - sample_size) : 0
        p =  a + b - c
        pa = (p - a).abs
        pb = (p - b).abs
        pc = (p - c).abs
        pr = pa <= pb && pa <= pc ? a : pb <= pc ? b : c
        data.setbyte i, (x - pr) & 0xfe
      end
      data
    end
  end
  png.output 'png-incorrect-filter03.png'
end
