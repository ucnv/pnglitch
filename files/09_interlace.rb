require 'pnglitch'
PNGlitch.open('png-interlace.png') do |png|
  png.glitch do |data|
    128.times do
      data[rand(data.size)] = 'x'
    end
    data
  end
  png.save 'png-glitch-interlace.png'
end
