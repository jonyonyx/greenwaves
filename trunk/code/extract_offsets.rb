
require 'const'

ISNUMS = DB["SELECT name,clng(number) as isnum FROM [intersections$] order by number"].all

rows = DB["SELECT intersection as name,clng(offset) as offset FROM [offsets$] WHERE program = 'P1'"]

def lookup_num isname
  ISNUMS.find{|isrow|isrow[:name] == isname}[:isnum]
end

def sort_by_num rows
  rows.sort_by{|r| lookup_num(r[:name])}
end

transyt_offsets = [['Area','\\#','Intersection','Offset']]
precalc_offsets = [['Area','\\#','Intersection',*(1..DOGS_MAX_LEVEL).to_a]]

sort_by_num(rows).each do |row|
  num = lookup_num(row[:name])
  case num
  when (1..5) then area = 'Herlev'
  when (9..12) then area = 'Glostrup'
  else
    next # skip others
  end
  area = num <= 5 ? 'Herlev' : 'Glostrup'
  transyt_offsets << [area,num,row[:name],row[:offset]]  
  
  offsets = (1..DOGS_MAX_LEVEL).map do |dogs_level|
    exec_query("SELECT clng(offset) FROM [offsets$] WHERE [signal controller] = '#{row[:name]}' AND [dogs level] = #{dogs_level}",RESULTS_FILE_CS)[0]
  end.flatten
  precalc_offsets << [area,num,row[:name],*offsets]
end


puts to_tex(transyt_offsets,:label => 'tab:offset_values',:caption => 'Morning program offset values from TRANSYT report \\cite{transyt}')
puts

rows = exec_query('SELECT area,[Signal Controller] as name, clng([dogs level]) as dogs_level, clng(offset) as offset FROM [offsets$] where [dogs level] > 0',RESULTS_FILE_CS)

#for row in precalc_offsets
#  puts row.inspect
#end

puts to_tex(precalc_offsets,:label => 'tab:offset_values_modified',:caption => 'Precalculated offset values for morning program in each DOGS level')