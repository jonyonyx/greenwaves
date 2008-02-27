require 'const'
require 'dbi'

Plans_file = "../data/planer/signalplans.xls"
CS = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source=#{Plans_file};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\";"

DBI.connect(CS) do |dbh|  
  P_rows = dbh.select_all "SELECT 
        Intersection, PROGRAM,
        Groupname As NAME, 
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
def gen_vap sc  
  puts "PROGRAM #{sc.name.downcase};"
  puts
  puts "CONST"
  # calculate stage lengths
  groups = sc.sorted_groups
  
  for stage in sc.stages
    puts "   STAGE#{stage.number}_TIME = #{stage.time},"
  end
  puts "   BASE_CYCLE_TIME = #{sc.cycle_time},"
  puts "   OFFSET = #{sc.offset};"
  puts
  puts
end

sc = scs[0]
puts (1..sc.cycle_time).to_a.map{|t|sc.interstage_active?(t) ? 1 : 0}.join(' ')


