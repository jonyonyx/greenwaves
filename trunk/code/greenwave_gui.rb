
require 'wx'
include Wx

class RoadTimeDiagram < Frame
  FATPENWIDTH = 3
  def initialize coords, scs, h
    super(nil, :title => "Road-Time Diagram (#{scs.size} intersections)", :size => [800,600])
    
    @signal_controllers = scs
    @coordinations = coords
    @horizon = h
    
    @tmax = [@coordinations.map{|c| c.traveltime}.sum, @horizon.max].max.to_f
    @distmax = @signal_controllers.map{|sc| sc.position + sc.internal_distance}.max.to_f + 5
          
    # all time/distance related paint jobs must translate to match this origo (0,0)
    @ox, @oy = 30, 120
      
    @fat_pen = Pen.new(BLACK)
    @fat_pen.set_width FATPENWIDTH
    
    @normal_pen = Pen.new(BLACK)
    
    @greenwave_brush = Brush.new(Colour.new(0,255,255,160))
    @bluewave_brush = Brush.new(Colour.new(0,0,255,160))
    set_background_colour WHITE    
    
    @green_pen = Pen.new(Colour.new(0,255,0))
    @green_pen.set_width FATPENWIDTH * 2
    
    @red_pen = Pen.new(Colour.new(255,0,0))
    @red_pen.set_width FATPENWIDTH * 2
    
    problem = CoordinationProblem.new(coords, scs, h)
    siman = SimulatedAnnealing.new(problem, 1, :start_temp => 100.0, :alpha => 0.5)
    
    problem.create_initial_solution
    @offset = problem.solution
    
    queue = Queue.new
    
    Thread.new do    
      siman.run do |newval, prevval, new_offsets|
        puts "Found new encumbent #{newval} vs. #{prevval}"
        queue << new_offsets
      end
    end.join
    
    Timer.every(1000) do       
      unless queue.empty?
        @offset = queue.pop     
        on_paint        
      end
    end
    
    evt_paint { on_paint }
    evt_size { on_paint }
    
    show     
  end
  def on_paint
    paint_buffered do | dc |
      dc.clear

      siz = dc.size
      h, w = siz.height, siz.width
      
      # WORKAROUND paint_buffered black background
      pen = Pen.new(get_background_colour)
      brush = Brush.new(get_background_colour)

      dc.set_pen(pen)
      dc.set_brush(brush)
      dc.draw_rectangle(0,0,w,h)
      # END WORKAROUND      
      
      gdc = GraphicsContext.create(dc)  
            
      gdc.set_pen @fat_pen
      
      ybase = h - @oy # base offset for vertical drawing ops
      
      gdc.stroke_line(0,ybase,w, ybase) # draw x-axis
      gdc.stroke_line(@ox,h,@ox,0) # draw y-axis
      
      dc.set_pen @normal_pen
      
      # scaling factor of time to pixels on the y-axis
      yscale = ybase / @tmax
      
      # scaling factor of distance to pixels on the x-axis
      xscale = (w - @ox) / @distmax
      
      # draw distance helper lines (vertical)
      10.step(@distmax.round,10) do |d|
        x = (d * xscale).round + @ox
        dc.draw_text("#{d}", x + 1, ybase)
        dc.draw_line(x,h,x,0)
      end
      
      # draw time helper lines (horizontal)
      10.step(@tmax.round,10) do |t|
        y = ybase - (t * yscale).round
        dc.draw_text("#{t}", 1, y)
        dc.draw_line(0,y,w,y)
      end
      
      # insert the names of the intersections
      for sc in @signal_controllers
        dc.draw_rotated_text(sc.to_s, (sc.position * xscale).round + @ox, h - 5, 90)
      end    

      green_lights = []
      
      # draw a band where the width corresponds to the green time
      # in the arterial direction       
      @coordinations.each do |coord|
        
        gdc.set_brush(coord.left_to_right ? @greenwave_brush : @bluewave_brush) # for filling wave bands
      
        sc1, sc2 = coord.sc1, coord.sc2
        if coord.left_to_right
          lstart = sc1.position
          lend = lstart + coord.distance
        else
          lstart = sc1.position + sc1.internal_distance
          lend = lstart - coord.distance
        end
        sc1.bands_in_horizon(@horizon, @offset[sc1]).each do |band|
          t1 = band.tstart
          t2 = band.tend
          t1, t2 = t2, t1 unless coord.left_to_right
        
          x1 = (lstart * xscale).round + @ox
          x2 = (lend * xscale).round + @ox
          y1 = ybase - (t1 * yscale).round
          y2 = ybase - ((t1 + coord.traveltime) * yscale).round
          ydelta = ((t2 - t1)*yscale).round # width of the band in pixel
          
          # mark the path of the green band
          path = gdc.create_path
          
          path.move_to_point(x1,y1)
          path.add_line_to_point(x2,y2)
          path.add_line_to_point(x2,y2 - ydelta)
          path.add_line_to_point(x1,y1 - ydelta)
          path.add_line_to_point(x1,y1)          
          
          gdc.set_pen(@fat_pen) # for drawing edges of the bands
          
          # outline the marked band using current pen then fill using green brush
          gdc.fill_path(path)       
          
          green_lights << [x1, y1, x1, y1 - ydelta]
        end
        
        # paint all mismatches (wave bands meeting a red light)
        gdc.set_pen @red_pen
        
        x = (coord.conflict_position * xscale).round + @ox
        coord.mismatches_in_horizon(@horizon, @offset[sc1], @offset[sc2]) do |band|
          t1, t2 = band.tstart, band.tend
          gdc.stroke_line(x, ybase - (t2 * yscale).round, x, ybase - (t1 * yscale).round)
        end
      end
      
      # draw a line for the green signal duration
      gdc.set_pen @green_pen
      for x1, y1, x2, y2 in green_lights
        gdc.stroke_line(x1, y1, x2, y2)
      end
      
    end
  end
end

def optimize_roadtime_diagram coords, scs, horizon  
  App.run do
    RoadTimeDiagram.new(coords, scs, horizon)
  end
end

if __FILE__ == $0
  require 'greenwave_eval'
  parse_coordinations do |coords, scs|    
    optimize_roadtime_diagram(coords, scs, H)
  end
end
  
