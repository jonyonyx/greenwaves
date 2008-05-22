##
# Classes to completely describe a signal controller:
# - interstage calculations
# - group representation and states

require 'vissim_elem'
require 'vissim_routes'

class SignalController < VissimElem
  attr_reader :controller_type,:cycle_time,:offset,:groups,:program,
    :bus_detector_n,:bus_detector_s, # north and southern detector suffixes
  :donor_stage,:recipient_stage, # donor and recipient stages
  :member_coordinations # list of coordinations, in which this controller participates
  def initialize number
    super(number)
    @groups = []
    @member_coordinations = []
  end
  
  # Methods used in bus priority
  def has_bus_priority?; not [@bus_detector_n,@bus_detector_s,@donor_stage,@recipient_stage].any?{|e|e.nil?}; end
  def is_donor? stage; stage.number == donor_stage; end
  def is_recipient? stage; stage.number == recipient_stage; end
    
  # check if all groups have a signal plan plus
  # generel checks
  def has_plans?; not [@cycle_time,@offset].any?{|e|e.nil?} and @groups.all?{|grp| grp.has_plan?}; end  
  def add_group(number, opts); @groups << SignalGroup.new!(number,opts); end
  def group(number); @groups.find{|grp|grp.number == number}; end
  def arterial_groups; @groups.find_all{|grp| grp.serves_artery?}; end
  def interstage_active?(cycle_sec)
    # all-red phases are considered interstage
    return true if @groups.all?{|grp| grp.color(cycle_sec) == RED}
    
    # check for ordinary interstages
    @groups.any?{|grp| [YELLOW,AMBER].include? grp.color(cycle_sec)}
  end
  def priority stage
    return NONE unless stage.instance_of?(Stage) # interstages are fixed length
    
    # a stage has major priority if it contains all groups (for this SC)
    # which should receive major priority rather than just some of them
    if (@groups.find_all{|grp| grp.priority == MAJOR}- stage.groups).empty?
      MAJOR
    else
      stage.groups.any?{|grp| grp.priority == MINOR} ? MINOR : NONE
    end
  end
  # Finds all arterial groups, which are active in the given time - respecting offset -
  # that serves the arterial traffic coming from the given direction.
  def state(t,o,from_direction)
    # convert the 1-based horizon second to 0-based plan indexing
    # offsets denote the delay in which the program should be started
    # and should thus be subtracted
    arterial_groups.find_all do |grp|
      grp.active_seconds === ((t - o) % @cycle_time) and
        grp.arterial_from.include?(from_direction)
    end
  end
  # Finds the green wave bands emitted from the given arterial direction
  # in the given time horizon. The offset of the signal controller is taken
  # as a parameter and will affect the start-and end times of the bands.
  def greenwaves(horizon,offset,from_direction)
    wavebands = []
    @groups.find_all{|grp|grp.arterial_from.include?(from_direction)}.each do |group|
      active_seconds = group.active_seconds
      tstart_base = horizon.min + offset + active_seconds.min
      tend_base = horizon.min + offset + active_seconds.max
      #puts "#{group} #{active_seconds}"
      cycle_count = 0
      loop do
        cycle_offset = cycle_count * @cycle_time
        tstart = tstart_base + cycle_offset
        break unless tstart < horizon.max # only show bands in the horizon
        # create the band. the end time might be cut off by the horizon limits
        wavebands << Band.new(tstart, [tend_base + cycle_offset, horizon.max].min)
        cycle_count += 1
      end
    end
    wavebands
  end
  def stages
    return @stagear if @stagear # cache hit
    last_stage = nil
    last_interstage = nil
    @stagear = []
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
        if @groups.all?{|grp| grp.color(t) == grp.color(t-1)}
          stagear << last_stage
        else
          last_stage = Stage.new!((last_stage ? last_stage.number+1 : 1),
            :groups => @groups.find_all{|grp| grp.active_seconds === t})
          stagear << last_stage
        end
      end
    end
    @stagear
  end
  def served_arterial_links(from_direction)
    arterial_groups.find{|grp| grp.arterial_from.include? from_direction}.served_arterial_links
  end
  class SignalGroup < VissimElem
    attr_reader :red_end,:green_end,:tred_amber,:tamber,:heads,:priority
    def initialize(number)
      super(number)
      @heads = [] # signal heads in this group
    end
    def add_head number, opts; @heads << SignalHead.new!(number,opts); end
    def has_plan?; not [@red_end,@green_end,@tred_amber,@tamber].any?{|e|e.nil?}; end
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
    # returns a range of seconds in a cycle in vehicles are permitted
    # to cross the stop lines of the group
    def active_seconds
      green_start = @red_end + @tred_amber + 1
      if green_start < @green_end
        (green_start..@green_end)
      else
        # (green_end+1..green_start) defines the red time
        (1..@green_end) # todo: handle the case of green time which wraps around
      end
    end
    def serves_artery?; @heads.any?{|h| h.serves_artery?}; end
    def served_arterial_links; arterial_heads.map{|h| h.position_link}.uniq; end
    # Scan over the signal heads in this group extracting all
    # road segments, which are arterial and the from direction.
    # If none such markings are found among the heads, this group serves
    # only minor-road traffic. Otherwise at least some heads
    # serve the arterial (major road) and the direction from which is served
    # becomes the answer
    def arterial_from; @heads.map{|h| h.arterial_from}.uniq - [nil]; end
    def arterial_heads; @heads.find_all{|h| h.serves_artery?}; end
    # (see description for Stage-method of same name)
    # This check depends on each signal head and the link on which it is placed.
    # When the vissim network was loaded the arterial links and connectors were marked
    # with the from direction by which they serve traffic.
    # To be direction compatible this group must serve arterial traffic
    # as well as the other group and they must serve the same from direction
    def direction_compatible(downstream_group)      
      serves_artery? and arterial_from == downstream_group.arterial_from    
    end
    class SignalHead < VissimElem
      attr_reader :position_link,:lane,:at
      def serves_artery?; not arterial_from.nil?; end
      def arterial_from; @position_link.arterial_from; end
      def to_s; "Head #{number} on #{@position_link} at #{at}"; end
    end
  end
end
# A stage defines a period of time in which one or more signal groups are
# active ie. green simultaneously.
class Stage < VissimElem
  attr_reader :groups
  def to_s; @number.to_s; end
  # determine if this stage and otherstage are
  # compatible wrt direction ie their groups give way
  # for the same traffic stream through the artery
  #
  # return true if there exist a connection from
  def direction_compatible?(downstream_stage)
    @groups.any? do |grp|
      downstream_stage.groups.any?{|togrp| grp.direction_compatible(togrp)}
    end
  end
  def arterial?; @groups.any?{|grp|grp.serves_artery?};end
end
