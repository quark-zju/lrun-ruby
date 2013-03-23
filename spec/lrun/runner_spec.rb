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
require 'lrun/runner'

describe Lrun::Runner, '#new' do

  it 'creates a runner' do
    Lrun::Runner.new.class.should == Lrun::Runner
  end

  it 'accepts options' do
    Lrun::Runner.new(:uid => 2, :gid => 3).options.should == {:uid => 2, :gid => 3}
  end

  it 'rejects too many options' do
    lambda { Lrun::Runner.new({:uid => 2}, {:gid => 3}) }.should raise_error(ArgumentError)
  end

end

describe Lrun::Runner, '#where' do

  let(:runner) { Lrun::Runner.new(:uid => 2, :fd => 2, :tmpfs => {'/tmp' => 0}) }

  it 'change options' do
    runner.where(:uid => 3).options[:uid].should == 3
  end

  it 'add options' do
    runner.where(:fd => 3).options[:fd].should == [2, 3]
    runner.where(:fd => [4, 5]).options[:fd].should == [2, 4, 5]
    runner.where(:tmpfs => {'/usr/bin' => 1}).options[:tmpfs].should == [["/tmp", 0], ["/usr/bin", 1]]
  end

  it 'delete options' do
    runner.where(:uid => nil).options[:fd].should_not include(:uid)
    runner.where(:fd => nil).options.keys.should_not include(:fd)
    runner.where(:fd => nil, :uid => nil, :tmpfs => nil).options.should be_empty
  end

  it 'does not change original options' do
    lambda {
      runner.where(:uid => 5, :fd => nil, :tmpfs => {'/a' => 2}, :gid => 6)
    }.should_not change(runner, :options)
  end

end

describe Lrun::Runner, '#run', :if => Lrun.available? do

  let(:runner) { Lrun::Runner.new(:uid => 2, :fd => 2, :tmpfs => {'/tmp' => 0}) }

  it 'runs' do
    runner.run('echo a').stdout.should == "a\n"
  end

  it 'passes options' do
    runner.env('A' => 42).run(['sh', '-c', 'echo $A']).stdout.chomp.should == '42'
  end

end
