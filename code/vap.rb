require 'vissim'
require 'dogs_threshold'

class CodePrinter
  def initialize 
    @fmt_num = "S%03d: %s"
    @fmt_nonum = "#{' '*6}%s"
    @line_number = 0
    @lines = []
  end
  # add a line *with* a line number
  def <<(line)
    @lines << format(@fmt_num,@line_number,line)
    @line_number += 1
  end
  # add a line without a line number
  def add line; @lines << format(@fmt_nonum,line); end
  # adds a line verbatim
  def add_verb line; @lines << line; end
  def to_s; @lines.join("\n"); end
  def write filepath; File.open(filepath, 'w') { |f|  f << to_s}; end
end
def get_generated_info
  "/* This program was automatically generated by #{$0.split("/").last} on #{Time.now.strftime(EU_date_fmt)} */"
end
def gen_master opts, cycles_to_remain_in_level, outputdir

  cp = CodePrinter.new
  
  cp.add_verb get_generated_info
    
  cp.add_verb "PROGRAM DOGS_MASTER ; /* #{opts[:area]} */"
  cp.add_verb ''
  
  # Count (intensity) bounds are estimated for a counting period of BASE_CYCLE_TIME seconds
  # Occupied rate- (percentages) and count-bounds are taken from the DOGS material
  # and are identical for both areas on O3
  cnt_bounds = opts[:cnt_bounds]
  occ_bounds = opts[:occ_bounds]
  
  cp.add_verb "CONST 
        BASE_CYCLE_TIME = #{BASE_CYCLE_TIME},
        DN = #{opts[:dn]},
        DS = #{opts[:ds]},
        SMOOTHING_FACTOR = 0.5,
        ENABLE_CNT = #{cnt_bounds[:upper].min},
        DISABLE_CNT = #{cnt_bounds[:lower].min},
        ENABLE_OCC = #{occ_bounds[:upper].min},
        DISABLE_OCC = #{occ_bounds[:lower].min},
        DOGS_FORCE_DISABLE = #{opts[:dogs_enabled] ? 0 : 1};
  "
  
  cp.add_verb "/* Expressions */
    cycle_sec := T;
    cycle_sec_plus1 := cycle_sec + 1;
    CURRENT_CYCLE_TIME := BASE_CYCLE_TIME + #{DOGS_LEVEL_GREEN} * DOGS_LEVEL;
  "
  
  cp << "IF NOT cycle_sec THEN /* Perform initialization */"
  cp << "  DN_CNT := 0; DS_CNT := 0; CYCLES_AT_LEVEL:= 0; /* Keeps Vissim from nagging */"
  cp << "  SetT(1); /* Start the clock */"
  cp << "  TRACE(ALL); /* Enable tracing */" if ENABLE_VAP_TRACING[:master]
  cp.add "  GOTO PROG_ENDE"
  cp.add "END;"
  
  cp << "Marker_put(1,DOGS_LEVEL); Marker_put(2,cycle_sec);"
  cp << "IF cycle_sec < CURRENT_CYCLE_TIME THEN"
  cp << "   SetT(cycle_sec_plus1);"
  cp.add "ELSE"
  cp << "   SetT(1);"
  cp << "   PREV_CYCLES_AT_LEVEL := CYCLES_AT_LEVEL;"
  cp << "   CYCLES_AT_LEVEL := PREV_CYCLES_AT_LEVEL + 1;"
  cp.add "END;"
  
  cp << "IF T <> 1 THEN"
  cp << "   GOTO PROG_ENDE;"
  cp.add "ELSE /* read and clear detectors every cycle */"
  cp.add_verb "/* When DOGS_LEVEL > 0 the counting period is extended along with the green time 
                  and the counts from the detections must be corrected before comparing to the cnt threshold values */"
  cp << "   DOGS_CORRECTION_FACTOR := BASE_CYCLE_TIME / CURRENT_CYCLE_TIME;"
  cp << "   DN_CNT := DOGS_CORRECTION_FACTOR * (DN_CNT + SMOOTHING_FACTOR * (Rear_ends(DN) - DN_CNT)); "
  cp << "   DS_CNT := DOGS_CORRECTION_FACTOR * (DS_CNT + SMOOTHING_FACTOR * (Rear_ends(DS) - DS_CNT));"    
  cp << "   DN_OCC := Occup_rate(DN) * 100; /* Occupied rate percentage */"    
  cp << "   DS_OCC := Occup_rate(DS) * 100;"
  cp.add_verb "/* Measuring on detectors, which are used to determine current dogs level */"
  for occ_det in opts[:occ_dets]
    cp << "   D#{occ_det}_OCC := Occup_rate(#{occ_det}) * 100;"
  end
  # counting detectors needs to be cleared
  for cnt_det in opts[:cnt_dets]
    cp << "   D#{cnt_det}_CNT := Rear_ends(#{cnt_det});"
    cp << "   cre(#{cnt_det});"
  end
  unless opts[:cnt_dets].include? opts[:dn]
    cp << "   cre(DN);"
  end
  unless opts[:cnt_dets].include? opts[:ds]
    cp << "   cre(DS);"
  end
  cp << "   IF (CYCLES_AT_LEVEL >= #{cycles_to_remain_in_level}) THEN"
  cp << "      CYCLES_AT_LEVEL := 0; /* allow fall through to dogs level change */"
  cp.add "   ELSE"
  cp.add "      GOTO ADJUST_LEVEL; /* make sure the new level is fully implemented */"
  cp.add "   END;"
  cp.add "END;"
  
  cp.add_verb "/* Enable dogs if north or south bounds are reached. If dogs is enabled but we are below enable-bounds, keep dogs enabled until the lower threshold is reached */"
  cp << "DOGS_ENABLED := " +
    "((DN_CNT >= ENABLE_CNT) OR (DS_CNT >= ENABLE_CNT) AND (DN_OCC >= ENABLE_OCC) OR (DS_OCC >= ENABLE_OCC)) "+
    "OR DOGS_ENABLED AND " +
    "((DN_CNT > DISABLE_CNT) OR (DS_CNT > DISABLE_CNT) AND (DN_OCC > DISABLE_OCC) OR (DS_OCC > DISABLE_OCC));"
  cp << "IF DOGS_FORCE_DISABLE OR NOT DOGS_ENABLED THEN"
  cp << "   DOGS_LEVEL := 0;"
  cp.add "ELSE" 
  for level in (0...DOGS_LEVELS)
    cp << "  IF DOGS_LEVEL = #{level} THEN"
    cp << "     IF #{opts[:occ_dets].map{|det| "(D#{det}_OCC > #{occ_bounds[:upper][level]})"}.join(' OR ')} OR #{opts[:cnt_dets].map{|det| "(D#{det}_CNT > #{cnt_bounds[:upper][level]})"}.join(' OR ')} THEN"
    cp << "         NEW_DOGS_LEVEL := #{level+1};"
    cp.add "     END;"
    if level > 0
      cp << "     IF #{opts[:occ_dets].map{|det| "(D#{det}_OCC < #{occ_bounds[:lower][level]})"}.join(' AND ')} AND #{opts[:cnt_dets].map{|det| "(D#{det}_CNT < #{cnt_bounds[:lower][level]})"}.join(' AND ')} THEN"
      cp << "         NEW_DOGS_LEVEL := #{level-1};"
      cp.add "     END;"
    end
    cp.add "  END;"
  end
  cp.add "END;"
  cp.add_verb "/*|NEW_DOGS_LEVEL - DOGS_LEVEL| = 0 or 1 */"
  cp.add_verb "ADJUST_LEVEL: IF DOGS_LEVEL <> NEW_DOGS_LEVEL THEN /* DOGS level changes are implemented by increments of +- 5 seconds per cycle */"
  cp << "   IF DOGS_LEVEL < NEW_DOGS_LEVEL THEN"
  cp << "      DOGS_LEVEL_STEP := DOGS_LEVEL + 0.5;"
  cp.add "   ELSE"
  cp << "      DOGS_LEVEL_STEP := DOGS_LEVEL - 0.5;"
  cp.add "   END;"
  cp << "   DOGS_LEVEL := DOGS_LEVEL_STEP;"
  cp.add "END"
  cp.add_verb 'PROG_ENDE:    .'

  cp.write File.join(outputdir, "DOGS_MASTER_#{opts[:name].upcase}.vap")
end

Replacement = {221 => 'ae', 248 => 'oe', 206 => 'aa'} # be sure to use character codes for non-ascii chars
  
# Below is code for generating a DOGS SLAVE controller in VAP
def gen_vap sc, outputdir, offset
  cp = CodePrinter.new
  
  cp.add_verb get_generated_info  
  
  name = sc.name.downcase.gsub(' ','_')
  cp.add_verb "PROGRAM #{name.gsub(/[^a-z]/){ |match| Replacement[match.to_s[0]]}}; /* #{sc.program} */"
  cp.add_verb ''
  
  stages = sc.stages
  
  uniq_stages = stages.uniq.find_all{|s| s.instance_of? Stage}
  
  if USEDOGS
    # prepare the split of DOGS extra time between major and minor stages
    minor_stages = uniq_stages.find_all{|s| sc.priority(s) == MINOR}
    
    # make sure that exactly DOGS_TIME will be distributed to extended stages
    minor_fact = minor_stages.length > 1 ? 1 : 2
    # arterial optimization: there is always exactly 1 major priority stage
    major_fact = DOGS_TIME - minor_fact * minor_stages.length
  end
  
  cp.add_verb "CONST"
  # calculate stage lengths
  for stage in uniq_stages
    cp.add_verb "\tSTAGE#{stage}_TIME = #{stages.find_all{|s| s == stage}.length},"
  end
  if sc.has_bus_priority?
    cp.add_verb "\tBUSDETN = 1#{sc.bus_detector_n}," # arrival detector
    cp.add_verb "\tBUSDETS = 1#{sc.bus_detector_s}," # arrival detector
    cp.add_verb "\tBUSDETN_END = 2#{sc.bus_detector_n}," # departure detector
    cp.add_verb "\tBUSDETS_END = 2#{sc.bus_detector_s}," # departure detector
  end
  # unless there are cycle times per dogs level, use the transyt cycle times, which are
  # stored in the signal controller
  cp.add_verb "\tBASE_CYCLE_TIME = #{sc.cycle_time}" + (Hash === offset ? '' : ",\n\tOFFSET = #{offset}") + ";"
  cp.add_verb ''
  
  if USEDOGS    
    cp.add_verb 'DOGS_LEVEL := Marker_get(1);'
    cp.add_verb 'TIME := Marker_get(2);'
  end
  
  # calculate stage end times based on stage lengths, respecting dogs level and bus priorities
  for i in (0...uniq_stages.length)
    prev, cur = uniq_stages[i-1], uniq_stages[i]
    stage_end = "stage#{cur}_end := STAGE#{cur}_TIME"
    
    if USEDOGS
      curprio = sc.priority cur
      # assign priority to major and minor stages
      stage_end += " + #{curprio == MAJOR ? major_fact : minor_fact} * DOGS_LEVEL" if curprio != NONE
    end
    
    # account for the interstage length for all stage ends but the first stage
    stage_end += " + isl(#{prev},#{cur}) + stage#{prev}_end" if cur != uniq_stages.first   
    
    # insert bus priority for the first stage (=main direction), if the SC has it
    if sc.has_bus_priority?
      if sc.is_recipient? cur
        stage_end += " + #{BUS_TIME} * BUS_PRIORITY"
      elsif sc.is_donor? cur
        # the bus green extension is subtracted from the subsequent stage
        # in the compensation cycle, the extension is given to this stage
        stage_end += " - #{BUS_TIME} * BUS_PRIORITY"
      end
    end
    cp.add_verb stage_end + ';'
  end
  
  cp.add_verb ''
  
  if USEDOGS
    # dogs master sync and local timing calculations  
  
    if Hash === offset # map from dogs level to current offset
      offset.sort.each do |dogs_level,offset|
        cp << "IF DOGS_LEVEL = #{dogs_level} THEN"
        cp << "   OFFSET := #{offset};"
        cp.add 'END;'
      end
    end
    cp << 'IF NOT SYNC THEN'
    cp << '   IF (TIME - 1) = OFFSET THEN'
    cp << '      SYNC := 1;'
    cp << '      TRACE(ALL);' if ENABLE_VAP_TRACING[:slave]
    cp.add '   END;'
    cp.add '   GOTO PROG_ENDE'
    cp.add 'END;'
  else
    # local time required
    cp << 'TIME := OLDTIME + 1;'
    cp << 'OLDTIME := TIME;'
  end  
  
  cp << "C := BASE_CYCLE_TIME + #{DOGS_TIME} * DOGS_LEVEL;" if USEDOGS
  cp << "t_loc := (TIME - OFFSET) % #{USEDOGS ? 'C' : 'BASE_CYCLE_TIME'} + 1;"
  cp << 'SetT(t_loc);'
  
  if sc.has_bus_priority?
    
    # arrival detection
    cp << "IF Detection(BUSDETN) THEN"
    cp << "   BUS_FROM_NORTH := 1;"
    cp.add "END;"
    cp << "IF Detection(BUSDETS) THEN"
    cp << "   BUS_FROM_SOUTH := 1;"
    cp.add "END;"
    
    # departure detection
    cp << "IF Detection(BUSDETN_END) THEN"
    cp << "   BUS_FROM_NORTH := 0;"
    cp.add "END;"
    cp << "IF Detection(BUSDETS_END) THEN"
    cp << "   BUS_FROM_SOUTH := 0;"
    cp.add "END;"
    
    # Recipient is the stage for the main direction where buses come
    # To give priority we require that the bus arrives while in 
    # stage 1 and grant the stage extra time so that the bus may just squeeze across.
    # Only start priority if BUS_PRIORITY = 0 ie. we are not already prioritizing or compensating.
    
    # Any bus prioritization must be done within the main (arterial) stage
    cp << "IF stga(#{sc.recipient_stage}) THEN"
    # check for deactivation of bus priority because buses signalled they no longer need it
    cp << "   IF (BUS_PRIORITY = 1) AND (NOT BUS_FROM_NORTH) AND (NOT BUS_FROM_SOUTH) AND (T < (stage#{sc.recipient_stage}_end - #{BUS_TIME})) THEN"
    cp << '      BUS_PRIORITY := 0;'
    cp.add '   END;'
    
    # check if bus priority should be enabled
    cp << '   IF (BUS_FROM_NORTH OR BUS_FROM_SOUTH) AND (BUS_PRIORITY = 0) THEN'
    cp << '      BUS_PRIORITY := 1;'
    cp.add '   END;'
    cp.add 'END;'
  end
  
  # checks for interstage runs
  for i in (0...uniq_stages.length)
    cur, nxt = uniq_stages[i], uniq_stages[(i+1) % uniq_stages.length]
    # check that from-stage is running - may not be due to dogs level change!
    cp << "IF stga(#{cur}) THEN" 
    cp << "   IF T = stage#{cur}_end THEN"
    cp.add_verb "IS#{cur}_#{nxt}:      Is(#{cur},#{nxt});"
    if sc.has_bus_priority?
      if sc.is_donor? cur
        cp << '      IF BUS_PRIORITY = -1 THEN'
        cp << '      	BUS_PRIORITY := 0; /* two cycles of bus priority has finished and the donor received its compensation */'
        cp.add '      END;'  
      end
      if cur == uniq_stages.last
        cp << '      IF BUS_PRIORITY = 1 THEN'
        cp << '        BUS_PRIORITY := -1; /* subtract the extra bus time in next cycle */'
        cp.add '      END;'    
      end
    end
    cp.add '   END'
    cp.add "END"
  end
  
  if Project == 'dtu'
    # checks for missed interstage runs due to dogs level downshifts
    # note this will cause unexpected signal changes (red/amber -> red)
    # if the simulation resolution is 1 step per sim second or worse (less)
    for i in (1...uniq_stages.length)
      prev, cur =  uniq_stages[i-1], uniq_stages[i]
      cp << "#{i == 1 ? ';' : ''}IF stga(#{prev}) AND (T > (stage#{prev}_end + isl(#{prev},#{cur}))) AND ((T + #{MIN_STAGE_LENGTH}) < stage#{cur}_end) THEN"
      cp.add "  GOTO IS#{prev}_#{cur};"
      cp.add "END#{(i < uniq_stages.length-1) ? ';' : ''}"
    end
  end
  cp.add_verb 'PROG_ENDE:    .'
  
  cp.write File.join(outputdir, "#{name}.vap")
end

def gen_pua sc, outputdir
  cp = CodePrinter.new
  cp.add_verb '$SIGNAL_GROUPS'
  cp.add_verb '$'
  for grp in sc.groups.sort{|g1,g2| g1.number <=> g2.number}
    cp.add_verb "#{grp.name}\t#{grp.number}"
  end
  
  cp.add_verb ''  
  cp.add_verb '$STAGES'
  cp.add_verb '$'
  
  stages = sc.stages
  uniq_stages = stages.uniq.find_all{|s| s.instance_of? Stage}
  
  for stage in uniq_stages
    cp.add_verb "Stage_#{stage.number}\t#{stage.groups.map{|g|g.name}.join(' ')}"
    cp.add_verb "red\t#{(sc.groups - stage.groups).map{|g|g.name}.join(' ')}"
  end
  
  cp.add_verb ''  
  cp.add_verb '$STARTING_STAGE'
  cp.add_verb '$'
  cp.add_verb 'Stage_1'
  cp.add_verb ''  
  
  isnum = 0
  for t in (2..sc.cycle_time)
    next unless stages[t-1] != stages[t] and stages[t-1].instance_of?(Stage)
    isnum += 1
    cp.add_verb "$INTERSTAGE#{isnum}"
    
    # find the length of the interstage
    islen = 0
    fromstage = stages[t-1]
    if stages[t].instance_of?(Stage)
      # interstage happens from one cycle second to the next
      tostage = stages[t]
    else
      # this is an extended interstage
      islen += 1 while stages[t+islen] == stages[t]
      tostage = stages[t+islen+1]
    end
    
    cp.add_verb "Length [s]: #{islen}"
    cp.add_verb "From Stage: #{fromstage}"
    cp.add_verb "To Stage: #{tostage || uniq_stages.first}" # wrap around cycle
    cp.add_verb "$\tredend\tgrend"
    
    # capture all changes in this interstage
    for it in (0..islen)
      for grp in sc.groups
        # compare the colors of the previous and current heads
        tp = t + it
        case [grp.color(tp),grp.color(tp+1)]
        when [AMBER,AMBER]
          # this is the 2nd amber second, red ended 2 secs ago
          cp.add_verb "#{grp.name}\t#{it - 1}\t127"
        when [RED,GREEN]
          # direct change from red to green
          cp.add_verb "#{grp.name}\t#{it}\t127"
        when [GREEN,RED],[GREEN,YELLOW]
          # change from green to yellow or          
          # this light became red immediately
          cp.add_verb "#{grp.name}\t-127\t#{it}"
        end
      end
    end
    
    cp.add_verb ''  
  end  
  
  cp.add_verb '$END'
  
  cp.write File.join(outputdir, "#{sc.name.downcase.gsub(' ','_')}.pua")
end

if Project == 'dtu'
  # criteria for when DOGS can be enabled and disabled. measured against dn and ds

  # information on master controllers
  MasterInfo = [
    {
      :name => 'Herlev', 
      :dn => 3, :ds => 14, 
      :occ_dets => [3,14], :cnt_dets => [3,4,13,14],
      :cnt_bounds => {:upper => numbers(20,13,DOGS_LEVELS), :lower => numbers(17,11,DOGS_LEVELS)},
      :occ_bounds => {:upper => [11,29,45,58,70,80,92,96], :lower => [8,17,35,51,65,74,86,94]}
    }, {
      :name => 'Glostrup', 
      :dn => 14, :ds => 1, 
      :occ_dets => [1,2,5,8,9,10,11,12,13,14], :cnt_dets => [1,2,5,8,9,10,11,12,13,14],
      :cnt_bounds => {:upper => numbers(23,15,DOGS_LEVELS), :lower => numbers(19,14,DOGS_LEVELS)},
      :occ_bounds => {:upper => [20,41,53,62,78,84,90,96], :lower => [15,35,44,54,67,76,81,90]}
    }
  ]
end

def generate_controllers vissim, user_opts = {}, outputdir = Vissim_dir
  default_opts = {:verbose => true}
  opts = default_opts.merge(user_opts)
  
  offsets_per_cycle_time = Hash === opts[:offset]
  
  if Project == 'dtu'
    for master_opts in MasterInfo
      # if there are offsets per cycle time remain at least 3 cycles in each level
      # otherwise, allow level change after each cycle time has ended (original dogs)
      gen_master opts.merge(master_opts), offsets_per_cycle_time ? 4 : 2, outputdir
    end
  end

  busprior = if opts[:buspriority]
    # fetch the bus detectors attached to this intersection, if any
    DB["SELECT  CLNG(INSECTS.number) AS [number],
                CSTR([Detector North Suffix]) AS bus_detector_n, 
                CSTR([Detector South Suffix]) AS bus_detector_s,
                CLNG([Donor Stage]) as donor_stage, 
                CLNG([Recipient Stage]) as recipient_stage
         FROM [buspriority$] AS BUSP
         INNER JOIN [intersections$] As INSECTS ON INSECTS.Name = BUSP.Intersection"].all
  else; []; end
  
  for sc in vissim.controllers.find_all{|x| x.has_plans?}
    buspriorow = busprior.find{|r| r[:number] == sc.number}
    if opts[:buspriority] and buspriorow
      sc.update buspriorow.retain_keys!(:bus_detector_n,:bus_detector_s,:donor_stage,:recipient_stage)
      #      puts "#{sc}:"
      #      puts "   donor: #{sc.donor_stage}"
      #      puts "   recipient: #{sc.recipient_stage}"
    else
      sc.update :bus_detector_n => nil,:bus_detector_s => nil,:donor_stage => nil,:recipient_stage => nil
    end
    puts "Generating VAP and PUA for #{sc}" if opts[:verbose]
    gen_vap sc, outputdir, offsets_per_cycle_time ? opts[:offset][sc] : sc.offset # map from dogs level to offset or nil
    gen_pua sc, outputdir
  end
end

if __FILE__ == $0
  rows = [['Area','Detectors','Type', 'Bound','Thresholds']]
  typename = {:cnt => 'Counting',:occ => 'Occupancy'}
  MasterInfo.each do |master|
    [:cnt,:occ].each do |det_type|
      [:lower,:upper].each do |bound|
        rows << [
          master[:name],
          master["#{det_type}_dets".to_sym].join(' '),
          typename[det_type],
          bound.to_s.capitalize,
          master["#{det_type}_bounds".to_sym][bound].join(' ')
        ]
      end
    end
  end
  
  puts to_tex(rows,:label => 'tab:thvals', :caption => 'DOGS detectors and threshold values. Occupancy detector thresholds are in percent and counting thresholds in number of vehicles (per cycle).')
  
  #  vissim = Vissim.new
  #  generate_controllers(vissim,:buspriority => false,:dogs_enabled => true)
end