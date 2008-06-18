require 'vap'

class ExtendableStage
  attr_reader :name, :number, :time, :min_time, :max_time, :wait_for_sync, :shares_time_with_previous
  def extendable?
    not [@min_time,@max_time].any?{|t|t.nil?}
  end
end

class Slave
  attr_reader :name, :in_stage_channel, :detectors_for_stage
  # the channel this slaves communicates its current stage to the master
  def to_s
    "IN_STAGE_#{@name.upcase} = #{@in_stage_channel}" 
  end
  def detectors(stage)
    dets = []
    ObjectSpace.each_object(Detector){|det| dets << det if @detectors_for_stage[stage].include?(det.number)}
    dets.uniq
  end
end

CLOCK_CHANNEL = 1
SWITCH_STAGE_CHANNEL = 2
EXTEND_REQUEST_CHANNEL = 3
WAITING_FOR_SYNC = 10

DETECTOR_EXTENSION_INTERVAL = {
  1 => 4.0,
  2 => 2.0,
  3 => 3.6,
  4 => 2.0,
  5 => 2.1,
  6 => 3.6,
  7 => 2.0,
  8 => 3.2,
  9 => 3.6,
  10 => 2.1,
  11 => 4.0,
  12 => 2.0
}

class Detector
  attr_reader :number, :extension_time
  def detects_occupancy?
    @extension_time.nil?
  end
  def <=>(other)
    @number <=> other.number
  end
end

# passage and precense detectors
DETECTORS = DETECTOR_EXTENSION_INTERVAL.map do |number,time|
  Detector.new!(:number => number,:extension_time => time)
end + [20,21,30,31].map{|number|Detector.new! :number => number}

SLAVES = [
  Slave.new!(
    :name => 'nord', :in_stage_channel => 4, 
    :detectors_for_stage => {1 => [7,8,9,10,30], 2 => [20], 3 => [11,12]}
  ), Slave.new!(
    :name => 'syd',  :in_stage_channel => 5,
    :detectors_for_stage => {1 => [3,4,31,5,6], 2 => [21], 3 => [1, 2]}
  )
]

# north and south junction has 3 stages
# A is north-south going
# Av is for left-turning down on highway
# B is for traffic coming off the highway and up from the ramp
STAGES = {
  'nord' => [
    ExtendableStage.new!(:name => 'A1',  :number => 1, :min_time => 12, :max_time => 30),
    ExtendableStage.new!(:name => 'At1', :number => 2, :min_time => 22 - 12, :max_time => 44 - 30, :wait_for_sync => true),
    ExtendableStage.new!(:name => 'B1',  :number => 3, :min_time => 10, :max_time => 23)
  ],
  'syd' => [
    ExtendableStage.new!(:name => 'A2',  :number => 1, :min_time => 21 - 12, :max_time => 38 - 21),
    ExtendableStage.new!(:name => 'At2', :number => 2, :min_time => 12, :max_time => 21, :wait_for_sync => true),
    ExtendableStage.new!(:name => 'B2',  :number => 3, :min_time => 10, :max_time => 29)
  ]
}

def generate_master

  cp = CodePrinter.new

  cp.add_verb "PROGRAM master;"
  cp.add_verb "CONST LATEST_SYNC = 44;"

  cp << 'IF NOT INITIALIZED THEN'
  cp << '   INITIALIZED := 1;'
  cp << '   TRACE(ALL);'
  cp << "   complete_the_cycle := 1;"
  cp.add '   GOTO CLOCK_TICK;'
  cp.add 'END;'
  
  cp.add '/* collect current stage input from slaves */'
  SLAVES.each do |slave|
    cp << "current_stage_#{slave.name} := mget(#{slave.in_stage_channel});"
  end
  
  cp << "IF " + SLAVES.map{|slave|"(current_stage_#{slave.name} = #{WAITING_FOR_SYNC})"}.join(' AND ') + " THEN"
  cp << "   mput(#{SWITCH_STAGE_CHANNEL},3);/* send signal to allow slaves to enter stage 3 */"
  cp.add "ELSE"
  cp << "   mput(#{SWITCH_STAGE_CHANNEL},0);/* communications are static variables and must be filled each cycle second */"
  cp.add "END;"
  
  cp << "IF (T > LATEST_SYNC) AND " + SLAVES.map{|slave|"(current_stage_#{slave.name} = 1)"}.join(' AND ') + " THEN"
  cp << "   complete_the_cycle := 1;"
  cp.add "END;"

  cp.add_verb "CLOCK_TICK: IF complete_the_cycle THEN"
  cp << '   complete_the_cycle := 0;'
  cp << '   sett(1);'
  cp << "   mput(#{CLOCK_CHANNEL},1);"
  cp.add 'ELSE'
  cp << '   cur_cycle_sec := t;'
  cp << '   cycle_sec_plus1 := cur_cycle_sec + 1;'
  cp << '   sett(cycle_sec_plus1);'
  cp << "   mput(#{CLOCK_CHANNEL},cycle_sec_plus1);"
  cp.add "END"

  cp.add_verb 'PROG_ENDE:    .'

  cp.write(File.join(Vissim_dir,'master.vap'))
  puts 'Generated master controller'
end

def generate_slave slave,stages
  
  cp = CodePrinter.new

  cp.add_verb "PROGRAM slave_#{slave.name};"
  
  cp << "cur_cycle_sec := mget(#{CLOCK_CHANNEL});"
  cp << 'sett(cur_cycle_sec); /* get time from master */'
  
  cp << 'TRACE(ALL);'
  
  (0...stages.size).each do |i|
    current_stage = stages[i]
    next_stage = stages[(i + 1) % stages.size]    
    
    cp << "IF stga(#{current_stage.number}) THEN"
    
    if current_stage.number == 1
      cp << "   mput(#{slave.in_stage_channel},#{current_stage.number}); /* inform of current stage */" 
    end
    cp << "   time_in_stage := time_in_stage + 1;"
    cp << "   green_time_extension := green_time_extension - 1;"
    
    occupancy_detectors = slave.detectors(current_stage.number).find_all{|det|det.detects_occupancy?}
    unless occupancy_detectors.empty?
      cp << "   IF green_time_extension < 1 THEN"
      cp << "      green_time_extension := #{occupancy_detectors.map{|occdet|"(occt(#{occdet.number}) > 0)"}.join(' OR ')};"
      cp.add "   END;"
    end
    
    slave.detectors(current_stage.number).find_all{|det|not det.detects_occupancy?}.sort_by{|d1| d1.extension_time}.each do |passagedet|
      cp << "   IF det(#{passagedet.number}) THEN"
      cp << "      IF green_time_extension < #{passagedet.extension_time} THEN"
      cp << "         green_time_extension := #{passagedet.extension_time};"
      cp.add "      END;"
      cp.add "   END;"
    end
    
    cp << "   IF ((time_in_stage >= #{current_stage.min_time}) AND ((green_time_extension <= 0) OR (time_in_stage >= #{current_stage.max_time}))) THEN"
    
    if current_stage.wait_for_sync
      cp << "      proceed := mget(#{SWITCH_STAGE_CHANNEL});"
      cp << "      IF proceed THEN"
      cp << "         is(#{current_stage.number},#{next_stage.number});"
      cp << "         time_in_stage := 0;"
      cp << "         green_time_extension := 0;"
      cp << "         proceed := 0;"
      cp.add "      ELSE"
      cp << "         mput(#{slave.in_stage_channel},#{WAITING_FOR_SYNC}); /* waiting for synchronization */"
      cp.add "      END;"
      cp.add "      GOTO PROG_ENDE;"
    else    
      cp << "      is(#{current_stage.number},#{next_stage.number});"    
      cp << "      green_time_extension := 0;"
      unless next_stage.shares_time_with_previous
        cp << "      time_in_stage := 0;"
      end
      cp.add "      GOTO PROG_ENDE;"
    end
    
    cp.add '   END;'
    cp.add "END" + (i == stages.size - 1 ? '' : ';')
  end
  
  cp.add_verb 'PROG_ENDE:    .'

  cp.write(File.join(Vissim_dir,"#{slave.name}.vap"))
  puts "Generated slave controller '#{slave.name}'"
end

if __FILE__ == $0
  generate_master
  SLAVES.each{|slave|generate_slave slave,STAGES[slave.name]}
end
