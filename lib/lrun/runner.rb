################################################################################
# Copyright (C) 2012-2013 WU Jun <quark@zju.edu.cn>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
################################################################################

require 'lrun'

# {Lrun} provides essential methods to run program with different options
# using <tt>lrun</tt> binary.
#
# {Lrun::Runner} makes it easier to run many programs with same options.
#
# = Example
#
#   runner = Lrun::Runner.new(:max_cpu_time=>1, :tmpfs=>[["/tmp", 2**20]], :chdir=>"/tmp")
#   # or:
#   runner = Lrun::Runner.new.where(:max_cpu_time=>1, :tmpfs=>[["/tmp", 2**20]], :chdir=>"/tmp")
#   # or:
#   runner = Lrun::Runner.new.max_cpu_time(1).tmpfs('/tmp' => 2**20).chdir('/tmp')
#
#   runner.options
#   # => {:max_cpu_time=>1, :tmpfs=>[["/tmp", 1048576]], :chdir=>"/tmp"} 
#   runner.max_cpu_time(nil).options
#   # => {:tmpfs=>[["/tmp", 1048576]], :chdir=>"/tmp"} 
#   runner.cmd("touch `seq 1 4`").run('ls').stdout
#   # => "1\n2\n3\n4\n"
#   runner.cmd("echo 'puts ENV[?A]' > a.rb").env('A' => 'Hello').run('ruby a.rb').stdout
#   # => "Hello\n"
class Lrun::Runner

  # @!attribute [rw] options
  #   @return [Hash] options used in {#run}
  attr_accessor :options

  # @param [Hash] options options for the runner
  def initialize(options = {})
    @options = options
  end

  # Methods for easily applying custom options
  [:stdin, :stdout, :stderr, *Lrun::LRUN_OPTIONS.keys].each do |name|
    define_method name do |value| where(name => value) end
  end

  # Run commands using current {#options}.
  #
  # @param [Array<String>, String] commands commands to be executed
  #
  # @see options
  # @see Lrun.run
  def run(commands)
    Lrun.run commands, @options
  end

  # Create a new runner with new options
  #
  # @param [Hash] options new options to be merged
  # @return [Lrun::Runner] new runner created with merged options
  def where(options)
    raise TypeError.new('expect options to be a Hash') unless options.is_a? Hash
    Lrun::Runner.new(Lrun.merge_options(@options, options))
  end

end
