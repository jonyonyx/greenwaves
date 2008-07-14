require 'const'

queuecounter = {
  1 => 'S3H', #'N3H',
  2 => 'S3L', #'N3V',
  3 => 'V3H',
  4 => 'V3V',
  5 => 'N3V', #'S3V',
  6 => 'S2V', #'N2V',
  7 => 'E2',
  8 => 'N2'
}

traveltime = {
  1 => 'E-N',
  2 => 'E-S',
  3 => 'N-E',
  4 => 'N-V',
  5 => 'N-S',
  6 => 'S-V',
  7 => 'S-E',
  8 => 'S-N',
  9 => 'V-S',
  10 => 'V-N'
}

dataitemlookup = {
  :queue => queuecounter,
  :delay => traveltime
}

sqlfordata = {
  :queue => "SELECT TOP 95 percent
  n, max(queue) as queue
FROM (SELECT No__ as n, [max] as queue
      FROM QUEUE
      WHERE TIME BETWEEN PEAKSTART AND PEAKEND
      ORDER BY [max])
GROUP BY n",
  
  :delay => "SELECT
  No_ as n,
  avg(delay) as delay
FROM DELAY
WHERE TIME BETWEEN PEAKSTART AND PEAKEND
GROUP BY No_"
}

require 'cowi_tests'

peakstart = {
  MORNING => Time.parse('7:30'),
  DAY => Time.parse('12:00'),
  AFTERNOON => Time.parse('15:30')
}

to_extract = []
to_extract << :queue
#to_extract << :delay

for situation in [MORNING,DAY,AFTERNOON]
  itemdata = {}
  to_extract.each do |datatype|
    itemdata[datatype] = [['',*dataitemlookup[datatype].values.sort]]
  end
  
  for test in TESTQUEUE
    next unless test.programs.include?(situation)
    
    db = Sequel.dbi "#{CSPREFIX}#{File.join(test.get_output_dir(situation),'vissim.mdb')};"

    tstart = peakstart[situation] - situation.from
    tend = tstart + 3600.0
    
    to_extract.each do |datatype|
      row = [test.name]
      
      sql = sqlfordata[datatype].
        sub('PEAKSTART',tstart.to_s).
        sub('PEAKEND',tend.to_s)
    
      data = db[sql].all

      row.concat(data.sort_by{|r|dataitemlookup[datatype][r[:n]]}.map{|r|r[datatype].round})
    
      itemdata[datatype] << row
    end
  end

  to_extract.each do |datatype|
    puts "#{datatype.to_s.capitalize} - #{situation}"
    transposeddata = itemdata[datatype].transpose

    for row in transposeddata
      puts row.inspect
    end
  
    #to_xls(transposeddata,"#{datatype}_#{situation.name.downcase}",File.join(Base_dir,'results','results.xls'))
  end
  
end
