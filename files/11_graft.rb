require 'pnglitch'
PNGlitch.open('png.png') do |png|
  png.each_scanline do |line|
    line.graft rand(5)
  end
  png.save 'png-glitch-graft.png'
end
