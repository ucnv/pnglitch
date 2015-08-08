require 'pnglitch'
PNGlitch.open('png.png') do |png|
  png.change_all_filters :average
  png.glitch do |data|
    256.times do
      data[rand(data.size)] = 'x'
    end
    data
  end
  png.save 'png-glitch-average.png'
end
