# frozen_string_literal: true
require 'spec_helper'

describe PNGlitch do
  before :context do
    @tmpdir = Pathname(File.dirname(__FILE__)).join('fixtures').join('out')
    FileUtils.mkdir @tmpdir unless File.exist? @tmpdir
  end

  after :context do
    FileUtils.remove_entry_secure @tmpdir
  end

  after :example do
    FileUtils.rm Dir.glob(@tmpdir.join('*'))
  end

  let(:infile) { Pathname(File.dirname(__FILE__)).join('fixtures').join('in.png') }
  let(:outdir) { Pathname(@tmpdir) }
  let(:outfile) { outdir.join('out.png') }

  describe '.open' do
    subject(:png) { PNGlitch.open infile }
    it { is_expected.to be_a PNGlitch::Base }

    it 'can close' do
      expect { png.close }.not_to raise_error
      expect do
        png.compressed_data.read
      end.to raise_error IOError
    end

    context 'when it takes a block' do
      it 'should be closed after the block' do
        png = nil
        PNGlitch.open(infile) { |p| png = p }
        expect do
          png.compressed_data.read
        end.to raise_error IOError
      end

      it 'also can execute with DSL style' do
        types, h = ()
        out = outfile
        expect do
          PNGlitch.open(infile) do
            types = filter_types
            h = height
            output out
          end
        end.not_to raise_error
        expect(types.size).to eq h
        expect(outfile).to exist
      end

      it 'should return a value of last call in the block' do
        e = 0
        v = PNGlitch.open infile do |p|
          e = p.height
          p.height
        end
        expect(v).to be == e

        e = 0
        v = PNGlitch.open infile do
          e = height
          height
        end
        expect(v).to be == e
      end
    end

    context 'when decompressed data is unexpected size' do
      it 'should not raise error for too small size' do
        bomb = infile.dirname.join('ina.png')
        expect do
          png = PNGlitch.open bomb
          png.close
        end.to_not raise_error
      end

      it 'should raise error for too large size' do
        bomb = infile.dirname.join('inb.png')
        expect do
          png = PNGlitch.open bomb
          png.close
        end.to raise_error PNGlitch::DataSizeError
      end

      it 'can avoid the error' do
        bomb = infile.dirname.join('inb.png')
        expect do
          png = PNGlitch.open bomb, limit_of_decompressed_data_size: 100 * 1024**2
          png.close
        end.not_to raise_error
      end
    end

    context 'when it is not PNG file' do
      it 'should raise error' do
        file = infile.dirname.join('filter_none')
        expect do
          png = PNGlitch.open file
          png.close
        end.to raise_error PNGlitch::FormatError
      end
    end

    context 'with interlaced image' do
      it 'should check it' do
        a = PNGlitch.open infile, &:interlaced?
        interlace = infile.dirname.join('inc.png')
        b = PNGlitch.open interlace, &:interlaced?
        expect(a).to be false
        expect(b).to be true
      end
    end
  end

  describe '.output' do
    context 'when nothing change' do
      it 'makes an output to be same as input' do
        PNGlitch.open infile do |png|
          png.output outfile
        end
        a = open outfile
        b = open infile
        expect(a.read.unpack('a*').first).to eq(b.read.unpack('a*').first)
        a.close
        b.close
      end
    end

    context 'when it generates wrong PNG' do
      it 'can even read it again (if it has right compression)' do
        out1 = outfile
        out2 = outdir.join('out2.png')
        PNGlitch.open infile do
          glitch { |d| d.gsub(/\d/, '') }
          output out1
        end
        expect do
          PNGlitch.open outfile do
            compress
            output out2
          end
        end.not_to raise_error
      end

      it 'cannot read broken compression' do
        out1 = outfile
        out2 = outdir.join('out2.png')
        PNGlitch.open infile do
          glitch_after_compress { |d| d.gsub(/\d/, 'a') }
          output out1
        end
        expect do
          PNGlitch.open outfile do
            compress
            output out2
          end
        end.to raise_error Zlib::DataError
      end
    end
  end

  describe '.compress' do
    it 'should be lossless' do
      png = PNGlitch.open infile
      before = png.filtered_data.read
      png.compress
      after = Zlib::Inflate.inflate(png.compressed_data.read)
      png.close
      expect(before).to eq after
    end
  end

  describe '.apply_filters' do
    it 'should ignore wrong filter types' do
      PNGlitch.open infile do |p|
        io = p.filtered_data
        io.rewind
        io << [100].pack('C')
        expect do
          p.apply_filters
        end.not_to raise_error
      end
    end
  end

  describe '.glitch' do
    it 'makes a result that is readable as PNG' do
      png = PNGlitch.open infile
      png.glitch do |data|
        data.gsub(/\d/,'a')
      end
      png.output outfile
      png.close
      expect do
        ChunkyPNG::Image.from_file outfile
      end.not_to raise_error
    end

    it 'makes a result has an intended size of data' do
      png1 = PNGlitch.open infile
      a = png1.filtered_data.size
      png1.glitch do |data|
        data.gsub(/\d/,'a')
      end
      png1.output outfile
      png2 = PNGlitch.open outfile
      b = png2.filtered_data.size
      png2.close
      expect(b).to eq a

      png1 = PNGlitch.open infile
      a = png1.filtered_data.size
      png1.glitch do |data|
        data[(data.size / 2), 100] = ''
        data
      end
      png1.output outfile
      png2 = PNGlitch.open outfile
      b = png2.filtered_data.size
      png2.close
      expect(b).to eq(a - 100)
    end
  end

  describe '.glitch_after_compress' do
    it 'should not fail' do
      png = PNGlitch.open infile
      png.glitch_after_compress do |data|
        data[rand(data.size)] = 'x'
        data
      end
      png.output outfile
      png.close
      expect(outfile).to exist
    end

    context 'when manipulation after glitch_after_compress' do
      it 'warn' do
        png = PNGlitch.open infile
        png.glitch_after_compress do |data|
          data[rand(data.size)] = 'x'
          data
        end
        expect do
          png.glitch do |data|
            data[0] = 'x'
          end
        end.to output.to_stderr
        png.close
      end
    end
  end

  describe '.glitch_as_io' do
    it 'can generate a same result with glitch method' do
      out1 = outdir.join 'a.png'
      out2 = outdir.join 'b.png'
      pos = []
      PNGlitch.open infile do |p|
        p.glitch_as_io do |io|
          10.times do |i|
            pos << [rand(io.size), i.to_s]
          end
          pos.each do |x|
            io.pos = x[0]
            io << x[1]
          end
        end
        p.output out1
      end
      PNGlitch.open infile do |p|
        p.glitch do |data|
          pos.each do |x|
            data[x[0]] = x[1]
          end
          data
        end
        p.output out2
      end

      a = File.read out1
      b = File.read out2
      expect(a.b).to eq b.b
    end
  end

  describe '.glitch_after_compress_as_io' do
    it 'can generate a same result with glitch_after_compress method' do
      out1 = outdir.join 'a.png'
      out2 = outdir.join 'b.png'
      pos = []
      PNGlitch.open infile do |p|
        p.glitch_after_compress_as_io do |io|
          10.times do |i|
            pos << [rand(io.size), i.to_s]
          end
          pos.each do |x|
            io.pos = x[0]
            io << x[1]
          end
        end
        p.output out1
      end
      PNGlitch.open infile do |p|
        p.glitch_after_compress do |data|
          pos.each do |x|
            data[x[0]] = x[1]
          end
          data
        end
        p.output out2
      end

      a = File.read out1
      b = File.read out2
      expect(a.b).to eq b.b
    end
  end

  describe '.filter_types' do
    it 'should be in range between 0 and 4' do
      png = PNGlitch.open infile
      types = png.filter_types
      png.close
      types.each do |t|
        expect(t).to be_between(0, 4)
      end
    end

    it 'should be same size of image height' do
      png = PNGlitch.open infile
      types = png.filter_types
      height = png.height
      png.close
      expect(types.size).to eq height
    end

    context 'with interlaced PNG' do
      it 'should be in range between 0 and 4' do
        png = PNGlitch.open infile.dirname.join('inc.png')
        types = png.filter_types
        png.close
        types.each do |t|
          expect(t).to be_between(0, 4)
        end
      end
    end
  end

  describe '.each_scanline' do
    it 'returns Enumerator' do
      png = PNGlitch.open infile
      expect(png.each_scanline).to be_a Enumerator
    end

    it 'can exchange filter types' do
      png = PNGlitch.open infile
      png.each_scanline do |line|
        expect(line).to be_a PNGlitch::Scanline
        line.graft rand(4)
      end
      png.output outfile
      png.close
      expect do
        ChunkyPNG::Image.from_file outfile
      end.not_to raise_error
    end

    it 'can rewite scanline data' do
      png = PNGlitch.open infile
      png.each_scanline do |line|
        line.data = line.data.gsub(/\d/,'a')
      end
      png.output outfile
      png.close
      expect do
        ChunkyPNG::Image.from_file outfile
      end.not_to raise_error
    end

    it 'can change filter types and re-filter' do
      png = PNGlitch.open infile
      png.each_scanline do |line|
        line.change_filter rand(4)
      end
      png.output outfile
      png.close
      expect do
        ChunkyPNG::Image.from_file outfile
      end.not_to raise_error

    end

    it 'can change filter type with the name' do
      t1 = PNGlitch.open infile do |p|
        p.each_scanline do |l|
          l.change_filter PNGlitch::Filter::PAETH
        end
        p.filter_types
      end
      t2 = PNGlitch.open infile do |p|
        p.each_scanline do |l|
          l.change_filter :paeth
        end
        p.filter_types
      end
      t3 = PNGlitch.open infile do |p|
        p.each_scanline do |l|
          l.change_filter :sub
        end
        p.filter_types
      end
      t4 = PNGlitch.open infile do |p|
        p.each_scanline do |l|
          l.graft 'Paeth'
        end
        p.filter_types
      end
      expect(t2).to be == t1
      expect(t3).not_to be == t1
      expect(t4).to be == t1
    end

    it 'can apply custom filter method' do
      lines = []
      sample_size = nil
      original_filter = 0
      PNGlitch.open infile do |png|
        target = png.scanline_at 100
        original_filter = target.filter_type
        lines[1] = target.data
        sample_size = png.sample_size
        png.each_scanline do |l|
          l.change_filter 0
        end
        lines[0] = png.scanline_at(99).data
      end

      enc = lambda do |data, prev|
        data.size.times.reverse_each do |i|
          x = data.getbyte i
          a = i >= sample_size ? data.getbyte(i - sample_size - 1) : 0
          b = !prev.nil? ? prev.getbyte(i - 1) : 0
          data.setbyte i, (x - ((a + b) / 2)) & 0xff
        end
        data
      end
      decoded = PNGlitch::Filter.new(original_filter, sample_size).decode(lines[1], lines[0])
      encoded = enc.call(decoded.dup, lines[0])

      PNGlitch.open infile do |png|
        png.each_scanline.with_index do |s, i|
          s.register_filter_encoder enc if i == 100
        end
        png.output outfile
      end
      PNGlitch.open outfile do |png|
        expect(png.scanline_at(100).data).to eq encoded
      end

      # ==================================

      dec = lambda do |data, prev|
        data.size.times do |i|
          x = data.getbyte i
          a = i >= sample_size ? data.getbyte(i - sample_size - 2) : 0
          b = !prev.nil? ? prev.getbyte(i - 1) : 0
          data.setbyte i, (x + ((a + b) / 2)) & 0xff
        end
        data
      end
      decoded = dec.call(lines[1].dup, lines[0])
      encoded = PNGlitch::Filter.new(original_filter, sample_size).encode(decoded, lines[0])

      PNGlitch.open infile do |png|
        png.each_scanline.with_index do |s, i|
          s.register_filter_decoder dec if i == 100
        end
        png.output outfile
      end
      PNGlitch.open outfile do |png|
        expect(png.scanline_at(100).data).to eq encoded
      end

      # ==================================

      decoded = dec.call(lines[1].dup, lines[0])
      encoded = enc.call(decoded.dup, lines[0])

      PNGlitch.open infile do |png|
        png.each_scanline.with_index do |s, i|
          if i == 100
            s.register_filter_encoder enc
            s.register_filter_decoder dec
          end
        end
        png.output outfile
      end
      PNGlitch.open outfile do |png|
        expect(png.scanline_at(100).data).to eq encoded
      end
    end

    context 'with wrong sized data' do
      it 'should raise no errors' do
        expect do
          PNGlitch.open infile do |png|
            pos = png.filtered_data.pos = png.filtered_data.size * 4 / 5
            png.filtered_data.truncate pos
            png.each_scanline do |line|
              line.gsub! /\d/, 'x'
              line.filter_type = rand(4)
            end
            png.output outfile
          end
        end.not_to raise_error
        expect do
          PNGlitch.open infile do |png|
            png.filtered_data.pos = png.filtered_data.size * 4 / 5
            chunk = png.filtered_data.read
            png.filtered_data.rewind
            10.times do
              png.filtered_data << chunk
            end
            png.each_scanline do |line|
              line.gsub! /\d/, 'x'
              line.filter_type = rand(4)
            end
            png.output outfile
          end
        end.not_to raise_error
      end
    end

    context 'when re-filtering with same filters' do
      it 'becomes a same result' do
        png = PNGlitch.open infile
        png.filtered_data.rewind
        a = png.filtered_data.read
        filters = png.filter_types
        png.each_scanline.with_index do |l, _i|
          l.change_filter PNGlitch::Filter::UP
        end
        b = png.filtered_data.read
        png.each_scanline.with_index do |l, i|
          l.change_filter filters[i]
        end
        png.filtered_data.rewind
        c = png.filtered_data.read
        png.output outfile
        png.close
        expect(c).to eq(a)
        expect(b).not_to eq(a)
      end
    end

    context 'with an interlaced image' do
      it 'can recognize correct filter types' do
        img = infile.dirname.join('inc.png')
        PNGlitch.open img do |p|
          p.each_scanline do |line|
            expect(line.filter_type).to be_between(0, 4)
          end
          p.change_all_filters 4
          p.each_scanline do |line|
            expect(line.filter_type).to be == 4
          end
          p.save outfile.dirname.join('i.png')
        end
      end
    end
  end

  describe '.scanline_at' do
    it 'should reflect the changes to the instance' do
      PNGlitch.open infile do |png|
        line = png.scanline_at 100
        f = line.filter_type
        line.filter_type = (f + 1) % 5
        png.output outfile
      end

      png1 = PNGlitch.open infile
      line1_100 = png1.scanline_at(100).data
      line1_95 = png1.scanline_at(95).data
      png2 = PNGlitch.open outfile
      line2_100 = png2.scanline_at(100).data
      line2_95 = png2.scanline_at(95).data
      png1.close
      png2.close
      expect(line2_100).not_to eq(line1_100)
      expect(line2_95).to eq(line1_95)
    end

    it 'can apply custom filter method' do
      lines = []
      sample_size = nil
      original_filter = 0
      PNGlitch.open infile do |png|
        target = png.scanline_at 100
        original_filter = target.filter_type
        lines[1] = target.data
        sample_size = png.sample_size
        png.each_scanline do |l|
          l.change_filter 0
        end
        lines[0] = png.scanline_at(99).data
      end

      enc = lambda do |data, prev|
        data.size.times.reverse_each do |i|
          x = data.getbyte i
          a = i >= sample_size ? data.getbyte(i - sample_size - 1) : 0
          b = !prev.nil? ? prev.getbyte(i - 2) : 0
          data.setbyte i, (x - ((a + b) / 2)) & 0xff
        end
        data
      end
      decoded = PNGlitch::Filter.new(original_filter, sample_size).decode(lines[1], lines[0])
      encoded = enc.call(decoded.dup, lines[0])

      PNGlitch.open infile do |png|
        l = png.scanline_at 100
        l.register_filter_encoder enc
        png.output outfile
      end
      PNGlitch.open outfile do |png|
        expect(png.scanline_at(100).data).to eq encoded
      end
    end

  end

  describe '.change_all_filters' do
    it 'can change filter types with single method' do
      v = rand(4)
      PNGlitch.open infile do |p|
        p.change_all_filters v
        p.save outfile
      end
      PNGlitch.open outfile do |p|
        p.each_scanline do |l|
          expect(l.filter_type).to be == v
        end
      end
    end
  end

  describe '.width and .height' do
    it 'destroy the dimension of the image' do
      w, h = ()
      out = outfile
      PNGlitch.open infile do |p|
        w = p.width
        h = p.height
        p.width = w - 10
        p.height = h + 10
        p.output out
      end
      p = PNGlitch.open out
      expect(p.width).to equal w - 10
      expect(p.height).to equal h + 10
      p.close
    end
  end

  describe '.idat_chunk_size' do
    it 'should be controllable' do
      amount = nil
      out1 = outdir.join 'a.png'
      out2 = outdir.join 'b.png'
      PNGlitch.open infile do |p|
        amount = p.compressed_data.size
        p.idat_chunk_size = 1024
        p.output out1
      end
      PNGlitch.open out1 do |p|
        expect(p.idat_chunk_size).to be == 1024
      end
      idat_size = open(out1, 'rb') do |f|
        f.read.scan(/IDAT/).size
      end
      expect(idat_size).to be == (amount.to_f / 1024).ceil

      PNGlitch.open infile do |p|
        p.idat_chunk_size = nil
        p.output out2
      end
      PNGlitch.open out2 do |p|
        expect(p.idat_chunk_size).to be nil
      end
      idat_size = open(out2, 'rb') do |f|
        f.read.scan(/IDAT/).size
      end
      expect(idat_size).to be == 1
    end
  end
end
