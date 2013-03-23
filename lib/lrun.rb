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

require 'tempfile'
require 'shellwords'

# Run program using <tt>lrun</tt>. Require external <tt>lrun</tt> binary.
#
# @see Lrun.run
# @see https://github.com/quark-zju/lrun lrun project page
#
# = Example
#
#   Lrun.run('foo', Lrun.merge_options({:max_memory => 2 ** 20, :max_cpu_time => 5}, {:network => false}))
#
module Lrun

  # Name of lrun executable
  LRUN_BINARY = 'lrun'

  # Full path of lrun executable, automatically detected using {LRUN_BINARY} and <tt>PATH</tt> environment variable
  LRUN_PATH   = ENV['PATH'].split(':').map{|p| File.join(p, LRUN_BINARY)}.find{|p| File.executable? p}

  # Available lrun options, and whether they can occur multiple times (1: no, 2: yes)
  LRUN_OPTIONS = {
    :max_cpu_time => 1,
    :max_real_time => 1,
    :max_memory => 1,
    :max_output => 1,
    :max_nprocess => 1,
    :max_rtprio => 1,
    :max_nfile => 1,
    :max_stack => 1,
    :isolate_process => 1,
    :basic_devices => 1,
    :reset_env => 1,
    :network => 1,
    :chroot => 1,
    :chdir => 1,
    :nice => 1,
    :umask => 1,
    :uid => 1,
    :gid => 1,
    :interval => 1,
    :cgname => 1,
    :bindfs => 2,
    :cgroup_option => 2,
    :tmpfs => 2,
    :env => 2,
    :fd => 2,
    :group => 2,
    :cmd => 2,
  }

  # Keep how many bytes of stdout and stderr, can be overrided using <tt>options[:truncate]</tt>
  TRUNCATE_OUTPUT_LENGTH = 4096

  # Error related to lrun
  class LrunError < RuntimeError; end

  # Result of {Lrun.run}.
  class Result < Struct.new(:memory, :cputime, :exceed, :exitcode, :signal, :stdout, :stderr)

    # @!attribute memory
    #   @return [Integer] peak memory used, in bytes
    #
    # @!attribute cputime
    #   @return [Float] CPU time consumed, in seconds
    #
    # @!attribute exceed
    #   @return [Symbol] what limit exceed,
    #           <tt>:time</tt> if time limit exceeded,
    #           <tt>:memory</tt> if memory limit exceeded,
    #           <tt>:output</tt> if output limit exceeded,
    #           or <tt>nil</tt> if no limit exceeded
    #
    # @!attribute exitcode
    #   @return [Integer] exit code
    #
    # @!attribute signal
    #   @return [Integer] signal number received, or <tt>nil</tt> if exited normally
    #
    # @!attribute stdout
    #   @return [String] standard output, or <tt>nil</tt> if it is ignored in options
    #
    # @!attribute stderr
    #   @return [String] standard error output, or <tt>nil</tt> if stderr is ignored in options

    # @return [Boolean] whether the program exited without crash and has a zero exit code
    def clean?
      exitcode.to_i == 0 && !crashed?
    end

    # @return [Boolean] whether the program crashed (exited by signal)
    def crashed?
      signal.nil?
    end
  end


  # Merge options so that it can be used in {Lrun.run}.
  #
  # @param [Array<Hash>] options options to be merged
  # @return [Hash] merged options
  #
  # = Example
  #
  #   Lrun.merge_options({:uid => 1000}, {:gid => 100})
  #   # => {:uid=>1000, :gid=>100}
  #
  #   Lrun.merge_options({:nice => 1, :uid => 1001}, {:nice => 2})
  #   # => {:nice=>2, :uid=>1000}
  #
  #   Lrun.merge_options({:fd => [4, 6]}, {:fd => 5}, {:fd => 7})
  #   # => {:fd=>[4, 6, 5, 7]}
  #
  #   Lrun.merge_options({:env => {'A'=>'1', 'B' => '2'}}, {:env => {'C' => '3'}})
  #   # => {:env=>[["A", "1"], ["B", "2"], ["C", "3"]]}
  #
  #   Lrun.merge_options({:uid => 1000}, {:uid => nil})
  #   # => {}
  #
  #   Lrun.merge_options({:fd => [4]}, {:fd => 5}, {:fd => nil})
  #   # => {}
  #
  #   Lrun.merge_options({:network => true, :chdir => '/tmp', :bindfs => {'/a' => '/b'}},
  #                      {:network => nil, :bindfs => {'/c' => '/d'}})
  #   # => {:chdir=>"/tmp", :bindfs=>[["/a", "/b"], ["/c", "/d"]]}
  def self.merge_options(*options)
    # Remove nil
    options.compact!

    # Check type of options
    raise ArgumentError.new("options should be Hash") unless options.all? { |o| o.is_a? Hash }

    # Merge options
    options.inject({}) do |result, option|
      option.each do |k, v|
        # Remove an option using nil
        if v.nil?
          result.delete k
          next
        end

        # Append to or Replace an option
        case LRUN_OPTIONS[k]
        when 2
          # Append to previous options
          result[k] ||= []
          result[k] += [*v]
        else
          # Overwrite previous option
          result[k] = v
        end
      end
      result
    end
  end

  # Run program using <tt>lrun</tt> binary.
  #
  # @param [Array<String>, String] commands
  #   commands to be executed
  #
  # @param [Hash] options
  #   options for lrun.
  #   Besides options in {Lrun.LRUN_OPTIONS}, there are some additional options available:
  #
  #   truncate::
  #     maximum bytes read for stderr and stdout (default: {Lrun.TRUNCATE_OUTPUT_LENGTH}).
  #   stdin::
  #     stdin file path (default: no input).
  #   stdout::
  #     stdout file path (default: a tempfile, will be deleted automatically).
  #     If this option is set, the returned result will have no stdout,
  #     you should read and delete stdout file manually.
  #   stderr::
  #     stderr file path (default: a tempfile, will be deleted automatically).
  #     If this option is set, the returned result will have no stderr,
  #     you should read and delete stderr file manually.
  #
  #   Note: lrun chroot and mounts does not affect above paths.
  #
  # @return [LrunResult]
  #
  # = Example
  #
  #   Lrun.run('echo hello')
  #   # => #<struct Lrun::Result
  #   #             memory=262144, cputime=0.002,
  #   #             exceed=nil, exitcode=0, signal=nil,
  #   #             stdout="hello\n", stderr=nil>
  #
  #   Lrun.run('java', :max_memory => 2 ** 19)
  #   # => #<struct Lrun::Result
  #   #             memory=524288, cputime=0.006,
  #   #             exceed=:memory, exitcode=0, signal=nil,
  #   #             stdout=nil, stderr=nil>
  #
  #   Lrun.run('sleep 30', :max_real_time => 1)
  #   #  => #<struct Lrun::Result
  #   #              memory=262144, cputime=0.002,
  #   #              exceed=:time, exitcode=0, signal=nil,
  #   #              stdout=nil, stderr=nil>
  #
  #    Lrun.run('cat /dev/full', :max_output => 100, :truncate => 2)
  #    # => #<struct Lrun::Result
  #    #             memory=67366912, cputime=0.05,
  #    #             exceed=:output, exitcode=0, signal=nil,
  #    #             stdout="\x00\x00", stderr=nil>  
  #
  def self.run(commands, options = {})
    tmp_out, tmp_err = nil, nil

    IO.pipe do |rfd, wfd|
      # Expand commands if commands is a string
      commands = Shellwords.split(commands) if commands.is_a? String

      # Build command line
      command_line = [LRUN_PATH, *expand_options(options), *commands]
      spawn_options = {0 => options[:stdin] || :close,
                       1 => options[:stdout] || (tmp_out = Tempfile.new("lrun.#{$$}.out")).path,
                       2 => options[:stderr] || (tmp_err = Tempfile.new("lrun.#{$$}.err")).path,
                       3 => wfd.fileno}

      # Keep pid of lrun process for checking its status
      pid = Process.spawn(*command_line, spawn_options)

      # Read fd 3, where lrun write its report
      [wfd].each(&:close)
      report = Hash[rfd.lines.map{ |l| l.chomp.split(' ', 2)}]

      # Check if lrun exits normally
      stat = Process.wait2(pid)[-1]
      if stat.signaled? || stat.exitstatus != 0
        raise LrunError.new("#{Shellwords.shelljoin command_line} exits abnormally: #{stat}. #{tmp_err.read unless tmp_err.nil?}")
      end

      # Check which limit is exceeded
      exceed = case report['EXCEED']
               when 'none'
                 nil
               when /TIME/
                 :time
               when /OUTPUT/
                 :output
               when /MEMORY/
                 :memory
               else
                 raise LrunError.new("unexpected EXCEED returned by lrun: #{report['EXCEED']}")
               end
      signal = report['SIGNALED'].to_i == 0 ? nil : report['TERMSIG'].to_i

      Result.new(report['MEMORY'].to_i,
                 report['CPUTIME'].to_f,
                 exceed,
                 report['EXITCODE'].to_i,
                 signal,
                 tmp_out && tmp_out.read(options[:truncate] || TRUNCATE_OUTPUT_LENGTH),
                 tmp_err && tmp_err.read(options[:truncate] || TRUNCATE_OUTPUT_LENGTH))
    end
  ensure
    [tmp_out, tmp_err].compact.each do |f|
      f.close rescue nil
      f.unlink rescue nil
    end
  end

  protected

  # Expand options to be used in command line
  #
  # @param [Hash] options single options hash returned by merge_options
  # @return [Array<String>] command line arguments
  #
  # = Example
  #
  #   Lrun.format_options({:chdir=>"/tmp", :bindfs=>[["/a", "/b"], ["/c", "/d"]], :fd => [2, 3]})
  #   # => ["--chdir", "/tmp", "--bindfs", "/a", "/b", "--bindfs", "/c", "/d", "--fd", "2", "--fd", "3"]
  def self.expand_options(options)
    raise ArgumentError.new('expect options to be a Hash') unless options.is_a? Hash

    options.map do |key, values|
      next unless LRUN_OPTIONS.has_key? key
      [*values].map do |value|
        ["--#{key.to_s.gsub('_', '-')}", *value]
      end
    end.compact.flatten.map(&:to_s)
  end

end
