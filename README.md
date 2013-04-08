# lrun-ruby

[![Gem Version](https://badge.fury.io/rb/lrun-ruby.png)](http://badge.fury.io/rb/lrun-ruby)
[![Build Status](https://travis-ci.org/quark-zju/lrun-ruby.png)](https://travis-ci.org/quark-zju/lrun-ruby)
[![Code Climate](https://codeclimate.com/github/quark-zju/lrun-ruby.png)](https://codeclimate.com/github/quark-zju/lrun-ruby)

Ruby binding for [lrun](https://github.com/quark-zju/lrun)

## Dependencies

* [lrun](https://github.com/quark-zju/lrun)
* Ruby 1.9 or above

## Installation

1. Install lrun binary. For detailed steps, please refer to [lrun project page](https://github.com/quark-zju/lrun).
2. Install `lrun-ruby` gem:

```bash
gem install lrun-ruby
```

## Usage

```ruby
require 'lrun'

Lrun.run('false').exitcode # => 1
Lrun.run(['echo', 'hello']).stdout # => "hello\n"

runner = Lrun::Runner.new(:max_cpu_time=>1, :chdir=>"/tmp")
runner.run('pwd').stdout # => "/tmp\n"
runner.chdir('/bin').run('pwd').stdout # => "/bin\n"
```

See [documentation](http://rdoc.info/github/quark-zju/lrun-ruby/frames/index) for details.
