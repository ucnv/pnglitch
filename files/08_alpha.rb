require 'pnglitch'
PNGlitch.open('png-alpha.png') do |png|
  png.glitch do |data|
    128.times do
      data[rand(data.size)] = 'x'
    end
    data
  end
  png.save 'png-glitch-alpha.png'
end
