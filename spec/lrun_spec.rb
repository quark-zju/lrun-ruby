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

require 'spec_helper'
require 'lrun'
require 'tempfile'

describe Lrun do

  it 'can not be instantiated' do
    lambda { Lrun.new }.should raise_error(NoMethodError)
  end

end

describe Lrun, '#merge_options' do

  it 'accepts empty options' do
    Lrun.merge_options(nil).should == {}
    Lrun.merge_options({}).should == {}
  end

  it 'rejects non-Hash' do
    lambda { Lrun.merge_options(1) }.should raise_error(TypeError)
    lambda { Lrun.merge_options('a', 'b') }.should raise_error(TypeError)
  end

  it 'merges options' do
    Lrun.merge_options({:uid => 1000}, {:gid => 100, :interval => 2}, {:network => false}).should == {:network => false, :uid => 1000, :gid => 100, :interval => 2}
    Lrun.merge_options({:fd => [4, 6]}, {:fd => 5}, {:fd => 7}).should == {:fd=>[4, 6, 5, 7]}
    Lrun.merge_options({:bindfs => {'/a' => '/b'}}, {:bindfs => {'/c' => '/d'}}).should == {:bindfs => [["/a", "/b"], ["/c", "/d"]]}
  end

  it 'overwrite options' do
    Lrun.merge_options({:uid => 1}, {:uid => 3}, {:uid => 4}).should == {:uid => 4}
  end

  it 'removes options' do
    Lrun.merge_options({:uid => 1000}, {:uid => nil}).should == {}
    Lrun.merge_options({:fd => [4, 5, 6]}, {:fd => 7}, {:fd => nil}).should == {}
  end

end

describe Lrun, '#run', :if => Lrun.available? do

  context "when running true and false" do
    let(:true_result) { Lrun.run('true') }
    let(:false_result) { Lrun.run('false') }

    it 'returns exitcode' do
      true_result.exitcode.should == 0
      false_result.exitcode.should_not == 0
    end

    it 'returns cpu and memory usage' do
      true_result.memory.should > 0
      true_result.cputime.should >= 0
    end

    it 'returns exceed' do
      true_result.exceed.should be_nil
      false_result.exceed.should be_nil
    end

    it 'returns stdout and stderr' do
      true_result.stdout.should == ""
      false_result.stdout.should == ""
    end

    it 'returns stderr' do
      true_result.stderr.should == ""
      false_result.stderr.should == ""
    end

    it '.clean?' do
      true_result.clean?.should be_true
      false_result.clean?.should be_false
    end

    it '.crashed?' do
      true_result.crashed?.should be_false
      false_result.crashed?.should be_false
    end
  end

  context 'when running cat' do
    it 'can redirect stdin' do
      begin
        tmpfile = Tempfile.new("input")
        tmpfile.write("foo bar")
        tmpfile.close
        Lrun.run('cat', stdin: tmpfile.path).stdout.should == "foo bar"
      ensure
        tmpfile.unlink rescue nil
      end
    end

    it 'does not alter options' do
      options = {}
      Lrun.run('cat', options)
      options.should == {}
    end
  end

  context 'when running echo' do
    it 'captures stdout' do
      Lrun.run('echo Hello').stdout.should == "Hello\n"
      Lrun.run(['echo', 'World']).stdout.should == "World\n"
    end

    it 'can redirect stdout' do
      begin
        tmpfile = Tempfile.new("output")
        result = Lrun.run('echo blabla', stdout: tmpfile.path)
        result.stderr.should == ""
        result.stdout.should be_nil
        tmpfile.read.should == "blabla\n"
      ensure
        tmpfile.unlink rescue nil
      end
    end
  end

  context 'when setting limit options' do
    it 'returns exceed' do
      Lrun.run('sleep 1', :max_real_time => 0.1).exceed.should == :time
      Lrun.run(['cat', '/dev/full'], :stdout => '/dev/null', :max_cpu_time => 0.1).exceed.should == :time
      Lrun.run(['cpp', '/dev/full', '-o', '/dev/null'], :max_memory => 1_000_000).exceed.should == :memory
      Lrun.run(['cat', '/dev/full'], :stdout => '/dev/null', :max_output => 1_000).exceed.should == :output
    end
  end

  context 'when parameters are illegal' do
    it 'rejects empty command' do
      lambda { Lrun.run(nil) }.should raise_error(ArgumentError)
      lambda { Lrun.run('') }.should raise_error(ArgumentError)
      lambda { Lrun.run([]) }.should raise_error(ArgumentError)
    end

    it 'handles lrun errors' do
      lambda { Lrun.run('strange_non_existed_executable') }.should raise_error(Lrun::LrunError)
      lambda { Lrun.run(['--unsupported-options', 'true']) }.should raise_error(Lrun::LrunError)
    end
  end

end

