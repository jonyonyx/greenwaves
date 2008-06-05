require 'vap'

class ExtendableStage
  attr_reader :name, :number, :time, :min_time, :max_time
  def extendable?
    [@min_time,@max_time].all?{|t|t}
  end
end

class Slave
  attr_reader :name, :in_stage_channel
  # the channel this slaves communicates its current stage to the master
  def to_s
    "IN_STAGE_#{@name.upcase} = #{@in_stage_channel}" 
  end
end

CLOCK_CHANNEL = 1
SWITCH_STAGE_CHANNEL = 2
EXTEND_REQUEST_CHANNEL = 3

CHANNELS = "/* defining friendly names for communication channels */
   CYCLE_SEC = #{CLOCK_CHANNEL},
   /* master orders for slaves to change stage are put here: */
   SWITCH_TO_STAGE = #{SWITCH_STAGE_CHANNEL},
   /* extend requests from slaves for a numbered stage enter on this channel: */
   REQUEST_FOR_EXTENSION = #{EXTEND_REQUEST_CHANNEL}"

# north and south junction has 3 stages
# A is north-south going
# Av is for left-turning down on highway
# B is for traffic coming off the highway and up from the ramp
STAGES = [
  ExtendableStage.new!(:name => 'A',  :number => 1, :time => 34),
  ExtendableStage.new!(:name => 'Av', :number => 2, :min_time => 12, :max_time => 24),
  ExtendableStage.new!(:name => 'B',  :number => 3, :min_time => 16, :max_time => 30)
]

EXT_STAGE_TIMES = STAGES.find_all{|s|s.extendable?}.map do |s|
  "MIN_TIME_#{s.number} = #{s.min_time}," +
    "\n   MAX_TIME_#{s.number} = #{s.max_time}" 
end.join(",\n   ")

SLAVES = [
  Slave.new!(:name => 'nord', :in_stage_channel => 4),
  Slave.new!(:name => 'syd',  :in_stage_channel => 5)
]

def generate_master

  cp = CodePrinter.new

  cp.add_verb "
PROGRAM master;

CONST
   #{EXT_STAGE_TIMES},
   #{CHANNELS};
  "

  cp << 'IF NOT INITIALIZED THEN'
  cp << '   sett(1); /* start the clock */'
  cp << '   INITIALIZED := 1;'
  cp << '   time_in_stage := 0;'
  cp.add '   GOTO PROG_ENDE;'
  cp.add 'END;'
  
  cp.add '/* collect current stage input from slaves */'
  SLAVES.each do |slave|
    cp << "current_stage_#{slave.name} := mget(#{slave.in_stage_channel});"
  end

  cp << 'request_to_extend := mget(REQUEST_FOR_EXTENSION); /* any slave wants a green time extension? */'

  (0...STAGES.size).each do |i|
    current_stage = STAGES[i]
    next unless current_stage.extendable?
    next_stage = STAGES[(i + 1) % STAGES.size]
    same_stage_check = SLAVES.map{|slave|"(current_stage_#{slave.name} = STAGE_#{current_stage.number})"}.join(' AND ')
    cp << "IF #{same_stage_check} THEN"
    cp << "   time_in_stage := time_in_stage + 1;"
    cp << "   IF (time_in_stage >= MIN_TIME_#{current_stage.number}) AND ((NOT request_to_extend) OR (time_in_stage = MAX_TIME_#{current_stage.number})) THEN"
    cp << "      mput(SWITCH_TO_STAGE,STAGE_#{next_stage.number});"
    cp << "      time_in_stage := 0;"
    if next_stage.number < current_stage.number
      cp << "      sett(0); /* completed another cycle */"
    end
    cp.add '   END;'
    cp.add 'END;'
  end

  cp << 'cur_cycle_sec := t;'
  cp << 'cycle_sec_plus1 := cur_cycle_sec + 1;'
  cp << 'sett(cycle_sec_plus1);'
  cp << 'mput(CYCLE_SEC,cycle_sec_plus1)'

  cp.add_verb 'PROG_ENDE:    .'

  cp.write(File.join(Vissim_dir,'master.vap'))
  puts 'Generated master controller'
end

def generate_slave slave
  
  cp = CodePrinter.new

  cp.add_verb "PROGRAM slave_#{slave.name};
  "
  
  cp.add_verb "CONST
   #{STAGE_NUMBERS},
   #{CHANNELS},
   CURRENT_STAGE_CHANNEL = #{slave.in_stage_channel};
  "
  
  cp.add_verb '   previous_stage := current_stage;
   current_stage := mget(SWITCH_TO_STAGE);
  '
  
  cp << "IF NOT (previous_stage = current_stage) AND stga(previous_stage) THEN"
  cp << "   is(previous_stage,current_stage);"
  cp.add 'END;'
  
  cp << 'cur_cycle_sec := mget(CYCLE_SEC);'
  cp << 'sett(cur_cycle_sec); /* get time from master */'  
  
  (0...STAGES.size).each do |i|
    current_stage = STAGES[i]
    next_stage = STAGES[(i + 1) % STAGES.size]
    
    cp << "IF stga(#{current_stage.name}) THEN"
    cp << "   mput(CURRENT_STAGE_CHANNEL,#{current_stage.name});"
    
    if not current_stage.extendable?
      cp << "   IF (t = #{current_stage.time}) THEN"
      cp << "      is(#{current_stage.number},#{next_stage.number});"
      cp.add '   END;'
    else
    end
    cp.add "END#{(next_stage.number < current_stage.number) ? '' : ';'}"
  end  
  
  cp.add_verb 'PROG_ENDE:    .'

  cp.write(File.join(Vissim_dir,"#{slave.name}.vap"))
  puts "Generated slave controller '#{slave.name}'"
end

if __FILE__ == $0
  generate_master
  SLAVES.each{|slave|generate_slave slave}
end
