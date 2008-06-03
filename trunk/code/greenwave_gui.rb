
require 'wx'
include Wx

class RoadTimeDiagram < Frame
  FATPENWIDTH = 3
  def initialize
    super(nil, :size => [800,600])
    
    @coordinations,@controllers, @solutions, @horizon = 
      #get_dogs_scenarios
    run_simulation_annealing
    
    set_title "Road-Time Diagram (#{@controllers.size} intersections)"
    
    @tmax = (@coordinations.map{|c| c.traveltime(c.default_speed)}.max * 2 + @horizon.max).to_f
    @distmax = @controllers.map{|sc|sc.position}.max + 100
              
    # all time/distance related paint jobs must translate to match this origo (0,0)
    @ox, @oy = 30, 120
      
    @fat_pen = Pen.new(BLACK)
    @fat_pen.set_width FATPENWIDTH
    
    @normal_pen = Pen.new(BLACK)
    
    @brush = {
      true => Brush.new(Colour.new(0,255,255,160)),
      false => Brush.new(Colour.new(0,0,255,160))
    }
    
    set_background_colour WHITE    
    
    # pick a green pen for each direction
    @green_pen = {
      true => Pen.new(Colour.new(0,255,0)),
      false => Pen.new(Colour.new(0,192,0))      
    }.each_value{|pen|pen.set_width(FATPENWIDTH * 2)}
    
    @red_pen = Pen.new(Colour.new(255,0,0))
    @red_pen.set_width FATPENWIDTH * 2
    
    fetch_next_solution
    
    Timer.every(500){fetch_next_solution; on_paint}   
    
    evt_paint { on_paint }
    evt_size { on_paint }
    
    show
  end
  def fetch_next_solution    
    return if @solutions.empty?
    solution = @solutions.shift
    if solution.has_key?(:offset)
      @offset = solution[:offset]
    else
      @offset = {}
      @controllers.each{|sc|@offset[sc] = sc.offset}      
    end    
    if solution.has_key?(:speed)
      @speed = solution[:speed]
    else
      @speed = {}
      @coordinations.each{|coord| @speed[coord] = coord.default_speed}
    end        
    if solution.has_key?(:cycle_time)
      @cycle_time = solution[:cycle_time]
    else
      @cycle_time = {}
      @controllers.each{|sc| @cycle_time[sc] = sc.cycle_time}
    end
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
      
      common_cycle = @cycle_time.values.first
      # draw time helper lines (horizontal)
      common_cycle.step(@tmax.round,common_cycle) do |t|
        y = ybase - (t * yscale).round
        dc.draw_text("#{t}", 1, y)
        dc.draw_line(0,y,w,y)
      end
      
      # insert the names of the intersections
      # and current offsets
      for sc in @controllers
        x = (sc.position * xscale).round + @ox
        dc.draw_text("#{sc.position}", x + 1, ybase)
        dc.draw_text("O=#{@offset[sc]}", x - 1, ybase + 12)
        dc.draw_rotated_text(sc.name, x, h - 5, 90)
      end    

      # insert current speeds of coordinations
      for coord in @coordinations
        x = (xscale * [coord.sc1.position,coord.sc2.position].mean).round + @ox
        speed = "#{(@speed[coord] * 3.6).round}km"
        speedsign = coord.left_to_right ? "#{speed} ->" : "<- #{speed}"
        tw,th = dc.get_text_extent(speedsign)
        
        y = h - 1 - (coord.left_to_right ? 2 : 1) * th
        dc.draw_text(speedsign , (x - tw/2.0).round, y)
      end

      # true => left_to_right, false => right_to_left
      green_lights = {true => [], false => []}

      # draw a band where the width corresponds to the green time
      # in the arterial direction       
      @coordinations.each do |coord|        
        gdc.set_brush @brush[coord.left_to_right] # for filling wave bands
      
        sc1, sc2 = coord.sc1, coord.sc2
        if coord.left_to_right
          lstart = sc1.position
          lend = lstart + coord.distance
        else
          lstart = sc2.position + sc2.internal_distance + coord.distance
          lend = lstart - coord.distance
        end
        
        # TODO: draw wave bands for controllers in the ends of the arterial
        # (the internal controllers will be drawn because they are sc1 in some coordination)
        sc1.greenwaves(@horizon, @offset[sc1],coord.from_direction,@cycle_time[sc1]).each do |band|
          t1 = band.tstart
          t2 = t1 + band.width
          t1, t2 = t2, t1 unless coord.left_to_right
        
          x1 = (lstart * xscale).round + @ox
          x2 = (lend * xscale).round + @ox
          y1 = ybase - (t1 * yscale).round
          y2 = ybase - ((t1 + coord.traveltime(@speed[coord])) * yscale).round
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
          
          green_lights[coord.left_to_right] << [x1, y1, x1, y1 - ydelta]
        end
        
        # paint all mismatches (wave bands meeting a red light)
        gdc.set_pen @red_pen
        
        x = (coord.conflict_position * xscale).round + @ox
        coord.mismatches_in_horizon(@horizon,@offset[sc1],@offset[sc2],@speed[coord],@cycle_time[sc1],@cycle_time[sc2]) do |band|
          t1 = band.tstart
          t2 = t1 + band.width # paint tend inclusive
          gdc.stroke_line(x, ybase - (t2 * yscale).round, x, ybase - (t1 * yscale).round)
        end
      end
      
      # draw a line for the green signal duration
      for l2r_indc, green_lights_for_direction in green_lights
        for x1, y1, x2, y2 in green_lights_for_direction
          gdc.set_pen @green_pen[l2r_indc]
          gdc.stroke_line(x1, y1, x2, y2)
        end
      end
    end
  end
end

def print_solution(solution)
  for setting_type, settings in solution
    puts setting_type
    settings.each do |el,setting|
      puts "   #{el}: #{setting}"
    end
  end
end

if __FILE__ == $0
  require 'greenwave_eval'
  App.run{RoadTimeDiagram.new}
end

  
