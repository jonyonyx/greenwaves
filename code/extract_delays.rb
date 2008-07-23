require 'const'

queuecounter = {
  1 => 'S3H',
  2 => 'S3L',
  3 => 'V3H',
  4 => 'V3V',
  5 => 'N3V', 
  6 => 'S2V',
  7 => 'Ø2',
  8 => 'N2',
  9 => 'S2L',
  10 => 'N3L',
  11 => 'S1',
  12 => 'S1V'
}

traveltime = {
  1 => "Ø-N",
  2 => "Ø-S",
  3 => "N-Ø",
  4 => 'N-V',
  5 => 'N-S',
  6 => 'S-V',
  7 => "S-Ø",
  8 => 'S-N',
  9 => 'V-S',
  10 => 'V-N',
  11 => 'Ø-N2',
  12 => 'S-N2',
  13 => 'V-N2'
}

dataitemlookup = {
  :queue => queuecounter,
  :delay => traveltime,
  :delaytot => {1 => 'Samlet forsinkelse'},
  :maxdelay => {1 => 'Maks. forsinkelse'}
}

percentile = 90

sqlfordata = {
  :queue => "SELECT max(maxqueue) AS queue, n
FROM (SELECT TOP #{percentile} PERCENT [max] as maxqueue, No__ as n FROM QUEUE
      WHERE TIME BETWEEN PEAKSTART AND PEAKEND
      AND No__ = NUMBER
      ORDER BY [max])
GROUP BY n",
  
  :delay => "SELECT
  avg(delay) as delay, n
FROM (SELECT TOP #{percentile} PERCENT delay, No_ as n FROM DELAY
      WHERE TIME BETWEEN PEAKSTART AND PEAKEND
      AND No_ = NUMBER
      ORDER BY delay)
GROUP BY n",

  :delaytot => "SELECT SUM(veh * delay) / SUM(veh) as delaytot
      FROM DELAY
      WHERE TIME BETWEEN PEAKSTART AND PEAKEND
",

  :maxdelay => "SELECT MAX(delay) as maxdelay
      FROM DELAY
      WHERE TIME BETWEEN PEAKSTART AND PEAKEND
"
}

require 'cowi_tests'

peakstart = {
  MORNING => Time.parse('7:30'),
  DAY => Time.parse('12:00'),
  AFTERNOON => Time.parse('15:30')
}

if __FILE__ == $0

  to_extract = []
#  to_extract << :queue
#  to_extract << :delay
#  to_extract << :delaytot
  to_extract << :maxdelay

  situations = []
  situations << MORNING
#  situations << DAY
#  situations << AFTERNOON

  for situation in situations
    itemdata = {}
    to_extract.each do |datatype|
      itemdata[datatype] = [['',*dataitemlookup[datatype].values.sort]]
    end
  
    for test in TESTQUEUE
      next unless test.programs.include?(situation)
    
      db = Sequel.dbi "#{CSPREFIX}#{File.join(test.get_output_dir(situation),'vissim.mdb')};"

      tstart = peakstart[situation] - situation.from + (situation.repeat_first_interval ? situation.resolution_in_seconds : 0)
      tend = tstart + 3600.0 # tstart and tend defines the peak hour in seconds
    
      to_extract.each do |datatype|
        row = [test.name]
      
        sql = sqlfordata[datatype].
          sub('PEAKSTART',tstart.to_s).
          sub('PEAKEND',tend.to_s)
    
        data = [] # contains rows (hash'es)
      
        number2names = dataitemlookup[datatype]
      
        number2names.keys.each do |number|
          numbersql = sql.sub('NUMBER',number.to_s)
          data << db[numbersql].all.first # expect only one
        end
      
        row.concat(data.sort_by{|r|number2names[r[:n]]}.map{|r|r[datatype].round})
    
        itemdata[datatype] << row
      end
    end

    to_extract.each do |datatype|
      transposeddata = itemdata[datatype].transpose

      puts "#{datatype.to_s.capitalize} - #{situation}"

      for row in transposeddata
        puts row.inspect
      end

      #to_xls(transposeddata,"#{datatype}_#{situation.name.downcase}",File.join(Base_dir,'results','results.xls'))
    
    end
  
  end
end
