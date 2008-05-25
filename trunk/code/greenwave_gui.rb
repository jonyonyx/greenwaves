
require 'wx'
include Wx

class RoadTimeDiagram < Frame
  FATPENWIDTH = 3
  def initialize coordinations, controllers, horizon, vissim
    super(nil, :title => "Road-Time Diagram (#{controllers.size} intersections)", :size => [800,600])
    
    @controllers = controllers
    @coordinations = coordinations
    @horizon = horizon
    
    @tmax = [@coordinations.map{|c| c.traveltime}.sum, @horizon.max].max.to_f
    @distmax = @controllers.map{|sc|sc.position}.max + 100
              
    # all time/distance related paint jobs must translate to match this origo (0,0)
    @ox, @oy = 30, 120
      
    @fat_pen = Pen.new(BLACK)
    @fat_pen.set_width FATPENWIDTH
    
    @normal_pen = Pen.new(BLACK)
    
    @left2right_brush = Brush.new(Colour.new(0,255,255,160))
    @right2left_brush = Brush.new(Colour.new(0,0,255,160))
    set_background_colour WHITE    
    
    @green_pen = Pen.new(Colour.new(0,255,0))
    @green_pen.set_width FATPENWIDTH * 2
    
    @red_pen = Pen.new(Colour.new(255,0,0))
    @red_pen.set_width FATPENWIDTH * 2
    
    problem = CoordinationProblem.new(coordinations, controllers, horizon)
    siman = SimulatedAnnealing.new(problem, 5, :start_temp => 500.0, :alpha => 0.99)
    
    problem.create_initial_solution
    @offset = problem.solution
    
    queue = Queue.new
    
    solthread = Thread.new do    
      result = siman.run do |newval, prevval, new_offsets|
        puts "Found new encumbent #{newval} vs. #{prevval}"
        queue.push new_offsets
      end
      puts "Solver finished at #{result[:iter_per_sec]} iterations per second"
    end
    
    Timer.every(500) do       
      unless queue.empty?
        @offset = queue.pop     
        on_paint        
      end
    end
    
    evt_paint { on_paint }
    evt_size { on_paint }
    
    show     
    
    solthread.join
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
      xscale = (w - @ox) / @distmax.to_f
      
      # draw distance helper lines (vertical)
      500.step(@distmax.round,500) do |d|
        x = (d * xscale).round + @ox
        dc.draw_line(x,h,x,0)
      end
      
      # draw time helper lines (horizontal)
      10.step(@tmax.round,10) do |t|
        y = ybase - (t * yscale).round
        dc.draw_text("#{t}", 1, y)
        dc.draw_line(0,y,w,y)
      end
      
      # insert the names of the intersections
      for sc in @controllers
        x = (sc.position * xscale).round + @ox
        dc.draw_text("#{sc.position}", x + 1, ybase)
        dc.draw_rotated_text(sc.name, x, h - 5, 90)
      end    

      green_lights = []
      
      # draw a band where the width corresponds to the green time
      # in the arterial direction       
      @coordinations.each do |coord|
        
        gdc.set_brush(coord.left_to_right ? @left2right_brush : @right2left_brush) # for filling wave bands
      
        sc1, sc2 = coord.sc1, coord.sc2
        if coord.left_to_right
          lstart = sc1.position
          lend = lstart + coord.distance
        else
          lstart = sc2.position + sc2.internal_distance + coord.distance
          lend = lstart - coord.distance
        end

        sc1.greenwaves(@horizon, @offset[sc1],coord.from_direction).each do |band|
          t1 = band.tstart
          t2 = t1 + band.width
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
          t1 = band.tstart
          t2 = t1 + band.width # paint tend inclusive
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

if __FILE__ == $0
  require 'greenwave_eval'
  parse_coordinations do |coords, scs, vissim|    
    App.run do
      RoadTimeDiagram.new(coords, scs, H, vissim)
    end
  end
end
  
