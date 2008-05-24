require 'vissim'
require 'const'

ARTERIAL = 'a'

class Band
  NILBAND = nil
  attr_reader :tstart, :tend
  def initialize tstart, tend 
    @tstart, @tend = tstart, tend
  end
  def width
    @tend - @tstart + 1
  end
  def overlap?(other)
    to_r.include?(other.tstart) or other.to_r.include?(@start)
  end
  # returns a new band signifying the time units
  # where self and otherband is overlapping each other
  def overlap otherband
    return NILBAND unless overlap?(otherband)
    
    tstart = [@tstart, otherband.tstart].max
    tend = [@tend, otherband.tend].min
      
    Band.new(tstart, tend)  
  end
  def -(otherband)
    # find the common time indices
    common = to_a - otherband.to_a
    return NILBAND if common.empty? # perfect / complete overlap
    
    # TODO: check if common contains a non-consecutive string of integers
    Band.new(common.min, common.max)
  end
  def shift(offset)
    @tstart += offset
    @tend += offset
  end
  def to_s
    "(#{@tstart}..#{@tend})"
  end
  def to_r; (@tstart..@tend); end
  def to_a; to_r.to_a; end
end
class Coordination
  attr_reader :sc1, :sc2, :distance, :from_direction, :left_to_right
  def initialize sc1, sc2, velocity
    @sc1, @sc2 = sc1, sc2
    @default_velocity = velocity
    @distance = @@vissim.distance(@sc1,@sc2)
    @from_direction = get_from_direction(@sc1,@sc2)
    [@sc1,@sc2].each{|sc|sc.member_coordinations << self} # notify controllers
    @left_to_right = true
  end
  def traveltime(v = @default_velocity); (@distance / v).round; end
  # returns times where there is a mismatch between sc1 and sc2 ie.
  # when traffic emitted from sc1 is not received by green light at sc2
  # respecting the current offsets of these controllers and the traveltime
  # from stop-light to stop-light
  def mismatches_in_horizon h, o1, o2    
    tt = traveltime
    
    for b1 in @sc1.greenwaves(h, o1, @from_direction)
      b1.shift(tt) # project this emitted band forward in time
      bands2 = @sc2.greenwaves([h.min, b1.tend], o2, @from_direction)
      #puts "trying to chop up #{b1} using #{bands2.join(', ')}"
      # b1 shifted is now all mismatches;
      # use the bands from sc2 to chop off pieces
      begin 
        overlapping_band = bands2.find{|b| b1.overlap?(b)}
        break if overlapping_band.nil? # check if something was found
        puts "found overlapping band #{overlapping_band}"
        b1 -= overlapping_band
      end while b1
      
      yield b1 if b1
    end
  end
  # the position where a green band *may* become held up by a red light
  def conflict_position
    if @left_to_right
      @sc2.position
    else
      @sc2.position + @sc2.internal_distance
    end
  end
  # finds the utility ie. number of mismatches in the given horizon
  def eval h,o1,o2
    z = 0    
    mismatches_in_horizon(h,o1,o2){|band| z += band.width}
    z
  end
  def to_s; "Coordination from #{@sc1} to #{@sc2}"; end
end

class SimulatedAnnealing
  def initialize problem, time_limit, params
    @problem = problem
    @time_limit = time_limit
    @parameters = params
  end
  def run    
    iterations = 0
    encumbent_found_time = 0
    jumps = 0
    
    start_time = Time.now # start the clock
    
    @problem.create_initial_solution
    
    temp = @parameters[:start_temp]
    
    while (Time.now - start_time) < @time_limit
      iterations += 1
      currentval = @problem.evaluate
      
      # change "current" directly to "neighbor" (save time copying objects)
      # (@problem is capable of undoing the change)
      @problem.change
      
      neighborval = @problem.evaluate

      if neighborval < @problem.encumbent_val 
        # use the neighbor solution next iteration if it is better than the best found so far...
        @problem.store_encumbent
        encumbent_found_time = Time.now - start_time
        
        yield neighborval, currentval, @problem.solution if block_given?
      elsif Math.exp(-(neighborval - currentval) / temp) > rand 
        # and maybe even if its not!
        # (retain neighbor solution as current)
        jumps += 1
      else
        # undo the change we made / return to previous "current" solution
        @problem.undo_changes
      end

      temp *= @parameters[:alpha]
    end
    
    finish_time = Time.now - start_time
    
    {
      :solution => @problem.solution, 
      :iterations => iterations, 
      :iter_per_sec => iterations / finish_time.to_f,
      :time => finish_time,
      :jumps => jumps,
      :encumbent_time => encumbent_found_time
    }
  end
end

class CoordinationProblem
  @@test_delta_evaluation = false
  attr_reader :encumbent,:encumbent_val
  def initialize coords, scs, horizon
    @coordinations = coords
    @controllers = scs
    @horizon = horizon
    @size = @controllers.size
  end
  # return a set of offsets for each signal controllers
  def create_initial_solution
    @current = {}
    @controllers.each{|sc| @current[sc] = 0}
    @coord_contribution = {}
    @value = full_evaluation # updates current solution value
    store_encumbent
  end
  # make a clean copy of the current solution free from backreferences
  def store_encumbent    
    # synchronize encumbent and current solution
    @encumbent = {}
    @current.each{|sc,offset| @encumbent[sc] = offset}
    @encumbent_val = @value
  end
  # make a change in the current solution
  # note the change so that it may be undone, if requested
  def change
    # pick a coordination to alter
    @changed_sc = @controllers[(rand * @size).round % @size]
    @previous_setting = @current[@changed_sc]
    @current[@changed_sc] = @previous_setting + ((@previous_setting == 0 or rand < 0.5) ? 1 : -1)
            
    # perform delta-evaluation
    
    @delta_contribution = {}
    # refresh evaluations for the coordinations which involve the changed signal controller
    for coord in @changed_sc.member_coordinations
      prev_contrib = @coord_contribution[coord]
      @delta_contribution[coord] = prev_contrib
      @value -= prev_contrib
      
      o1 = @current[coord.sc1]
      o2 = @current[coord.sc2]
      newval = coord.eval(@horizon, o1, o2)
      
      @coord_contribution[coord] = newval
      @value += newval
    end
    
    # below is code to check that delta-evaluation is correct, don't delete!
    
    if @@test_delta_evaluation
      true_value = full_evaluation
      unless true_value == @value
        raise "Delta evaluation gives #{@value}, should be #{true_value}" 
      end
    end
  end
  # return a hash of signals mapping to the found offsets
  def solution; @encumbent; end
  # undo all changes made during last call to change
  def undo_changes
    # restore state of previous solution
    @current[@changed_sc] = @previous_setting
    
    # delta-restore the value of the solution
    for coord, prev_contrib in @delta_contribution
      @value -= @coord_contribution[coord]
      @coord_contribution[coord] = prev_contrib
      @value += prev_contrib
    end
  end
  def evaluate; @value; end
  # evaluate the current solution
  def full_evaluation
    @coordinations.each do |coord|
      o1 = @current[coord.sc1]
      o2 = @current[coord.sc2]
      @coord_contribution[coord] = coord.eval(@horizon, o1, o2)
    end
    @coord_contribution.values.sum
  end
end

@@vissim = Vissim.new

H = (10..90) # horizon

def parse_coordinations
  
  scs = @@vissim.controllers_with_plans
  
  coordinations = []
  scs.each_cons(2) do |sc1,sc2|
    next unless (sc2.number - sc1.number).abs == 1 # assigned numbers indicate proximity
    # setup a coordination in each direction
    coordinations << Coordination.new(sc1,sc2,@@vissim.velocity(sc1,sc2))
    #@coordinations << Coordination.new(sc2,sc1)
  end
  
  yield coordinations, scs, @@vissim
end

if __FILE__ == $0
  parse_coordinations do |coords, scs|
    #    problem = CoordinationProblem.new(coords, scs, H)
    #    siman = SimulatedAnnealing.new(problem, 2, :start_temp => 100.0, :alpha => 0.99)      
    #    
    #    result = siman.run do |newval, prevval, new_offsets|
    #      puts "Found new encumbent #{newval} vs. #{prevval}"
    #    end
    #    puts "Solver finished in #{result[:time]} seconds."
    #    puts "Jumps: #{result[:jumps]}"
    #    puts "Iterations per second: #{result[:iter_per_sec]}"
        
    coord = coords[2]
    puts coord
    puts "travel time: #{coord.traveltime}s"
    sc1 = coord.sc1
    sc2 = coord.sc2
    o1 = 0
    o2 = 10
    from_direction = coord.from_direction
    puts "#{sc1} emits:"
    puts sc1.greenwaves(H, o1, from_direction)
    puts "#{sc2} receives:"
    puts sc2.greenwaves(H, o2, from_direction)
        
    puts "found mismatches:"
    coord.mismatches_in_horizon(H, o1, o2) do |band|
      puts "yielded band: #{band}"
    end
  end
end
