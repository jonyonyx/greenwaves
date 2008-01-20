require 'csv'
require 'fileutils'

Data_dir = 'D:/greenwaves/data/DOGS Glostrup 2007'
#Data_dir = 'D:\greenwaves\data\DOGS Herlev 2007'

def clean_n_conv csvfile
  puts "Cleaning '" + csvfile + "'..."
  tmpfile = csvfile + ".tmp"
  FileUtils.move csvfile, tmpfile
	
  CSV.open(csvfile.downcase,'w',';') do |csv|
    CSV.open(tmpfile,'r',';') do |row|
      date = row[0]
      if /(\d{2}[\/-]){2}\d{4}/.match date
      # an alternative format was used by tts in the glostrup files 
      # for dates - switch day and month
        date[0..1],date[3..4] = date[3..4],date[0..1]
        date.gsub! '/','-'
      end
      csv << [date] + row[1..-1]
    end	
  end
  FileUtils.remove tmpfile
end
puts "begin"

Dir.chdir Data_dir
for csvfile in Dir['tael7.csv']
  clean_n_conv csvfile	
end

puts "end"
  