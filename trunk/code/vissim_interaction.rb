
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
  RESOLUTION = 10 # steps per simulation second
end

require "#{Project}_tests" # file must define a TESTQUEUE constant list

seeds = numbers(rand(100) + 1, rand(100) + 1, TESTQUEUE.size*RUNS)

vissimnet = Vissim.new
results = NodeEvals.new(vissimnet)

networks = [['Path','Scenario','Time of Day']]

processed = 0
while test = TESTQUEUE.shift
  
  processed += 1
  
  # for each time-of-day program in the test
  test[:programs].each do |program|
    next if program == DAY# or program == MORNING
  
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
    vissim_dir = test[:network_dir] ? File.join(Base_dir,test[:network_dir]) : Vissim_dir
    Dir.chdir(vissim_dir)
    
    # copy all relevant files to the instance workdir
    FileUtils.cp(%w{inp pua knk mdb szp}.map{|ext| Dir["*.#{ext}"]}.flatten, workdir)
    
    inpfilename = Dir['*.inp'].first # Vissim => picky
    inppath = File.join(workdir,inpfilename)
    networks << [inppath,processed,program.name]
  
    if Project == 'dtu'
      # creates vap and pua files respecting the simulation parameters
      generate_controllers vissimnet, test + 
        {:offset => (test[:use_calculated_offsets] ? calculated_offsets : nil)}, 
        workdir
    else
      setup_test test[:detector_scheme], program, workdir
    end
  end # end for each test program (eg. morning, afternoon)
end

to_xls(networks,'networks to test',File.join(Base_dir,'results','results.xls'))

puts "#{Time.now}: END"
