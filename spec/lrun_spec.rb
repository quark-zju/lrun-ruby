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

describe Lrun, '#run', :unless => Lrun::LRUN_PATH.nil? do

  context "when running true and false", :if => [system('true'), system('false')] == [true, false] do

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

  context 'when running cat', :if => system('cat </dev/null >/dev/null') do
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
  end

  context 'when running echo', :if => system('echo </dev/null >/dev/null') do
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
    it 'handle errors' do
      lambda { Lrun.run('strange_non_existed_executable') }.should raise_error(Lrun::LrunError)
      lambda { Lrun.run(['--unsupported-options', 'true']) }.should raise_error(Lrun::LrunError)
    end
  end

end

