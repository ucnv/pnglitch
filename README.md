# PNGlitch

[![Build Status](https://travis-ci.org/ucnv/pnglitch.svg?branch=master)](https://travis-ci.org/ucnv/pnglitch)


PNGlitch is a Ruby library to destroy your PNG images.

With normal data-bending technique, a glitch against PNG will easily fail
because of the checksum function. We provide a fail-proof destruction for it.
Using this library you will see beautiful and various PNG artifacts.

## Usage

```ruby
    PNGlitch.open('/path/to/your/image.png') do |p|
      p.glitch do |data|
        data.gsub /\d/, 'x'
      end
      p.save '/path/to/broken/image.png'
    end
```
## Installation

Add this line to your application's Gemfile:

    gem 'pnglitch'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install pnglitch

## Contributing

1. Fork it ( http://github.com/ucnv/pnglitch/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
