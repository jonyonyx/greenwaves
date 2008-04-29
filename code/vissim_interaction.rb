# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 
require 'const'
require 'win32ole'
require 'vap'
require 'results'
require 'measurements'

puts "BEGIN"

RUNS = 10 # number of runs per test

testqueue = ThreadSafeArray.new

testqueue << {:testname => 'DOGS and bus',     :dogs_enabled => true,  :buspriority => true}
testqueue << {:testname => 'DOGS no bus',      :dogs_enabled => true,  :buspriority => false}
testqueue << {:testname => 'No DOGS with bus', :dogs_enabled => false, :buspriority => true}
testqueue << {:testname => 'No DOGS or bus',   :dogs_enabled => false, :buspriority => false}

insert_measurements

puts "Loading Vissim..."

vissimnet = Vissim.new(Default_network)

threads = []

results = NodeEvals.new(vissimnet)
    
# start a vissim instance for each processor / core
# (vissim does not use parallel computations before 5.10)
CPUCOUNT = 1 #ENV['NUMBER_OF_PROCESSORS'].to_i
CPUCOUNT.times do |i|
  threads << Thread.new(i) do |threadnum|
    
    # create a working directory for each vissim instance
    # to avoid clashes in database tables and parameters
    instancename = "vissim_instance#{threadnum+1}"
    
    workdir = File.join(Tempdir, instancename)
    begin
      Dir.mkdir workdir
    rescue
      # workdir already exists, clear it
      FileUtils.rm Dir[File.join(workdir,'*')]
    end
    
    Dir.chdir Vissim_dir
    
    # copy all relevant files to the instance workdir
    FileUtils.cp(%w{inp pua knk mdb}.map{|ext| Dir["*.#{ext}"]}.flatten, workdir)
        
    vissim = WIN32OLE.new('VISSIM.Vissim')
    
    # load the instance copy of the network
    tempnet = Dir[File.join(workdir, '*.inp')].first.gsub('/',"\\")
    #puts "Vissim #{instancename} loading '#{tempnet}'"
    vissim.LoadNet tempnet
    vissim.LoadLayout "#{Vissim_dir}speed.ini"

    sim = vissim.Simulation

    sim.Period = 2 * Minutes_per_hour * Seconds_per_minute # simulation seconds
    #sim.Period = 1200 # simulation seconds
    sim.Resolution = 1 # steps per simulation second

    processed = 0
    while parms = testqueue.pop
      simname = parms[:testname]
  
      # creates vap and pua files respecting the simulation parameters
      generate_controllers vissimnet, parms, workdir 
  
      print "Vissim instance #{threadnum+1} running #{RUNS} simulation#{RUNS != 1 ? 's' : ''} of '#{simname}'... "
  
      RUNS.times do |i|
        print "#{i+1} "
        sim.RunIndex = i
        sim.RandomSeed = rand
        sim.RunContinuous
      end
  
      puts "done"
  
      results.extract_results simname, workdir
  
      processed += 1
    end

    puts "Completed #{processed} simulation#{processed != 1 ? 's' : ''}, exiting Vissim..."

    vissim.Exit
  end
end

threads.reverse_each{|t| t.join}

puts "Preparing Results..."

results.to_xls

puts "END"
