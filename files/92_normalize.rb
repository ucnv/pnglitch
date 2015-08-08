require 'cocaine'

convert = Cocaine::CommandLine.new 'sips', ':infile --setProperty format png --out :outfile'
rotate = Cocaine::CommandLine.new 'sips', ':infile --out :outfile -r 180'
Dir.glob('original/*.png').each do |file|
  outfile = file.sub 'original/', ''
  convert.run infile: file, outfile: outfile
  unless File.exist?(outfile)
    tmp = 'tmp.png'
    rotate.run infile: file, outfile: tmp
    rotate.run infile: tmp, outfile: outfile
    File.unlink tmp
  end
end
