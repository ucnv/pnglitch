require 'pnglitch'
PNGlitch.open('png.png') do |png|
  png.change_all_filters :paeth
  png.glitch do |data|
    128.times do
      data[rand(data.size)] = 'x'
    end
    data
  end
  png.save 'png-glitch-paeth.png'
end
