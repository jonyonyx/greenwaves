require 'fastercsv'

#Data_dir = 'D:\greenwaves\data\DOGS Glostrup 2007'
Data_dir = 'D:\greenwaves\data\DOGS Herlev 2007'

Res = 15 # resolution for aggr in minutes

EU_date_fmt = '%d-%m-%Y'

##
# returns a Time object given
# an tuple with the date (eu fmt) and time (24h) resp.
def get_time eu_datetime_tuple
	Time.parse eu_datetime_tuple.join(' ')
end

def get_date time_obj
	time_obj.strftime EU_date_fmt
end

## 
# the csvfiles (taelling*.csv) contains detected vehicle counts
# from the last couple of minutes. 
# rows should be read sequentially and detections aggregated until
# Resolution seconds or more have passed
def create_aggr csvfile
	puts "Creating #{Res}s aggregate for detections in '" + csvfile + "'..."
	
	reader = FasterCSV.open(csvfile,'r',:col_sep=>';')
	header = reader.shift # skip past the header
			
	# pre-loop initialization	
	row = reader.shift	
	prev_acc_time = get_time(row[0..1])
	first_row_time = prev_acc_time - (prev_acc_time.sec + prev_acc_time.min*60)
	
	current_date = get_date(prev_acc_time)
	row = reader.shift
	row_num = 1
	num_det = row.length-2 # number of detectors
	acc = [0]*num_det # fill array with zeros
	
	FasterCSV.open("aggr_#{Res}min_#{csvfile}",'w',:col_sep=>';') do |csv|	
		csv << ['Date','Time','Day of Week'] + header[2..-1]
		offset = Res
		do_continue = true
		while row
			cutoff = first_row_time + offset * 60
			
			while row and get_time(row[0..1]) <= cutoff
				# accumulate detections
				row[2..-1].each_with_index do |d,i|
					acc[i] += d.to_i
				end
				
				row = reader.shift
				row_num += 1
			end
			
			# empty the acc buffer
			puts "accumulating at row #{row_num}"
			csv << [cutoff.strftime(EU_date_fmt),
					cutoff.strftime('%H:%M'),
					cutoff.strftime('%a')] + acc
			acc = [0]*num_det
			offset += Res
		end
	end
	
	reader.close
	puts "Completed processing of '" + csvfile + "'"
end

Dir.chdir Data_dir
for csvfile in Dir['taelling1.csv']
	create_aggr csvfile	
end

puts "end"
