
require 'const'
require 'vap'
require 'results'
require 'measurements'
require 'turningprob'
require 'vissim_input'

puts "#{Time.now}: BEGIN"

thorough = false # false => quick test to see everything works

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

networks = [['Path','Start Time']]

processed = 0
while test = TESTQUEUE.shift
  
  processed += 1
  
  # for each time-of-day program in the test
  test[:programs].each do |program|
  
    workdir = File.join(Base_dir,'test_scenarios', "scenario#{processed}_#{test[:name].downcase.gsub(/\s+/, '_')}_#{program.name.downcase}")
        
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
    FileUtils.cp(%w{inp pua knk mdb szp fzi}.map{|ext| Dir["*.#{ext}"]}.flatten, workdir)
    
    inpfilename = Dir['*.inp'].first # Vissim => picky
    inppath = File.join(workdir,inpfilename)
    networks << [inppath,program.vissim_start_time,program.name]
  
    setup_test test[:detector_scheme], program, workdir
    
    if test[:run_vissim]
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
    end

  end # end for each test program (eg. morning, afternoon)
end

puts "Prepared #{networks.size-1} scenarios"

to_xls(networks,'networks to test',File.join(Base_dir,'results','results.xls'))

puts "#{Time.now}: END"
