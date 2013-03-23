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
    #   @return [String] standard output, or <tt>nil</tt> if it is redirected in options
    #
    # @!attribute stderr
    #   @return [String] standard error output, or <tt>nil</tt> if stderr is redirected in options

    # @return [Boolean] whether the program exited without crash and has a zero exit code
    def clean?
      exitcode.to_i == 0 && !crashed?
    end

    # @return [Boolean] whether the program crashed (exited by signal)
    def crashed?
      !signal.nil?
    end
  end


  # Merge options so that it can be used in {Lrun.run}.
  #
  # @param [Array<Hash>] options options to be merged
  # @return [Hash] merged options, can be used again in {Lrun.merge_options}
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
  #   #             stdout="hello\n", stderr="">
  #
  #   Lrun.run('java', :max_memory => 2 ** 19, :stdout => '/tmp/out.txt')
  #   # => #<struct Lrun::Result
  #   #             memory=524288, cputime=0.006,
  #   #             exceed=:memory, exitcode=0, signal=nil,
  #   #             stdout=nil, stderr="">
  #
  #   Lrun.run('sleep 30', :max_real_time => 1, :stderr => '/dev/null')
  #   #  => #<struct Lrun::Result
  #   #              memory=262144, cputime=0.002,
  #   #              exceed=:time, exitcode=0, signal=nil,
  #   #              stdout="", stderr=nil>
  #
  #    Lrun.run('cat', :max_output => 100, :stdin => '/dev/urandom', :truncate => 2)
  #    # => #<struct Lrun::Result
  #    #             memory=782336, cputime=0.05,
  #    #             exceed=:output, exitcode=0, signal=nil,
  #    #             stdout="U\xE1", stderr="">
  #
  def self.run(commands, options = {})
    # Make sure lrun binary is available
    available!

    # Temp files storing stdout and stderr of target process
    tmp_out = tmp_err = nil

    # Create temp stdout, stderr files if user does not redirect them
    options = options.dup
    options[:stdout] ||= (tmp_out = Tempfile.new("lrun.#{$$}.out")).path
    options[:stderr] ||= (tmp_err = Tempfile.new("lrun.#{$$}.err")).path

    IO.pipe do |rfd, wfd|
      # Keep pid of lrun process for checking its status
      pid = spawn_lrun commands, options, wfd

      # Read fd 3, where lrun write its report
      wfd.close
      report = rfd.read

      # Check if lrun exits normally
      stat = Process.wait2(pid)[-1]
      if stat.signaled? || stat.exitstatus != 0
        raise LrunError.new("lrun exits abnormally: #{stat}. #{tmp_err.read unless tmp_err.nil?}")
      end

      # Build and return result
      build_result report, tmp_out, tmp_err, options[:truncate]
    end
  ensure
    clean_tmpfile [tmp_out, tmp_err]
  end

  # Check if lrun binary exists
  #
  # @return [Bool] whether lrun binary is found
  def self.available?
    !LRUN_PATH.nil?
  end

  # Complain if lrun binary is not available
  def self.available!
    raise "#{LRUN_BINARY} not found in PATH. Please install lrun first." unless available?
  end

  private

  # Clean temp files
  #
  # @param [Array<Tempfile>] temp_files temp files to be cleaned
  def self.clean_tmpfile(temp_files)
    temp_files.each do |file|
      file.unlink rescue nil
    end
  end

  # Expand options to be used in command line
  #
  # @param [Hash] options single options hash returned by {Lrun.merge_options}
  # @return [Array<String>] command line arguments
  #
  # = Example
  #
  #   Lrun.format_options({:chdir=>"/tmp", :bindfs=>[["/a", "/b"], ["/c", "/d"]], :fd => [2, 3]})
  #   # => ["--chdir", "/tmp", "--bindfs", "/a", "/b", "--bindfs", "/c", "/d", "--fd", "2", "--fd", "3"]
  def self.expand_options(options)
    raise ArgumentError.new('expect options to be a Hash') unless options.is_a? Hash

    command_arguments = options.map do |key, values|
      expand_option key, values
    end

    command_arguments.compact.flatten.map(&:to_s)
  end

  # Expand a single option to be used in command line
  #
  # @param [Symbol] key option name
  # @param [Array, #to_s] values option value(s)
  # @return [Array<String>] arguments used in command line
  def self.expand_option(key, values)
    return nil unless LRUN_OPTIONS.has_key? key

    [*values].map do |value|
      ["--#{key.to_s.gsub('_', '-')}", *value]
    end
  end

  # Spawn lrun process.
  #
  # @param [IO:fd] report_fd
  #   file descriptor used to receive lrun report
  #
  # @return [Integer] pid spawned process id of lrun
  def self.spawn_lrun(commands, options, report_fd)
    # Expand commands if commands is a string
    commands = Shellwords.split(commands) if commands.is_a? String

    # Build command line
    command_line = [LRUN_PATH, *expand_options(options), *commands]
    spawn_options = {0 => options[:stdin] || :close,
                     1 => options[:stdout] || (tmp_out = Tempfile.new("lrun.#{$$}.out")).path,
                     2 => options[:stderr] || (tmp_err = Tempfile.new("lrun.#{$$}.err")).path,
                     3 => report_fd.fileno}

    # Keep pid of lrun process for checking its status
    Process.spawn(*command_line, spawn_options)
  end

  # Build {Lrun::Result} from essential information.
  #
  # @return [Lrun:Result]
  def self.build_result(lrun_report, stdout = nil, stderr = nil, truncate = TRUNCATE_OUTPUT_LENGTH)
    report = Hash[lrun_report.lines.map{ |l| l.chomp.split(' ', 2)}]

    # Collect information
    memory = report['MEMORY'].to_i
    cputime = report['CPUTIME'].to_f
    exceed = parse_exceed(report['EXCEED'])
    exitcode = report['EXITCODE'].to_i
    signal = report['SIGNALED'].to_i == 0 ? nil : report['TERMSIG'].to_i
    stdout &&= stdout.read(truncate) || ''
    stderr &&= stderr.read(truncate) || ''

    # Build Result
    Result.new(memory, cputime, exceed, exitcode, signal, stdout, stderr)
  end

  # Parse exceed information from lrun report
  #
  # @param [String] report_exceed exceed reported by lrun
  # @return [Symbol, nil] exceeded limit in symbol, or <tt>nil</tt> if no limit exceeded
  def self.parse_exceed(report_exceed)
    case report_exceed
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
  end

  # Autoload {Lrun::Runner}
  autoload :Runner, 'lrun/runner'
end
