require 'csv'
require 'time'

#Data_dir,Namefilter = 'D:\greenwaves\data\DOGS Glostrup 2007','tael*.csv'
Data_dir,Namefilter = 'D:\greenwaves\data\DOGS Herlev 2007','taelling*.csv'

Res = 15 # resolution for aggr in minutes

EU_date_fmt = '%d-%m-%Y'
Time_fmt = '%H:%M:%S'

##
# returns a Time object given
# an tuple with the date (eu fmt) and time (24h) resp.
def parse_time eu_datetime_tuple

  Time.parse eu_datetime_tuple.join(' ')
end

def get_date time_obj
  time_obj.strftime EU_date_fmt
end

def get_time time_obj
  time_obj.strftime Time_fmt
end

def get_date_time time_obj
  time_obj.strftime "#{EU_date_fmt} #{Time_fmt}"
end

## 
# the csvfiles (taelling*.csv) contains detected vehicle counts
# from the last couple of minutes. 
# rows should be read sequentially and detections aggregated until
# Resolution seconds or more have passed
def create_aggr csvfile
	
  reader = CSV.open(csvfile,'r',';')
  header = reader.shift # skip past the header
	
  det_names = header[2..-1]
			
  # pre-loop initialization	
  row = reader.shift	
  prev_acc_time = parse_time(row[0..1])
  first_row_time = prev_acc_time - (prev_acc_time.sec + prev_acc_time.min*60)
	
  row = reader.shift
  num_det = row.length-2 # number of detectors
  acc = [0]*num_det # fill array with zeros
	
  offset = Res
  until row.empty?
		
    cutoff = first_row_time + offset * 60
		
    while not row.empty? and parse_time(row[0..1]) <= cutoff
      # accumulate detections
      row[2..-1].each_with_index do |d,i|
        acc[i] += d.to_i
      end
			
      row = reader.shift
    end
    
    # only return the entry, if something was accumulated
    if acc.any?{|d| d > 0}
      # create a mapping from detector names to detected count
      acc_detects = {}
      (0..num_det-1).each{|i| acc_detects[det_names[i]] = acc[i]}
      yield cutoff, acc_detects
    end
		
    # empty the accumulation buffer
    acc = [0]*num_det
    offset += Res
  end
	
  reader.close
end

puts "BEGIN"

Dir.chdir Data_dir

Time_det_map = Hash.new({})

for csvfile in Dir[Namefilter]
  puts "Creating #{Res}m aggregate for detections in '" + csvfile + "'..."
  prev_date = nil
  create_aggr(csvfile) do |time,detections|
    # extract the old hash and merge with the new set of detections
    # assume there are no detector name clashes
    Time_det_map[time] = Time_det_map[time].merge(detections)
    cur_date = get_date(time)
    unless cur_date == prev_date
      puts "#{csvfile}: #{cur_date}"
      prev_date = cur_date
    end
    
    #break if cur_date == '14-11-2007'
  end	
  puts "Completed processing of '" + csvfile + "'"
end

# Now put the combined results into a csv-file for processing in excel
CSV.open('aggr.csv','w',';') do |csv|
  # find the entry with the most detector names
  det_names = Time_det_map.values.max {|dets1, dets2| dets1.length <=> dets2.length}.keys
  
  # make a header
  csv << ['Date','Time'] + det_names
  for t in Time_det_map.keys.sort
    #puts "#{get_date_time(t)}: #{Time_det_map[t].inspect}"  
    map_t = Time_det_map[t]
    
    # skip entries, which do not have data for all detectors
    next if map_t.length < det_names.length
    
    csv << [get_date(t),get_time(t)] + det_names.collect{|d| map_t[d]}
  end
end

puts "END"
