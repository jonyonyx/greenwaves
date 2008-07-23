require 'vap'

class ExtendableStage
  attr_reader :name, :number, :detectors, :wait_for_sync, :greentime
  def extendable?
    not [@min_time,@max_time].any?{|t|t.nil?}
  end
  def detectors(detector_scheme)
    DETECTORS.find_all do |det|
      @detectors.include?(det.number) and
        DETECTORS_IN_SCHEME[detector_scheme].include?(det.number)
    end
  end
end

class Slave
  attr_reader :name, :in_stage_channel, :detectors_for_stage
  # the channel this slaves communicates its current stage to the master
  def to_s
    "IN_STAGE_#{@name.upcase} = #{@in_stage_channel}" 
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
  12 => 2.0, 
  17 => 2.0,
  20 => 4.3,
  21 => 2.0  
}

PRESENCE_DETECTORS = [14,15,18,19,22,23]

ALL_DETECTORS = DETECTOR_EXTENSION_INTERVAL.keys + PRESENCE_DETECTORS

DETECTORS_IN_SCHEME = {
  1 => ALL_DETECTORS - [17,21],
  2 => ALL_DETECTORS
}

class Detector
  attr_reader :number, :extension_time, :detector_type
  def in_scheme?(detector_scheme)
    DETECTORS_IN_SCHEME[detector_scheme].include?(@number)
  end
  def <=>(other)
    @number <=> other.number
  end
end

# passage and precense detectors
DETECTORS = DETECTOR_EXTENSION_INTERVAL.map do |number,time|
  Detector.new!(:number => number,:extension_time => time, :detector_type => :passage)
end + PRESENCE_DETECTORS.map{|number|Detector.new!(:number => number,:detector_type => :presence)}

#for det in DETECTORS
#  puts "#{det.number} #{det.detector_type}"
#end

SLAVES = [
  Slave.new!(
    :name => 'nord', :in_stage_channel => 4
  ), Slave.new!(
    :name => 'syd',  :in_stage_channel => 5
  )
]

DEBUG = false

def generate_master output_dir

  cp = CodePrinter.new

  cp.add_verb "PROGRAM master;"
  cp.add_verb "CONST LATEST_SYNC = 44;"

  cp << 'IF NOT INITIALIZED THEN'
  cp << '   INITIALIZED := 1;'
  cp << '   TRACE(ALL);' if DEBUG
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

  cp.write(File.join(output_dir,'master.vap'))
end

def generate_slave slave,stages,program,detector_scheme,output_dir,extra_green
  
  cp = CodePrinter.new

  cp.add_verb "PROGRAM slave_#{slave.name};"
  
  cp << "cur_cycle_sec := mget(#{CLOCK_CHANNEL});"
  cp << 'sett(cur_cycle_sec); /* get time from master */'
  
  cp << 'TRACE(ALL);' if DEBUG
  
  (0...stages.size).each do |i|
    current_stage = stages[i]
    next_stage = stages[(i + 1) % stages.size]    
    
    cp << "IF stga(#{current_stage.number}) THEN"
    
    if current_stage.number == 1
      cp << "   mput(#{slave.in_stage_channel},#{current_stage.number}); /* inform of current stage */" 
    end
    cp << "   time_in_stage := time_in_stage + 1;"
    cp << "   green_time_extension := green_time_extension - 1;"
    
    detectors = current_stage.detectors(detector_scheme).group_by{|det|det.detector_type}
    
    presence_detectors = detectors[:presence]
    unless presence_detectors.nil? or presence_detectors.empty?
      cp << "   IF green_time_extension < 1 THEN"
      cp << "      green_time_extension := #{presence_detectors.map{|occdet|"(occt(#{occdet.number}) > 0)"}.join(' OR ')};"
      cp.add "   END;"
    end
    
    if passage_detectors = detectors[:passage]    
      passage_detectors.sort_by{|d1| d1.extension_time}.each do |passagedet|
        cp << "   IF det(#{passagedet.number}) THEN"
        cp << "      IF green_time_extension < #{passagedet.extension_time} THEN"
        cp << "         green_time_extension := #{passagedet.extension_time};"
        cp.add "      END;"
        cp.add "   END;"
      end
    end
    
    adjust_cur_isl = (current_stage.wait_for_sync ? " - isl(#{current_stage.number-1},#{current_stage.number})" : '')
    tmin,tmax = current_stage.greentime[program].min, current_stage.greentime[program].max

    if extra_green and extra_stage_time = extra_green[current_stage.number]
      tmax += extra_stage_time
    end

    cp << "   IF (time_in_stage > " + 
      (adjust_cur_isl.empty? ? tmin.to_s : "(#{tmin}#{adjust_cur_isl})") + ') ' +
      "AND ((green_time_extension <= 0) OR " +
      "(time_in_stage > " +       
      (adjust_cur_isl.empty? ? tmax.to_s : "(#{tmax}#{adjust_cur_isl})") + ')) THEN'
    
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
      cp << "      time_in_stage := 0;"
      cp.add "      GOTO PROG_ENDE;"
    end
    
    cp.add '   END;'
    cp.add "END" + (i == stages.size - 1 ? '' : ';')
  end
  
  cp.add_verb 'PROG_ENDE:    .'

  cp.write(File.join(output_dir,"#{slave.name}.vap"))
end
