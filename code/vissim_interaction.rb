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

testqueue = [
  {:testname => 'DOGS and bus',     :dogs_enabled => true,  :buspriority => true},
  {:testname => 'DOGS no bus',      :dogs_enabled => true,  :buspriority => false},
  {:testname => 'No DOGS with bus', :dogs_enabled => false, :buspriority => true},
  {:testname => 'No DOGS or bus',   :dogs_enabled => false, :buspriority => false},
]

insert_measurements

puts "Loading Vissim..."

vissimnet = Vissim.new
results = NodeEvals.new(vissimnet)
    
processed = 0
while parms = testqueue.pop
  simname = parms[:testname]
  workdir = File.join(Tempdir, "vissim#{simname.downcase.gsub(/\s+/, '_')}")
  begin
    Dir.mkdir workdir
  rescue
    # workdir already exists, clear it
    FileUtils.rm Dir[File.join(workdir,'*')]
  end
    
  Dir.chdir Vissim_dir
    
  # copy all relevant files to the instance workdir
  FileUtils.cp(%w{inp pua knk mdb szp}.map{|ext| Dir["*.#{ext}"]}.flatten, workdir)
        
  vissim = WIN32OLE.new('VISSIM.Vissim')
    
  # load the instance copy of the network
  tempnet = Dir[File.join(workdir, '*.inp')].first.gsub('/',"\\") # Vissim => picky
  vissim.LoadNet tempnet
  vissim.LoadLayout "#{Vissim_dir}speed.ini"

  sim = vissim.Simulation

  sim.Period = 2 * MINUTES_PER_HOUR * Seconds_per_minute # simulation seconds
  #sim.Period = 600 # simulation seconds
  sim.Resolution = 5 # steps per simulation second
  sim.Speed = 0 # maximum speed
  
  # creates vap and pua files respecting the simulation parameters
  generate_controllers vissimnet, parms + {:verbose => false}, workdir 
  
  print "Vissim running #{RUNS} simulation#{RUNS != 1 ? 's' : ''} of '#{simname}'... "
  
  RUNS.times do |i|
    print "#{i+1} "
    sim.RunIndex = i
    sim.RandomSeed = rand(1000000)
    sim.RunContinuous
  end
  
  puts "done"
  
  results.extract_results simname, workdir
  
  processed += 1

  vissim.Exit
end

puts "Preparing Results..."

to_xls(results.to_a, 'data', "#{Base_dir}results\\results.xls")

puts "END"
