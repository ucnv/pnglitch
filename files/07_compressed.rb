require 'pnglitch'
PNGlitch.open('png.png') do |png|
  png.glitch_after_compress do |data|
    5.times do
      data[rand(data.size)] = 'x'
    end
    data
  end
  png.save 'png-glitch-compressed.png'
end
