##
# Classes to completely describe a signal controller:
# - interstage calculations
# - group representation and states

require 'vissim_elem'

class SignalController < VissimElem
  attr_reader :controller_type,:cycle_time,:offset,:groups,:program
  def initialize number, attributes
    super
    update attributes
    @groups = {}
  end
  def update attributes
    super
    @controller_type = attributes['TYPE']
    @cycle_time = attributes['CYCLE_TIME'].to_f
    @offset = attributes['OFFSET'].to_f
    @program = attributes['PROGRAM']
  end
  def add group
    @groups[group.number] = group
  end
  def interstage_active?(cycle_sec)
    # all-red phases are considered interstage
    return true if @groups.values.all?{|grp| grp.color(cycle_sec) == RED}
    
    # check for ordinary interstages
    @groups.values.any?{|grp| [YELLOW,AMBER].include? grp.color(cycle_sec)}
  end
  def stages
    last_stage = nil
    last_interstage = nil
    stagear = []
    for t in (1..@cycle_time)
      if interstage_active?(t)
        if last_interstage
          last_interstage = last_interstage.succ unless stagear.last == last_interstage
        else
          last_interstage = 'a'
        end
        stagear << last_interstage
      else
        # check if any colors have changed
        if @groups.values.all?{|grp| grp.color(t) == grp.color(t-1)}
          stagear << last_stage
        else
          last_stage = Stage.new(last_stage ? last_stage.number+1 : 1,@groups.values.find_all{|grp| grp.active_seconds === t})
          stagear << last_stage
        end
      end
    end
    stagear
  end
  def to_s
    str = super + "\n"    
    for grpnum in @groups.keys.sort
      str += "   #{@groups[grpnum]}\n"
    end
    str
  end
end
class SignalGroup < VissimElem
  attr_reader :red_end,:green_end,:tred_amber,:tamber,:heads,:priority
  def initialize(number,attributes)
    super
    update attributes
    @heads = [] # signal heads in this group
  end
  def update attributes
    super
    @red_end = attributes['RED_END'].to_i
    @green_end = attributes['GREEN_END'].to_i
    @tred_amber = attributes['TRED_AMBER'].to_i
    @tamber = attributes['TAMBER'].to_i
    @priority = attributes['PRIORITY'] # The DOGS priority level for this group
  end
  def add head
    @heads << head
  end
  def color cycle_sec
    case cycle_sec
    when active_seconds
      GREEN 
    when (@red_end+1..@red_end+@tred_amber)
      AMBER
    when (@green_end..@green_end+@tamber)
      YELLOW
    else
      RED
    end
  end
  def active_seconds
    green_start = @red_end + @tred_amber + 1
    if green_start < green_end
      (green_start..green_end)
    else
      # (green_end+1..green_start) defines the red time
      (1..green_end) # todo: handle the case of green time which wraps around
    end
  end
end
class SignalHead < VissimElem
  attr_reader :position_link,:lane
  def initialize number, attributes
    super
    update attributes
  end
  def update attributes
    super
    @position_link = attributes['POSITION LINK'].to_i
    @lane = attributes['LANE'].to_i
  end
end
class Stage < VissimElem
  attr_reader :groups
  def initialize number, groups
    super number,{}
    @groups = groups
  end
  def to_s
    @number.to_s
  end
  def priority
    group_priorities = @groups.map{|grp| grp.priority}.uniq
    raise "Warning: mixed group priorities in same stage #{@groups.map{|grp| "#{grp.name} => #{grp.priority}"}}" if group_priorities.length > 1
    group_priorities.first 
  end
end