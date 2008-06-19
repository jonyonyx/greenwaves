
require 'const'
require 'win32ole'
require 'vap'
require 'results'
require 'measurements'

puts "#{Time.now}: BEGIN"

thorough = true # false => quick test

if thorough
  SOLVER_TIME = 0.2 # seconds
  SOLVER_ITERATIONS = 1 # number of times to rerun SA solver, trying to get better solutions

  RUNS = 1#0 # number of simulation runs per test
  SIMULATION_TIME =  2 * MINUTES_PER_HOUR * Seconds_per_minute # simulation seconds  
  RESOLUTION = 10 # steps per simulation second
else
  SOLVER_TIME = 2 # seconds
  SOLVER_ITERATIONS = 1 # number of times to rerun SA solver, trying to get better solutions

  RUNS = 1 # number of simulation runs per test
  SIMULATION_TIME =  1200 
  RESOLUTION = 3 # steps per simulation second
end

testqueue = [
  #{:testname => 'DOGS with bus priority', :dogs_enabled => true, :buspriority => true},
  {:testname => 'DOGS', :dogs_enabled => true},
  #{:testname => 'Basic program with bus priority', :buspriority => true},
  {:testname => 'Basic program'},
  #{:testname => 'Modified DOGS with bus priority', :dogs_enabled => true, :use_calculated_offsets => true, :bus_priority => true},
  {:testname => 'Modified DOGS', :dogs_enabled => true, :use_calculated_offsets => true}
]

seeds = numbers(rand(100) + 1, rand(100) + 1, testqueue.size*RUNS)

calculated_offsets = {} # controller => dogs level => offset

if testqueue.any?{|test|test[:buspriority]}
  insert_measurements # bus traveltime measurements
end

puts "Loading Vissim..."

vissimnet = Vissim.new
results = NodeEvals.new(vissimnet)

# check if any test needs precalculated offsets
if testqueue.any?{|test|test[:use_calculated_offsets]}
  require 'greenwave_eval'
  
  offset_data = [['Area','Signal Controller','DOGS Level','Offset']]
  
  [[:herlev, (1..5)], [:glostrup,(9..12)]].each do |area,controller_range|
    puts "Calculating offsets for signal controllers in #{area}..."
    controllers = vissimnet.controllers.find_all{|sc|controller_range === sc.number}
    
    controllers.each{|sc| calculated_offsets[sc] = {}}
          
    coords = parse_coordinations(controllers, vissimnet)
    
    # precalculate new offsets for each valid dogs level
    (0..DOGS_MAX_LEVEL).each do |dogs_level|
      solution_candidates = []
      cycle_time = BASE_CYCLE_TIME + DOGS_TIME * dogs_level
      SOLVER_ITERATIONS.times do |i| # get a bunch of solutions to choose from for each cycle time
        puts "Offset calculation run #{i+1} for cycle time #{cycle_time}"        
        
        problem = CoordinationProblem.new(coords, 
          :cycle_time => cycle_time,
          :direction_bias => nil, 
          :change_probability => {:speed => 0.0, :offset => 1.0})    
        
        result = SimulatedAnnealing.new(problem, SOLVER_TIME, 
          :start_temp => 100.0, 
          :alpha => 0.90, 
          :no_improvement_action_threshold => 75
        ).run
        
        solution_candidates << result[:solution]
      end
      
      best_solution = solution_candidates.min
      best_solution.offset.each do |sc,offset|
        calculated_offsets[sc][dogs_level] = offset
        offset_data << [area.to_s.capitalize,sc.name,dogs_level,offset]
      end
      
      puts "Best offsets found in #{area} was for cycle time #{cycle_time}:", best_solution
    end
  end
  to_xls(offset_data,'offsets',RESULTS_FILE)
end

exit

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

  sim.Period = SIMULATION_TIME
  sim.Resolution = RESOLUTION
  sim.Speed = 0 # maximum speed
  
  # creates vap and pua files respecting the simulation parameters
  generate_controllers vissimnet, parms + 
    {:verbose => false, :offset => (parms[:use_calculated_offsets] ? calculated_offsets : nil)}, 
    workdir 
  
  print "Vissim running #{RUNS} simulation#{RUNS != 1 ? 's' : ''} of '#{simname}'... "
  
  RUNS.times do |i|
    print "#{i+1} "
    sim.RunIndex = i
    sim.RandomSeed = seeds.pop
    sim.RunContinuous
  end
  
  puts "done"
  
  results.extract_results simname, workdir
  
  processed += 1

  vissim.Exit
end

puts "PREPARING RESULTS - PLEASE WAIT!"

#to_xls(results.to_a, 'data', RESULTS_FILE)

puts "#{Time.now}: END"
