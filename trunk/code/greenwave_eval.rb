require 'const'
require 'wx'
include Wx

ARTERIAL = 'a'

class SC
  def state t
    # convert the 1-based horizon second to 0-based plan indexing
    # offsets denote the delay in which the program should be started
    # and should thus be subtracted
    t_loc = (t - @offset) % @plan.length 
    @plan[t_loc]
  end
  def bands_in_horizon h
    t = h.min
    
    while t <= h.max
      if state(t) == ARTERIAL
        tstart = t
        t += 1 while state(t) == ARTERIAL
        tend = t      
        yield tstart, tend        
      end
      t += 1
    end
    
  end
  def to_s
    "SC#{@number.to_s}"
  end
end
class Coordination
  class Mismatch
  end
  def initialize
    @mismatches = []
  end
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
  def mismatches_in_horizon h
    tt = traveltime
    
    conflicts = (h.min..h.max).to_a.find_all{|t| @sc1.state(t) == ARTERIAL and not @sc2.state(t+tt) == ARTERIAL}
        
    puts conflicts.inspect
    i = 0
    while i < conflicts.size - 1
      tstart = conflicts[i]
      i += 1 while conflicts[i] + 1 == conflicts[i+1]
      yield tstart, conflicts[i]
      i += 1
    end
  end
  # the position where a green band *may* become held up by a red light
  def conflict_position
    if left_to_right
      @sc2.position
    else
      @sc2.position + @sc2.internal_distance
    end
  end
  def check_mismatch t    
    
    tt = traveltime.round    
      
    #puts "#{t}: #{from.state(t,@offset)} vs. #{t+tt}: #{sc2.state(t+tt,@offset)}"
    #puts "At second #{t}: SC1 in #{sc1.state(t,@offset)}, SC2 in #{sc2.state(t,@offset)}"
    unless @sc1.state(t) == GREEN and not @sc2.state(t+tt) == GREEN      
      dist = left_to_right ? @sc2.position : @sc1.position + @sc1.internal_distance
      @mismatches << Mismatch.new!(:from => @sc1, :to => @sc2, :conflict_time => t+tt, :at_distance => dist)
    end
  end
  def print_mismatches
    for mm in @mismatches.sort{|mm1,mm2| mm1.from_time <=> mm2.from_time} # sort by second
      from, to = mm.from, mm.to
      puts "Traffic from #{from} in second #{mm.from_time} is not received by #{to} in second #{mm.from_time + to.offset}"
    end
  end
  def eval
    @mismatches.size
  end
  def report    
    mismatchcount = @mismatches.find_all{|mm|mm.from == @sc1 and mm.to == @sc2}.length
    puts "Found #{mismatchcount} mismatches from #{@sc1} to #{@sc2}" if mismatchcount > 0 
  end
  def to_s
    "Coordination between #{@sc1} and #{@sc2}"
  end
end

H = [0,50] # horizon

CONTROLLERS = [
  {:number => 1, :plan => [ARTERIAL] * 10 + [RED] * 10, :position => 0, :internal_distance => 5,   :offset => 0},
  {:number => 2, :plan => [ARTERIAL] * 10 + [RED] * 10, :position => 20, :internal_distance => 5,  :offset => 0},
  {:number => 3, :plan => [ARTERIAL] * 10 + [RED] * 10, :position => 40, :internal_distance => 5,  :offset => 10}
]

scs = CONTROLLERS.map{|opts| SC.new! opts}

RELATIONS = [
  {:scno1 => 1, :scno2 => 2, :velocity => 4.0, :color => BLUE},
  {:scno1 => 2, :scno2 => 1, :velocity => 4.0, :color => BLACK},
  {:scno1 => 2, :scno2 => 3, :velocity => 4.0, :color => CYAN},
  {:scno1 => 3, :scno2 => 2, :velocity => 4.0, :color => BLACK}
]

coordinations = RELATIONS.map do |opts| 
  sc1 = scs.find{|sc| sc.number == opts[:scno1]}
  sc2 = scs.find{|sc| sc.number == opts[:scno2]}
  Coordination.new! opts.merge(:sc1 => sc1, :sc2 => sc2)
end

#puts "Reporting relation performance in time horizon #{H.min} to #{H.max}"
#for rel in coordinations
#  #rel.print_mismatches
#  puts rel.eval
#  #rel.report
#end
#exit()

class RoadTimeDiagram < Frame
  FATPENWIDTH = 3
  def initialize scs, coords, h
    @signal_controllers = scs
    @coordinations = coords
    @horizon = h
    
    @tmax = @coordinations.map{|c| c.traveltime  + [c.sc1.plan.length,c.sc2.plan.length].max}.sum.to_f
    @distmax = @signal_controllers.map{|sc| sc.position + sc.internal_distance}.max.to_f + 5
          
    @ox, @oy = 25, 25 # origo (0,0)
      
    @fat_pen = Pen.new
    @fat_pen.set_width FATPENWIDTH
    
    @normal_pen = Pen.new
    
    @pens = {} # make a pen for each coordination
    coords.each{|c| pen = Pen.new(c.color); pen.set_width(FATPENWIDTH); @pens[c] = pen}
    
    @green_pen = Pen.new(Colour.new(0,255,0))
    @green_pen.set_width FATPENWIDTH + 1
    
    @red_pen = Pen.new(Colour.new(255,0,0))
    @red_pen.set_width FATPENWIDTH
    
    super(nil, :title => "Road-Time Diagram (#{CONTROLLERS.size} intersections)", :size => [500,400])
    evt_paint { on_paint }
    evt_size { on_paint }
  end
  def on_paint
    paint do | dc |
      dc.clear
      
      siz = dc.size
      h, w = siz.height, siz.width
            
      dc.set_pen @fat_pen
      
      dc.draw_line(0,h - @oy,w, h - @oy) # draw x-axis
      dc.draw_line(@ox,h,@ox,0) # draw y-axis
      
      dc.set_pen @normal_pen
      
      # calculate the time frame (y-axis)
      yscale = (dc.size.height - @oy)/ @tmax
      
      # distance from first to last intersection (x-axis)
      xscale = (w - @ox) / @distmax
      
      # draw vertical lines (distance)
      5.step(@distmax.round,5) do |d|
        x = (d * xscale).round + @ox
        dc.draw_text("#{d}", x + 1, h - @oy + 1)
        dc.draw_line(x,h,x,0)
      end
      
      # draw horizontal lines (time)
      5.step(@tmax.round,5) do |t|
        y = h - (t * yscale).round - @oy
        dc.draw_text("#{t}", 1, y + 2)
        dc.draw_line(0,y,w,y)
      end
      
      @coordinations.each do |coord|
        # draw a band where the width corresponds to the green time
        # in the arterial direction        
        
        # stop the wave band this many pixels before the next intersection
        proximity_spacer = 10 
        sc1, sc2 = coord.sc1, coord.sc1
        if coord.left_to_right
          lstart = sc1.position
          lend = lstart + coord.distance
          proximity_spacer *= -1
        else
          lstart = sc2.position + sc2.internal_distance
          lend = lstart - coord.distance
        end
        sc1.bands_in_horizon(@horizon) do |t1, t2|
          #puts "t1 = #{t1}, t2 = #{t2}"
          t1, t2 = t2, t1 unless coord.left_to_right
                  
          dc.set_pen @pens[coord]
        
          x1 = (lstart * xscale).round + @ox
          x2 = (lend * xscale).round + @ox + proximity_spacer
          y1 = h - @oy - (t1 * yscale).round
          y2 = h - @oy - ((t1 + coord.traveltime) * yscale).round
          ydelta = ((t2 - t1)*yscale).round # width of the band
          
          # the slope is given by the travel time
          #ydelta = (coord.traveltime*yscale).round
          
          #          unless coord.left_to_right
          #            y1, y2 = y2, y1
          #          end
          
          dc.draw_line(x1, y1, x2, y2)
          dc.draw_line(x1, y1 - ydelta, x2, y2 - ydelta)
          
          # draw a line where the wavefront meets the next signal controller
          #dc.draw_line(x2, y1 - ydelta, x2, y2 - ydelta)
          
          # draw a line for the green signal duration
          dc.set_pen @green_pen
          dc.draw_line(x1, y1, x1, y1 - ydelta)          
          
        end
        
        next unless coord.left_to_right
        dc.set_pen @red_pen
        
        x = (coord.conflict_position * xscale).round + @ox
        # paint all mismatches (wave bands meeting a red light)
        coord.mismatches_in_horizon(@horizon) do |t1, t2|
          puts "Conflict in #{coord} from #{t1} to #{t2}"
          dc.draw_line(x - 3, h - @oy - (t2 * yscale).round, x - 3, h - @oy - (t1 * yscale).round)
        end
      end
      
    end
  end
end

App.run do
  RoadTimeDiagram.new(scs, coordinations, H).show
end
  
