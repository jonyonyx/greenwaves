require 'const'

ARTERIAL = 'a'

class Band
  attr_reader :tstart, :tend
  def initialize tstart, tend
    raise "Start time (#{tstart}) is not less than end time (#{tend})" if tend < tstart    
    @tstart, @tend = tstart, tend
  end
  def width
    @tend - @tstart + 1
  end
  def is_overlapping?(otherband)
    otherband.tstart < @tend and otherband.tend > @tstart
  end
  # returns a new band signifying the time units
  # where self and otherband is overlapping each other
  def overlap otherband
    return NILBAND unless is_overlapping?(otherband)
    
    tstart = [@tstart, otherband.tstart].max
    tend = [@tend, otherband.tend].min
      
    Band.new(tstart, tend)  
  end
  def -(otherband)
    # find the common time indices
    common = to_a & otherband.to_a
    
    # TODO: check if common contains a non-consecutive string of integers
    Band.new(common.min, common.max)
  end
  def to_s
    #"(#{@tstart}..#{@tend}) (#{width})"
    ar = to_a
    "#{ar.inspect} (#{ar.size})"
  end
  def to_a
    (@tstart..@tend).to_a
  end
  NILBAND = self.new(0,0)
end

class SC
  attr_reader :member_coordinations, :number, :position, :internal_distance
  def initialize
    @offset = 0    
    @member_coordinations = []
  end
  def state t, o
    # convert the 1-based horizon second to 0-based plan indexing
    # offsets denote the delay in which the program should be started
    # and should thus be subtracted
    t_loc = (t - o) % @plan.length 
    @plan[t_loc]
  end
  # yields all green lights in the arterial direction
  # in the given time horizon, respecting the given controller offset
  def bands_in_horizon h, o
    
    arterial_states = (h.min..h.max).to_a.find_all{|t| state(t,o) == ARTERIAL}
    
    bands = []
    i = 0
    while i < arterial_states.size - 1
      tstart = arterial_states[i]
      i += 1 while arterial_states[i] + 1 == arterial_states[i+1]
      bands << Band.new(tstart, arterial_states[i])
      i += 1
    end
    bands
  end
  def to_s
    "Signal Controller #{@number}"
  end
  def <=> sc2
    @number <=> sc2.number
  end
end
class Coordination
  attr_reader :sc1, :sc2
  # distance from stop-line to stop-line
  def distance
    dist = (@sc1.position - @sc2.position).abs
    if left_to_right
      dist
    else # sc1 is to the right from sc2
      dist + (@sc1.internal_distance - @sc2.internal_distance)
    end
  end
  def traveltime
    distance / @velocity
  end
  # determine if sc1 is left of sc2
  def left_to_right
    @sc1.position < @sc2.position
  end
  # returns times where there is a mismatch between sc1 and sc2 ie.
  # when traffic emitted from sc1 is not received by green light at sc2
  # respecting the current offsets of these controllers and the traveltime
  # from stop-light to stop-light
  def mismatches_in_horizon h, o1, o2
    
    bands1 = @sc1.bands_in_horizon(h, (o1 + traveltime).round)
    bands2 = @sc2.bands_in_horizon(h, o2)
    
    for b1 in bands1
      overlapping_band = bands2.find{|b| b1.is_overlapping?(b)}
      if overlapping_band.nil?
        yield b1
      else
        remaining_band = b1 - overlapping_band 
        yield remaining_band       
      end
    end
    
    #    conflicts = (h.min..h.max).to_a.find_all{|t| @sc1.state(t,o1) == ARTERIAL and not @sc2.state(t+tt,o2) == ARTERIAL}
    #        
    #    i = 0
    #    while i < conflicts.size - 1
    #      tstart = conflicts[i]
    #      i += 1 while conflicts[i] + 1 == conflicts[i+1]
    #      yield tstart + o2, conflicts[i] + o2
    #      i += 1
    #    end
  end
  # the position where a green band *may* become held up by a red light
  def conflict_position
    if left_to_right
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
  def to_s
    "Coordination between #{@sc1} and #{@sc2}"
  end
end

H = [0,75] # horizon

CONTROLLERS = [
  {:number => 1, :plan => [ARTERIAL] * 10 + [RED] * 10, :position => 0, :internal_distance => 0},
  {:number => 2, :plan => [ARTERIAL] * 10 + [RED] * 10, :position => 10, :internal_distance => 0},
  {:number => 3, :plan => [ARTERIAL] * 10 + [RED] * 10, :position => 20, :internal_distance => 0}
]

RELATIONS = [
  {:scno1 => 1, :scno2 => 2, :velocity => 2.0},
  {:scno1 => 2, :scno2 => 1, :velocity => 6.0},
  {:scno1 => 2, :scno2 => 3, :velocity => 3.0},
  {:scno1 => 3, :scno2 => 2, :velocity => 4.0}
]

def parse_coordinations
  scs = CONTROLLERS.map{|opts| SC.new! opts}
  
  coordinations = RELATIONS.map do |opts| 
    sc1 = scs.find{|sc| sc.number == opts[:scno1]}
    sc2 = scs.find{|sc| sc.number == opts[:scno2]}
    coord = Coordination.new!(opts.merge(:sc1 => sc1, :sc2 => sc2))
    sc1.member_coordinations << coord
    sc2.member_coordinations << coord
    coord
  end
  
  yield coordinations, scs
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

      if neighborval < currentval 
        # use the neighbor solution next iteration if it is better...
        yield neighborval, currentval, @problem.solution if block_given?
        @problem.store_encumbent
        encumbent_found_time = Time.now - start_time
      elsif Math.exp(-(neighborval - currentval) / temp) > rand 
        # and maybe even if its not!
        # (retain neighbor solution as current)
      else
        # undo the change we made / return to previous "current" solution
        @problem.undo_changes
      end

      temp *= @parameters[:alpha]
    end
    
    {
      :solution => @problem.solution, 
      :iterations => iterations, 
      :time => Time.now - start_time,
      :encumbent_time => encumbent_found_time
    }
  end
end

class CoordinationProblem
  @@test_delta_evaluation = true
  attr_reader :encumbent
  def initialize coords, scs, horizon
    @coordinations = coords
    @signal_controllers = scs
    @horizon = horizon
    @size = @signal_controllers.size
  end
  # return a set of offsets for each signal controllers
  def create_initial_solution
    @current = {}
    @signal_controllers.each{|sc| @current[sc] = 0}
    store_encumbent
    @coord_contribution = {}
    @value = full_evaluation # updates current solution value
  end
  # make a clean copy of the current solution free from backreferences
  def store_encumbent    
    @encumbent = {}
    @current.each{|sc,offset| @encumbent[sc] = offset}
  end
  # make a change in the current solution
  # note the change so that it may be undone, if requested
  def change
    # pick a coordination to alter
    @changed_sc = @signal_controllers[(rand * @size).round % @size]
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
  def solution
    @encumbent
  end
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
  def evaluate
    @value
  end
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

if __FILE__ == $0
  parse_coordinations do |coords, scs|
#    problem = CoordinationProblem.new(coords, scs, H)
#    siman = SimulatedAnnealing.new(problem, 1, :start_temp => 100.0, :alpha => 0.5)        
    
    coord = coords[0]
    puts coord
    
    coord.mismatches_in_horizon(H, 0, 10) do |band|
      puts band
    end
  end
end