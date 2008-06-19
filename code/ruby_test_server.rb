require 'drb'
require 'greenwave_eval'

class Tester
  def run_solver saparms, solver_time, cycle_time, coords, change_offset_prob
    problem = CoordinationProblem.new(coords, 
      :cycle_time => cycle_time,
      :change_probability => {:speed => 1 - change_offset_prob, :offset => change_offset_prob})    
        
    SimulatedAnnealing.new(problem, solver_time, saparms).run
  end  
end

def start_test_server(uri)
  DRb.start_service(uri, Tester.new)
    
  puts "Started service at #{DRb.uri}"

  DRb.thread.join

  DRb.stop_service
end

if __FILE__ == $0
  start_test_server(ARGV.shift)
end