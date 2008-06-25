
require 'const'
require 'vap'
require 'results'
require 'measurements'
require 'turningprob'
require 'vissim_input'

puts "#{Time.now}: BEGIN"

thorough = false # false => quick test

if thorough
  SOLVER_TIME = 2 # seconds
  SOLVER_ITERATIONS = 10 # number of times to rerun SA solver, trying to get better solutions

  RUNS = 10 # number of simulation runs per test
  RESOLUTION = 10 # steps per simulation second
else
  SOLVER_TIME = 1 # seconds
  SOLVER_ITERATIONS = 1 # number of times to rerun SA solver, trying to get better solutions

  RUNS = 1 # number of simulation runs per test
  RESOLUTION = 5 # steps per simulation second
end

require "#{Project}_tests" # file must define a TESTQUEUE constant list

seeds = numbers(rand(100) + 1, rand(100) + 1, TESTQUEUE.size*RUNS)

vissimnet = Vissim.new
results = NodeEvals.new(vissimnet)

processed = 0
while test = TESTQUEUE.shift
  
  processed += 1
  
  # for each time-of-day program in the test
  test[:programs].each do |program|
  
    simname = test[:name]
    workdir = File.join(Tempdir, "vissim_scenario#{processed}_#{program.to_s.downcase}")
  
    begin
      Dir.mkdir workdir
    rescue
      # workdir already exists, clear it
      FileUtils.rm Dir[File.join(workdir,'*')]
    end
    
    # move into the default vissim directory for this project
    # or the directory of the requested vissim network in order to copy it to
    # a temporary location
    vissim_dir = program.network_dir ? File.join(Base_dir,program.network_dir) : Vissim_dir
    Dir.chdir(vissim_dir)
    
    # copy all relevant files to the instance workdir
    FileUtils.cp(%w{inp pua knk mdb szp sak fzi}.map{|ext| Dir["*.#{ext}"]}.flatten, workdir)
    
    inpfilename = Dir['*.inp'].first # Vissim => picky
    inppath = File.join(workdir,inpfilename)
    
    vissim = WIN32OLE.new('VISSIM.Vissim')
    
    # load the instance copy of the network
    tempnet = inppath.gsub('/',"\\") # Vissim => picky
    vissim.LoadNet tempnet
    vissim.LoadLayout File.join(Vissim_dir,'speed.ini') # speed AND evaluation conf

    sim = vissim.Simulation

    sim.Period = program.duration
    sim.Resolution = RESOLUTION
    sim.Speed = 0 # maximum speed
  
    if Project == 'dtu'
      # creates vap and pua files respecting the simulation parameters
      generate_controllers vissimnet, test + 
        {:offset => (test[:use_calculated_offsets] ? calculated_offsets : nil)}, 
        workdir
    else
      setup_test vissimnet, test[:traffic_actuated], program, workdir
    end
    
    print "Vissim running #{RUNS} simulation#{RUNS != 1 ? 's' : ''} of '#{simname}'... "
    
    RUNS.times do |i|
      print "#{i+1} "
    
      # setting and incrementing RunIndex causes vissim to store
      # the results of the consecutive runs in the same table
      sim.RunIndex = i 
      sim.RandomSeed = seeds.pop
      sim.RunContinuous
    end
  
    puts "done"
  
    # the results from all runs in this test scenario can now be extracted
    results.extract_results "#{simname} #{program.name}", workdir

    vissim.Exit
  end # end for each test program (eg. morning, afternoon)
end

puts "PREPARING RESULTS - PLEASE WAIT!"

to_xls(results.to_a, 'data', RESULTS_FILE)

# take cycle times and link evaluations from the last run of DOGS and mod DOGS
require 'extract_cycle_times'
require 'extract_links_evals'

puts "#{Time.now}: END"
