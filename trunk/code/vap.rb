require 'vissim'
require 'dogs_threshold'

class CodePrinter
  def initialize 
    @fmt_num = "S%03d: %s"
    @fmt_nonum = "#{' '*6}%s"
    @line_number = 0
    @lines = []
  end
  def add line, print_line_number = true
    @lines << if print_line_number
      @line_number += 1 
      format(@fmt_num,@line_number,line)
    else
      format(@fmt_nonum,line)
    end
  end
  # adds a line verbatim
  def add_verb line
    @lines << line
  end
  def to_s
    @lines.join("\n")
  end
  def write filepath
    File.open(filepath, 'w') { |f|  f << to_s}
  end
end
def get_generated_info
  "/* This program was automatically generated by #{$0.split("/").last} on #{Time.now.strftime(EU_date_fmt)} */"
end
def gen_master opts, outputdir

  cp = CodePrinter.new
  
  cp.add_verb get_generated_info
    
  cp.add_verb "PROGRAM DOGS_MASTER ; /* #{opts[:area]} */"
  cp.add_verb "CONST 
        BASE_CYCLE_TIME = #{BASE_CYCLE_TIME},
        DN = #{opts[:dn]},
        DS = #{opts[:ds]},
        SMOOTHING_FACTOR = 0.5,
        DOGS_LEVEL_GREEN = #{DOGS_LEVEL_GREEN},
        ENABLE_CNT = 32,
        DISABLE_CNT = 13,
        ENABLE_OCC = 45,
        DISABLE_OCC = 13,
        DOGS_FORCE_DISABLE = #{opts[:dogs_enabled] ? 0 : 1};
  "

  # Count (intensity) bounds are estimated for a counting period of BASE_CYCLE_TIME seconds
  # Occupied rate- (percentages) and count-bounds are taken from the DOGS material
  # and are identical for both areas on O3
  cnt_bounds = {'UPPER' => [14, 23, 32, 41, 50, 60, 69, 78], 'LOWER' => [13, 21, 29, 37, 45, 53, 61, 69]}
  occ_bounds = {'UPPER' => [11, 29, 45, 58, 70, 80, 92, 96], 'LOWER' => [8, 17, 35, 51, 65, 74, 86, 94]}
  
  cp.add_verb "/* Expressions */
    cycle_sec := T;
    cycle_sec_plus1 := cycle_sec + 1;
    CURRENT_CYCLE_TIME := BASE_CYCLE_TIME + DOGS_LEVEL_GREEN * DOGS_LEVEL;
  "
  
  cp.add "IF NOT cycle_sec THEN /* Perform initialization */"
  cp.add "  DN_CNT := 0; DS_CNT := 0; /* Keeps Vissim from nagging */"
  cp.add "  SetT(1); /* Start the clock */"
  cp.add "  TRACE(ALL); /* Enable tracing */" if ENABLE_VAP_TRACING[:master]
  cp.add "  GOTO PROG_ENDE", false
  cp.add "END;", false
  
  cp.add "Marker_put(1,DOGS_LEVEL); Marker_put(2,cycle_sec);"
  cp.add "IF cycle_sec < CURRENT_CYCLE_TIME THEN"
  cp.add "  SetT(cycle_sec_plus1);"
  cp.add "  GOTO PROG_ENDE;", false
  cp.add "END;", false
  
  # Below here we actually reached cycle_sec = current cycle time
  cp.add_verb "/* When DOGS_LEVEL > 0 the counting period is extended along with the green time 
                  and the counts from the detections must be corrected before comparing to the cnt threshold values */"
  cp.add "DOGS_CORRECTION_FACTOR := BASE_CYCLE_TIME / CURRENT_CYCLE_TIME;"
  cp.add "DN_CNT := DOGS_CORRECTION_FACTOR * (DN_CNT + SMOOTHING_FACTOR * (Rear_ends(DN) - DN_CNT)); "
  cp.add "DS_CNT := DOGS_CORRECTION_FACTOR * (DS_CNT + SMOOTHING_FACTOR * (Rear_ends(DS) - DS_CNT));"    
  cp.add "DN_OCC := Occup_rate(DN) * 100; /* Occupied rate percentage */"    
  cp.add "DS_OCC := Occup_rate(DS) * 100;"
  cp.add_verb "/* Measuring on detectors, which are used to determine current dogs level */"
  for occ_det in opts[:occ_dets]
    cp.add "D#{occ_det}_OCC := Occup_rate(#{occ_det}) * 100;"
  end
  # counting detectors needs to be cleared
  for cnt_det in opts[:cnt_dets]
    cp.add "D#{cnt_det}_CNT := Rear_ends(#{cnt_det});"
    cp.add "Clear_rear_ends(#{cnt_det});"
  end
  unless opts[:cnt_dets].include? opts[:dn]
    cp.add "Clear_rear_ends(DN);"
  end
  unless opts[:cnt_dets].include? opts[:ds]
    cp.add "Clear_rear_ends(DS);"
  end
  cp.add_verb "/* Enable dogs if north or south bounds are reached. If dogs is enabled but we are below enable-bounds, keep dogs enabled until the lower threshold is reached */"
  cp.add "DOGS_ENABLED := ((DN_CNT > ENABLE_CNT) OR (DS_CNT > ENABLE_CNT) AND (DN_OCC > ENABLE_OCC) OR (DS_OCC > ENABLE_OCC)) OR DOGS_ENABLED AND ((DN_CNT > DISABLE_CNT) OR (DS_CNT > DISABLE_CNT) AND (DN_OCC > DISABLE_OCC) OR (DS_OCC > DISABLE_OCC));"
  cp.add "IF DOGS_FORCE_DISABLE OR NOT DOGS_ENABLED THEN"
  cp.add "   DOGS_LEVEL := 0;"
  cp.add "ELSE", false 
  for level in (0...DOGS_LEVELS)
    cp.add "  IF DOGS_LEVEL = #{level} THEN"
    cp.add "     IF #{opts[:occ_dets].map{|det| "(D#{det}_OCC > #{occ_bounds['UPPER'][level]})"}.join(' OR ')} OR #{opts[:cnt_dets].map{|det| "(D#{det}_CNT > #{cnt_bounds['UPPER'][level]})"}.join(' OR ')} THEN"
    cp.add "         DOGS_LEVEL := #{level+1};"
    cp.add "     END;", false
    if level > 0
      cp.add "     IF #{opts[:occ_dets].map{|det| "(D#{det}_OCC < #{occ_bounds['LOWER'][level]})"}.join(' AND ')} AND #{opts[:cnt_dets].map{|det| "(D#{det}_CNT < #{cnt_bounds['LOWER'][level]})"}.join(' AND ')} THEN"
      cp.add "         DOGS_LEVEL := #{level-1};"
      cp.add "     END;", false
    end
    cp.add "  GOTO FINAL_STATEMENTS;", false
    cp.add "  END;", false
  end
  cp.add "END;", false
  cp.add_verb "FINAL_STATEMENTS:   SetT(1)"
  cp.add_verb 'PROG_ENDE:    .'

  cp.write File.join(outputdir, "DOGS_MASTER_#{opts[:name].upcase}.vap")
end

Replacement = {221 => 'ae', 248 => 'oe', 206 => 'aa'} # be sure to use character codes for non-ascii chars
  
# Below is code for generating a DOGS SLAVE controller in VAP
def gen_vap sc, outputdir
  cp = CodePrinter.new
  
  cp.add_verb get_generated_info  
  
  name = sc.name.downcase.gsub(' ','_')
  cp.add_verb "PROGRAM #{name.gsub(/[^a-z]/){ |match| Replacement[match.to_s[0]]}}; /* #{sc.program} */"
  cp.add_verb ''
  
  stages = sc.stages
  uniq_stages = stages.uniq.find_all{|s| s.instance_of? Stage}
  # prepare the split of DOGS extra time between major and minor stages
  minor_stages = uniq_stages.find_all{|s| sc.priority(s) == MINOR}
    
  # make sure that exactly DOGS_TIME will be distributed to extended stages
  minor_fact = minor_stages.length > 1 ? 1 : 2
  # arterial optimization: there is always exactly 1 major priority stage
  major_fact = DOGS_TIME - minor_fact * minor_stages.length
    
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
  cp.add_verb "\tBASE_CYCLE_TIME = #{sc.cycle_time},\n\tOFFSET = #{sc.offset};"
  cp.add_verb ''
  # calculate stage end times based on stage lengths, respecting dogs level and bus priorities
  for i in (0...uniq_stages.length)
    prev, cur = uniq_stages[i-1], uniq_stages[i]
    curprio = sc.priority cur
    stage_end = "stage#{cur}_end := STAGE#{cur}_TIME"
    
    if USEDOGS
      # assign priority to major and minor stages
      stage_end += " + #{curprio == MAJOR ? major_fact : minor_fact} * DOGS_LEVEL" if curprio != NONE
    end
    
    # account for the interstage length for all stage ends but the first stage
    stage_end += " + Interstage_length(#{prev},#{cur}) + stage#{prev}_end" if cur != uniq_stages.first   
    
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
    cp.add 'DOGS_LEVEL := Marker_get(1); TIME := Marker_get(2);'
    cp.add 'IF NOT SYNC THEN'
    cp.add '   IF TIME = (OFFSET - 1) THEN'
    cp.add '      SYNC := 1;'
    cp.add '      TRACE(ALL);' if ENABLE_VAP_TRACING[:slave]
    cp.add '   END;', false
    cp.add '   GOTO PROG_ENDE', false
    cp.add 'END;', false
    #  cp.add "IF TIME >= OFFSET THEN /* Poor man's modulos (VAP version 4) */"
    #  cp.add '   t_loc := TIME - OFFSET + 1'
    #  cp.add 'ELSE', false
    #  cp.add '   t_loc := TIME - OFFSET + C + 1'
    #  cp.add 'END;', false
  else
    # local time required
    cp.add 'TIME := OLDTIME + 1;'
    cp.add 'OLDTIME := TIME;'
  end  
  
  cp.add "C := BASE_CYCLE_TIME + #{DOGS_TIME} * DOGS_LEVEL;" if USEDOGS
  cp.add "t_loc := (TIME + OFFSET) % #{USEDOGS ? 'C' : 'BASE_CYCLE_TIME'} + 1;"
  cp.add 'SetT(t_loc);'
  
  if sc.has_bus_priority?
    
    # arrival detection
    cp.add "IF Detection(BUSDETN) THEN"
    cp.add "   BUS_FROM_NORTH := 1;"
    cp.add "END;", false
    cp.add "IF Detection(BUSDETS) THEN"
    cp.add "   BUS_FROM_SOUTH := 1;"
    cp.add "END;", false
    
    # departure detection
    cp.add "IF Detection(BUSDETN_END) THEN"
    cp.add "   BUS_FROM_NORTH := 0;"
    cp.add "END;", false
    cp.add "IF Detection(BUSDETS_END) THEN"
    cp.add "   BUS_FROM_SOUTH := 0;"
    cp.add "END;", false
    
    # Recipient is the stage for the main direction where buses come
    # To give priority we require that the bus arrives while in 
    # stage 1 and grant the stage extra time so that the bus may just squeeze across.
    # Only start priority if BUS_PRIORITY = 0 ie. we are not already prioritizing or compensating.
    
    # Any bus prioritization must be done within the main (arterial) stage
    cp.add "IF Stage_active(#{sc.recipient_stage}) THEN"
    # check for deactivation of bus priority because buses signalled they no longer need it
    cp.add "   IF BUS_PRIORITY = 1 AND (BUS_FROM_NORTH = 0) AND (BUS_FROM_SOUTH = 0) AND (T < (stage#{sc.recipient_stage}_end - #{BUS_TIME})) THEN"
    cp.add '      BUS_PRIORITY := 0;'
    cp.add '   END;', false
    
    # check if bus priority should be enabled
    cp.add '   IF (BUS_FROM_NORTH OR BUS_FROM_SOUTH) AND (BUS_PRIORITY = 0) THEN'
    cp.add '      BUS_PRIORITY := 1;'
    cp.add '   END;', false
    cp.add 'END;', false
  end
  
  # checks for interstage runs
  for i in (0...uniq_stages.length)
    cur, nxt = uniq_stages[i], uniq_stages[(i+1) % uniq_stages.length]
    # check that from-stage is running - may not be due to dogs level change!
    cp.add "IF Stage_active(#{cur}) THEN" 
    cp.add "   IF T = stage#{cur}_end THEN"
    cp.add_verb "IS#{cur}_#{nxt}:      Is(#{cur},#{nxt});"
    if sc.has_bus_priority?
      if sc.is_donor? cur
        cp.add '      IF BUS_PRIORITY = -1 THEN'
        cp.add '      	BUS_PRIORITY := 0; /* two cycles of bus priority has finished and the donor received its compensation */'
        cp.add '      END;', false  
      end
      if cur == uniq_stages.last
        cp.add '      IF BUS_PRIORITY = 1 THEN'
        cp.add '        BUS_PRIORITY := -1; /* subtract the extra bus time in next cycle */'
        cp.add '      END;', false    
      end
    end
    cp.add '   END', false
    cp.add 'END;', false
  end
  # checks for missed interstage runs due to dogs level downshifts
  for i in (1...uniq_stages.length)
    prev, cur =  uniq_stages[i-1], uniq_stages[i]
    cp.add "IF (T > stage#{prev}_end) AND Stage_active(#{prev}) AND (T < stage#{cur}_end) THEN"
    cp.add "  GOTO IS#{prev}_#{cur};", false
    cp.add "END#{(i < uniq_stages.length-1) ? ';' : ''}", false
  end
  cp.add_verb 'PROG_ENDE:    .'
  
  cp.write File.join(outputdir, "#{name}.vap")
end

def gen_pua sc, outputdir
  cp = CodePrinter.new
  cp.add_verb '$SIGNAL_GROUPS'
  cp.add_verb '$'
  for grp in sc.groups.values.sort{|g1,g2| g1.number <=> g2.number}
    cp.add_verb "#{grp.name}\t#{grp.number}"
  end
  
  cp.add_verb ''  
  cp.add_verb '$STAGES'
  cp.add_verb '$'
  
  stages = sc.stages
  uniq_stages = stages.uniq.find_all{|s| s.instance_of? Stage}
  
  for stage in uniq_stages
    cp.add_verb "Stage_#{stage.number}\t#{stage.groups.map{|g|g.name}.join(' ')}"
    cp.add_verb "red\t#{(sc.groups.values - stage.groups).map{|g|g.name}.join(' ')}"
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
    cp.add_verb "To Stage: #{tostage ? tostage : uniq_stages.first}" # wrap around cycle
    cp.add_verb "$\tredend\tgrend"
    
    # capture all changes in this interstage
    for it in (0..islen)
      for grp in sc.groups.values
        # compare the colors of the previous and
        # current heads        
        
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

# information on master controllers
MasterInfo = [
  {:name => 'Herlev', :dn => 3, :ds => 14, :occ_dets => [3,14], :cnt_dets => [3,4,13,14]},  
  {:name => 'Glostrup', :dn => 14, :ds => 1, :occ_dets => [1,2,5,8,9,10,11,12,13,14], :cnt_dets => [1,2,5,8,9,10,11,12,13,14]}
]

def generate_controllers vissim, attributes, outputdir
  for opts in MasterInfo
    gen_master opts.merge(attributes), outputdir
  end

  if attributes[:buspriority]
    # fetch the bus detectors attached to this intersection, if any
    busprior = exec_query("SELECT INSECTS.Number,
                        [Detector North Suffix], [Detector South Suffix],
                        [Donor Stage], [Recipient Stage]
                       FROM [buspriority$]
                       INNER JOIN [intersections$] As INSECTS ON INSECTS.Name = Intersection")
    
  end
  
  for sc in vissim.sc_map.values.find_all{|x| x.has_plans?}
    buspriorow = busprior.find{|r| r['Number'] == sc.number}
    if attributes[:buspriority] and buspriorow
      sc.update :buspriority => 
        {'DETN' => busprior[0], 'DETS' => busprior[1], 'DONOR' => busprior[2].to_i, 'RCPT' => busprior[3].to_i}
    else
      sc.update :buspriority => {}        
    end
    gen_vap sc, outputdir
    gen_pua sc, outputdir
  end
end

if __FILE__ == $0
  generate_controllers 
end