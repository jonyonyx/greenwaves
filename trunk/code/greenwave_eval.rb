require 'vissim'
require 'const'

ARTERIAL = 'a'

class Band
  attr_reader :tstart, :tend, :width
  def initialize tstart, tend 
    raise "A waveband must start before it ends" if tstart > tend
    @tstart, @tend = tstart, tend
  end
  def overlap?(other); to_r.overlap?(other.to_r); end
  def width; @tend - @tstart + 1; end
  # returns a list of bands, which are the result of subtracting other from self
  def subtract(other)
    case [@tstart <=> other.tstart, @tend <=> other.tend]
    when [0,0], [1,-1], [0,-1], [1,0] # self is completely covered by other
      []
    when [-1,-1], [1,1] # self lies before or after other and nothing can be subtracted
      [copy]
    when [-1,1] # start before other start and end is after other end, multiple bands
      [Band.new(@tstart,other.tstart - 1),Band.new(@tend + 1,other.tend)]
    when [-1,0] # starts before other but ends at same time
      [Band.new(@tstart,other.tstart - 1)]
    when [0,1] # starts same time as other but ends after
      [Band.new(@tend + 1,other.tend)]
    else
      raise "Should not get here. Attempted #{self} - #{other}"
    end
  end
  def shift!(offset); @tstart += offset ; @tend += offset; @as_range = nil end
  def to_s; "(#{to_r})"; end
  def to_r; @as_range ||= (@tstart..@tend); end
  def to_a; to_r.to_a; end
  def copy; Band.new(@tstart,@tend); end
end
class Coordination
  attr_reader :sc1, :sc2, :distance, :from_direction, :left_to_right, :default_speed
  def initialize sc1, sc2, speed
    @sc1, @sc2 = sc1, sc2
    @default_speed = speed
    @from_direction = get_from_direction(@sc1,@sc2)
    @left_to_right = @from_direction == ARTERY[:sc1][:from_direction]
    
    # simplify things and visualization by always taking the distance
    # in the primary direction
    @distance = @left_to_right ? VISSIM.distance(@sc1,@sc2) : VISSIM.distance(@sc2,@sc1)
    [@sc1,@sc2].each{|sc|sc.member_coordinations << self} # notify controllers
  end
  def traveltime(s); (@distance / s).round; end
  # returns times where there is a mismatch between sc1 and sc2 ie.
  # when traffic emitted from sc1 is not received by green light at sc2
  # respecting the current offsets of these controllers and the traveltime
  # from stop-light to stop-light
  def mismatches_in_horizon h, o1, o2, s, c1 = @sc1.cycle_time, c2 = @sc2.cycle_time
    tt = traveltime(s)
    
    for b1 in @sc1.greenwaves(h, o1, @from_direction, c1)
      b1.shift!(tt) # project this emitted band forward in time
      uncovered_bands = [b1]
      bands2 = @sc2.greenwaves(b1.to_r, o2, @from_direction, c2)
      # b1 shifted is now all potential mismatches;
      # use the bands from sc2 to chop off pieces
      while b2 = bands2.shift and not uncovered_bands.empty?
        b1 = uncovered_bands.pop
        remaining = b1.subtract(b2)
        uncovered_bands.concat remaining
      end
      
      uncovered_bands.each{|b|yield b}
    end
  end
  # the position where a green band *may* become held up by a red light
  def conflict_position
    @left_to_right ? @sc2.position : (@sc1.position - @distance + @sc1.internal_distance)
  end
  def eval_speed s
    (@default_speed - s) ** 2 # quadratic punishment of deviation from default speed
  end; private :eval_speed
  # Finds the utility ie. number of mismatches in the given horizon.
  # Mixing apples and bananas.
  def eval h,o1,o2,s
    z = eval_speed
    mismatches_in_horizon(h,o1,o2,s){|band| z += band.width}
    z
  end
  # the green time displacement from green start of sc1 to
  # green start of sc2 under the given offsets and speed (travel time).
  # deviations from default speed are punished
  def eval_fixed o1, o2, s, c
    red_end_sc1 = @sc1.arterial_groups_from(@from_direction).first.red_end + o1
    red_end_sc2 = @sc2.arterial_groups_from(@from_direction).first.red_end + o2
    green_time_displacement = case red_end_sc1 <=> red_end_sc2
    when 1 # sc1 arterial green starts before sc2
      red_end_sc1 - red_end_sc2
    when -1 # must wait an entire cycle before green start of sc2
      c - (red_end_sc2 - red_end_sc1)
    else
      0 # green starts at the same time
    end
    # the value to minimize is the difference from green time displacement
    # to the expected travel time, given current speed signs
    (green_time_displacement - traveltime(s)).abs + eval_speed(s)
  end
  def to_s; "Coordination from #{@sc1.number} #{@sc1.name} to #{@sc2.number} #{@sc2.name}"; end
end

class SimulatedAnnealing
  def initialize problem, time_limit, params
    @problem = problem
    @time_limit = time_limit
    @parameters = params
  end
  def run
    result = Hash.new(0)
    result[:succesful_changes] = Hash.new(0)
    result[:action_count] = Hash.new(0) # number of times each action has been taken
    result[:action_success] = Hash.new(0) # no. times the action improved the encumbent
    
    iters_with_no_improvement = 0
    
    start_time = Time.now # start the clock
    
    @problem.create_initial_solution
    
    temp = @parameters[:start_temp]
    
    while Time.now - start_time < @time_limit
      result[:iterations] += 1
      currentval = @problem.current_value
      
      # change "current" directly to "neighbor" (save time copying objects)
      # (@problem is capable of undoing the change)
      change_type = @problem.change
      
      neighborval = @problem.current_value

      if neighborval < @problem.encumbent_value 
        # use the neighbor solution next iteration if it is better than the best found so far...
        @problem.store_encumbent
        result[:encumbent_found_time] = Time.now - start_time
        result[:encumbent_found_iteration] = result[:iterations]
        result[:succesful_changes][change_type] += 1
        iters_with_no_improvement = 0
        
        yield neighborval, currentval, "change of #{change_type}", @problem.solution if block_given?
      else
        iters_with_no_improvement += 1
        if Math.exp(-(neighborval - currentval) / temp) > rand 
          # and maybe even if its not!
          # (retain neighbor solution as current)
          result[:accepted] += 1
        else # undo the change we made / return to previous "current" solution          
          @problem.undo_changes
        end
      end
      
      # adjust temperature,
      # check if some action must be taken due to being stuck
      if iters_with_no_improvement > @parameters[:no_improvement_action_threshold]
        if temp < @parameters[:start_temp] and rand < 0.5 # pure reheating
          prevtemp = temp.round          
          temp = @parameters[:start_temp]
          puts "Reheat from #{prevtemp.round} to #{temp.round}"
          action = :reheat
        else
          action = [:random_restart,:focus].rand
          previous_value = @problem.current_value
          @problem.send(action)
          puts "#{action}, value change from #{previous_value} to #{@problem.current_value}"
        end
        
        if @problem.current_value < @problem.encumbent_value
          # the action (random restart) actually gave the best solution thus far!
          yield @problem.current_value, @problem.encumbent_value, action, @problem.solution if block_given?
          @problem.store_encumbent
          result[:action_success][action] += 1
        end
        
        result[:action_count][action] += 1
        iters_with_no_improvement = 0
      else
        temp *= @parameters[:alpha]        
      end
    end
    time = Time.now - start_time
    result + 
      {:encumbent_value => @problem.encumbent_value,
      :time => time,
      :solution => @problem.solution,
      :iter_per_sec => (result[:iterations] / time.to_f).round} + 
      @problem.statistics
  end
end

class CoordinationProblem
  attr_reader :current_value,:encumbent_value,:statistics
  def initialize coords, scs, opts
    @coordinations = coords
    @controllers = scs
    
    if opts[:horizon]
      @scheme = :stage_based
      @horizon = opts[:horizon]
    elsif opts[:cycle_time]
      @scheme = :common_cycle_time
      @current_cycle_time = opts[:cycle_time] # seconds
    end
    
    @coord_contribution = {} # individual contribution from coordinations to current value
    @delta_contribution = {} # bookkeeping of changes goes here
    
    @current_offset = {} ; @encumbent_offset = {} 
    @current_speed  = {} ; @encumbent_speed  = {}     
    
    @statistics = Hash.new(0)
  end
  def create_initial_solution
    @controllers.each{|sc| @current_offset[sc] = 0}    
    @coordinations.each{|coord| @current_speed[coord] = coord.default_speed}    
    @current_value = full_evaluation # updates current solution value
    store_encumbent
  end
  SPEED_INCREMENT = 5 / 3.6 # 5KM/H
  SPEED_CHANGE_OPTIONS = [-SPEED_INCREMENT, SPEED_INCREMENT]
  SPEED_CHANGE_OPTIONS_WITH_ZERO = SPEED_CHANGE_OPTIONS + [0]
  def random_restart
    @controllers.each{|sc| @current_offset[sc] = rand(sc.cycle_time)}
    @coordinations.each do |coord|
      @current_speed[coord] = coord.default_speed + SPEED_CHANGE_OPTIONS_WITH_ZERO.rand
    end
    @current_value = full_evaluation
  end
  # returns focus to encumbent solution
  def focus
    @current_offset = @encumbent_offset.copy
    @current_speed = @encumbent_speed.copy
    @current_value = full_evaluation
  end
  # make a clean copy of the current solution free from backreferences
  def store_encumbent    
    @statistics[:encumbents] += 1 if @encumbent_value # do not count the first "encumbent" (initial solution)
    # Synchronize encumbent and current solution
    # 
    # For offsets, lower all offsets by a constant factor so until the first offset becomes
    # zero. This has no effect on the solution but trims the offset so that
    # a "master" controller (offset = zero) appears.
    @encumbent_offset = {}
    min_offset = @current_offset.map{|sc,offset|offset}.min
    @current_offset.each{|sc,offset|@encumbent_offset[sc] = offset - min_offset}
    @encumbent_speed = @current_speed.copy
    @encumbent_value = @current_value
  end
  # make a change in the current solution
  # note the change so that it may be undone, if requested
  def change
    @last_change = if rand < 0.2
      change_speed; :speed
    else
      change_offset; :offset
    end
  end
  # Change the speed of one coordination between two controllers.
  def change_speed        
    @statistics[:speed_changes] += 1
    # pick a coordination to change speed for
    @changed_coord = @coordinations.rand
    @previous_speed = @current_speed[@changed_coord]
    @current_speed[@changed_coord] = @previous_speed + SPEED_CHANGE_OPTIONS.rand
    delta_eval(@changed_coord)
  end; private :change_speed
  def change_offset
    @statistics[:offset_changes] += 1
    @changed_sc = @controllers.rand
    @previous_offset = @current_offset[@changed_sc]
    @current_offset[@changed_sc] = @previous_offset + (rand < 0.5 ? -1 : 1)
            
    # perform delta-evaluation
    delta_eval(*@changed_sc.member_coordinations)
  end; private :change_offset
  def delta_eval(*coords)
    @current_value_check = @current_value # note previous value for delta restore integrity check
    
    # refresh evaluations for the coordinations which involve the changed signal controller
    @delta_contribution.clear # forget how to revert to the previous solution
    for coord in coords      
      # Make a note of the previous contribution of this
      # coordination and subtract it from the current solution value
      @delta_contribution[coord] = @coord_contribution[coord]
      @current_value -= @coord_contribution[coord]      
      
      # Recalculate the contribution of the coordination
      # under the new settings...
      @coord_contribution[coord] = eval_coord(coord)
      
      # ... and insert the new value into the current solution value
      @current_value += @coord_contribution[coord]
    end
  end
  def eval_coord(coord)    
    o1, o2, s = 
      @current_offset[coord.sc1], 
      @current_offset[coord.sc2], 
      @current_speed[coord]
      
    case @scheme 
    when :common_cycle_time
      coord.eval_fixed(o1, o2, s, @current_cycle_time)
    when :stage_based
      coord.eval(@horizon, o1, o2, s)
    else
      raise "Don't know how to evaluate offsets and speeds in a '#{@scheme}' scheme"
    end
  end; private :eval_coord
  # return a hash of signals mapping to the found offsets and speeds
  def solution; {:offset => @encumbent_offset, :speed => @encumbent_speed}; end
  # undo all changes made during last call to change
  def undo_changes
    @statistics[:rejected] += 1
    
    # restore state of previous solution
    case @last_change
    when :offset
      @current_offset[@changed_sc] = @previous_offset
    when :speed
      @current_speed[@changed_coord] = @previous_speed
    else
      raise "Don't know how to undo a '#{@last_change}' change!"
    end
    
    # delta-restore the value of the solution
    for coord, prev_contrib in @delta_contribution
      @current_value -= @coord_contribution[coord]
      @coord_contribution[coord] = prev_contrib
      @current_value += prev_contrib
    end
    raise "Restoration of previous solution failed after change in #{@last_change}:\n" +
      "expected value #{@current_value_check} got #{@current_value}" if (@current_value_check - @current_value).abs > EPS
  end
  # evaluate the current solution
  def full_evaluation
    @coordinations.each{|coord| @coord_contribution[coord] = eval_coord(coord)}
    @coord_contribution.values.sum
  end
end

VISSIM = Vissim.new

def parse_coordinations
  
  # filter out relevant signal controllers
  scs = VISSIM.controllers_with_plans.find_all do |sc|
    #sc.number <= 5 # Herlev
    sc.number >= 9 # Glostrup
  end
  
  # adjust the position of controllers such the left-most one
  # is at position zero  
  minpos = scs.map{|sc|sc.position}.min
  scs.each{|sc|sc.update :position => (sc.position - minpos)}
  
  coordinations = []
  scs.each_cons(2) do |sc1,sc2|
    next unless (sc2.number - sc1.number).abs == 1 # assigned numbers indicate proximity
    # setup a coordination in each direction
    coordinations << Coordination.new(sc1,sc2,VISSIM.speed(sc1,sc2))
    coordinations << Coordination.new(sc2,sc1,VISSIM.speed(sc2,sc1))
  end
  
  yield coordinations, scs
end
def get_dogs_scenarios
  parse_coordinations do |coords, scs|
    
    solutions = numbers(80,20,1).map do |dogs_cycle_time|
      puts dogs_cycle_time
      cycle_time = {}
      scs.each{|sc|cycle_time[sc] = dogs_cycle_time}
      {:cycle_time => cycle_time}
    end
    
    return coords, scs, solutions, (0..300)
  end
end
def run_simulation_annealing
  parse_coordinations do |coords, scs|
    #require 'profile'
    
    horizon = (0..300)
    
    solutions = []
    #opts = {:horizon => horizon}
    opts = {:cycle_time => BASE_CYCLE_TIME}
    problem = CoordinationProblem.new(coords, scs, opts)
    siman = SimulatedAnnealing.new(problem, 2, :start_temp => 100.0, :alpha => 0.95, :no_improvement_action_threshold => 50)
    
    result = siman.run do |newval, prevval, change_desc, solution|
      puts "Found new encumbent #{newval} vs. #{prevval} by #{change_desc}"
      solutions << solution
    end
    puts "Solver finished in #{result[:time]} seconds."
    puts "Completed iterations: #{result[:iterations]}"
    puts "Iterations per second: #{result[:iter_per_sec]}"
    puts "Actions taken on no improvement:"
    result[:action_count].each do |action,count|
      puts "   #{action}: #{count} of which #{result[:action_success][action]} improved encumbent"
    end
    puts "Reheatings: #{result[:reheats]}"
    puts "Restarts: #{result[:restarts]}"
    puts "Accepted solutions (jumps): #{result[:accepted]}"
    puts "Rejected solutions: #{result[:rejected]}"
    puts "Encumbents found: #{result[:encumbents]}"
    puts "Final solution value: #{result[:encumbent_value]}"
    
    return coords, scs, solutions, horizon
  end
end
if __FILE__ == $0
  run_simulation_annealing
end
