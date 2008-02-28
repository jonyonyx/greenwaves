require 'const'
require 'dbi'

Plans_file = "../data/planer/signalplans.xls"
CS = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source=#{Plans_file};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\";"

DBI.connect(CS) do |dbh|  
  P_rows = dbh.select_all "SELECT 
        Intersection, PROGRAM,
        Groupname As NAME, 
        [DOGS Priority] As PRIORITY,
        80 As CYCLE_TIME,
        OFFSET,
        [Red End] As RED_END, 
        [Green End] As GREEN_END, 
        [Red-Amber] As TRED_AMBER, 
        Amber As TAMBER
       FROM [Data$]"
end

scs = []

sc = nil
grpnum = 1
for row in P_rows
  isname = row['Intersection']
  isnum = row['Number']
  prog = row['PROGRAM']
  if not sc or not sc.name == isname or not sc.program == prog
    sc = SignalController.new(isnum, 
      'NAME' => isname, 
      'PROGRAM' => prog,
      'CYCLE_TIME' => row['CYCLE_TIME'],
      'OFFSET' => row['OFFSET'])
    scs << sc
  end
  
  sc.add SignalGroup.new(grpnum,row)
  grpnum += 1
end
class CodePrinter
  def initialize 
    @fmt_num = "S%03d:\t%s"
    @fmt_nonum = "\t%s"
    @line_number = 0
  end
  def print line, print_line_number = true
    if print_line_number
      @line_number += 1 
      format @fmt_num,@line_number,line
    else
      format @fmt_nonum,line
    end
  end
end
def gen_vap sc  
  puts "PROGRAM #{sc.name.downcase};"
  puts
  puts "CONST"
  
  stages = sc.stages
  uniq_stages = stages.uniq.find_all{|s| s.is?(Stage)}
  # prepare the split of DOGS extra time between major and minor stages
  minor_stages = uniq_stages.find_all{|s| s.priority == MINOR}
  major_stages = uniq_stages.find_all{|s| s.priority == MAJOR}
  
  minor_fact = 2 * minor_stages.length
  major_fact = 10 - minor_fact
  
  for stage in uniq_stages
    puts "   STAGE#{stage}_TIME = #{stages.find_all{|s| s == stage}.length},"
  end
  puts "   BASE_CYCLE_TIME = #{sc.cycle_time},"
  puts "   OFFSET = #{sc.offset};"
  puts
  for i in (0...uniq_stages.length)
    prev, cur = uniq_stages[i-1], uniq_stages[i]
    puts "   stage#{cur}_end := STAGE#{cur}_TIME" + 
      (cur.priority == NONE ? '' : " + #{cur.priority == MAJOR ? major_fact : minor_fact} * DOGS_LEVEL") +
      (cur == uniq_stages.first ? ';' : " + Interstage_length(#{prev},#{cur}) + stage#{prev}_end;")
  end
  cp = CodePrinter.new
  puts
  puts cp.print('DOGS_LEVEL := Marker_get(1); TIME := Marker_get(2);'),
    cp.print('IF NOT SYNC THEN'),
    cp.print('   IF TIME = (OFFSET - 1) THEN'),
    cp.print('      SYNC := 1; TRACE(ALL)'),
    cp.print('   END;', false),
    cp.print('   GOTO PROG_ENDE', false),
    cp.print('END;', false),
    cp.print('C := BASE_CYCLE_TIME + 10 * DOGS_LEVEL;'),
    cp.print('IF TIME >= OFFSET THEN'),
    cp.print('   t_loc := TIME - OFFSET + 1'),
    cp.print('ELSE',false),
    cp.print('   t_loc := TIME - OFFSET + C + 1'),
    cp.print('END;',false),
    cp.print('SetT(t_loc);')
  
  for i in (0...uniq_stages.length)
    cur, nxt = uniq_stages[i], uniq_stages[(i+1) % uniq_stages.length]
    puts cp.print("IF T = stage#{cur}_end THEN"),
      cp.print("   Is(#{cur},#{nxt})"),
      cp.print('END;',false)
  end
  puts 'PROG_ENDE:    .'
end

for sc in scs
  gen_vap sc
#  for stage in sc.stages.find_all{|s| s.is?(Stage)}
#    puts "#{stage}: #{stage.groups.join(', ')} => #{stage.priority}"
#  end
end