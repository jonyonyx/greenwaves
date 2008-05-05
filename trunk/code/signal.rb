##
# Classes to completely describe a signal controller:
# - interstage calculations
# - group representation and states

require 'vissim_elem'

class SignalController < VissimElem
  attr_reader :controller_type,:cycle_time,:offset,:groups,:program
  def initialize number
    super(number)
    @groups = []
  end
  
  # Methods used in bus priority
  def has_bus_priority?; @buspriority and not @buspriority.empty?; end
  def bus_detector_n; @buspriority['DETN']; end
  def bus_detector_s; @buspriority['DETS']; end
  def donor_stage; @buspriority['DONOR'].to_i; end
  def recipient_stage; @buspriority['RCPT'].to_i; end
  def is_donor? stage; stage.number == donor_stage; end
  def is_recipient? stage; stage.number == recipient_stage; end
    
  # check if all groups have a signal plan plus
  # generel checks
  def has_plans?
    @cycle_time and @offset and @groups.all?{|grp| grp.has_plan?}
  end  
  def add_group(number, opts)
    @groups << SignalGroup.new!(number,opts)
  end
  def group(number); @groups.find{|grp|grp.number == number}; end
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
          last_stage = Stage.new!((last_stage ? last_stage.number+1 : 1),
            :groups => @groups.find_all{|grp| grp.active_seconds === t})
          stagear << last_stage
        end
      end
    end
    stagear
  end
  class SignalGroup < VissimElem
    attr_reader :red_end,:green_end,:tred_amber,:tamber,:heads,:priority
    def initialize(number)
      super(number)
      @heads = [] # signal heads in this group
    end
    def add_head number, opts
      @heads << SignalHead.new!(number,opts)
    end
    def has_plan?
      @red_end and @green_end and @tred_amber and @tamber
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
    class SignalHead < VissimElem
      attr_reader :link,:lane,:at
    end
  end
end
class Stage < VissimElem
  attr_reader :groups
  def to_s; @number.to_s; end
  # determine if this stage and otherstage are
  # compatible wrt direction ie their groups give way
  # for traffic
  #
  # return true if there exist a connection from 
  # from 
  def self.direction_compatible?(fromstage, tostage)
    fromstage.groups.each do |fromgrp|
      return true if tostage.groups.any?{|togrp| fromgrp.direction == togrp.direction}
    end
  end
end
