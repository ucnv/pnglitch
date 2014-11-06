require 'spec_helper'

describe PNGlitch::Filter do
  types = [:none, :sub, :up, :average, :paeth]
  dir = Pathname(File.dirname(__FILE__)).join('fixtures')
  tests = {}
  types.each do |t|
    data = File.binread(dir.join('filter_' + t.to_s))
    tests[t] = data.scan %r|[\s\S]{1,#{data.size / 2}}|
  end

  types.each do |type|
    context "with #{type} type" do
      let(:filter) { PNGlitch::Filter.new type, 3 }
      it 'should encode correctly' do
        expect(filter.encode(tests[:none][0])).to eq tests[type][0]
        expect(filter.encode(tests[:none][1], tests[:none][0])).to eq tests[type][1]
      end
      it 'should decode correctly' do
        expect(filter.decode(tests[type][1], tests[:none][0])).to eq tests[:none][1]
        expect(filter.decode(tests[type][0])).to eq tests[:none][0]
      end
    end
  end

end
