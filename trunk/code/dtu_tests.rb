TESTQUEUE = [
  {:testname => 'DOGS with bus priority', :dogs_enabled => true, 
    :buspriority => true},
  {:testname => 'DOGS', :dogs_enabled => true},
  {:testname => 'Basic program with bus priority', :buspriority => true},
  {:testname => 'Basic program'},
  {:testname => 'Modified DOGS with bus priority', :dogs_enabled => true, 
    :use_calculated_offsets => true, :bus_priority => true},
  {:testname => 'Modified DOGS', :dogs_enabled => true, 
    :use_calculated_offsets => true}
]

calculated_offsets = {} # controller => dogs level => offset

# check if any test needs precalculated offsets
if TESTQUEUE.any?{|test|test[:use_calculated_offsets]}
  require 'greenwave_eval'
  
  offset_data = [['Area','Signal Controller','DOGS Level','Offset']]
  
  [[:herlev, (1..5)], [:glostrup,(9..12)]].each do |area,controller_range|
    controllers = vissimnet.controllers.find_all{|sc|controller_range === sc.number}
    
    controllers.each{|sc| calculated_offsets[sc] = {}}
          
    coords = parse_coordinations(controllers, vissimnet)
    
    # precalculate new offsets for each valid dogs level
    (0..DOGS_MAX_LEVEL).each do |dogs_level|
      print "Calculating offsets in #{area} for DOGS level #{dogs_level}:"
      solution_candidates = []
      cycle_time = BASE_CYCLE_TIME + DOGS_TIME * dogs_level
      SOLVER_ITERATIONS.times do |i| # get a bunch of solutions to choose from for each cycle time
        print " #{SOLVER_ITERATIONS - i}"
        
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
      
      puts
      
      best_solution = solution_candidates.min
      best_solution.offset.each do |sc,offset|
        calculated_offsets[sc][dogs_level] = offset
        offset_data << [area.to_s.capitalize,sc.name,dogs_level,offset]
      end
    end
  end
  to_xls(offset_data,'offsets',RESULTS_FILE)
end

if TESTQUEUE.any?{|test|test[:buspriority]}
  insert_measurements # bus traveltime measurements
end
