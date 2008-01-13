require 'csv'
require 'fileutils'

#Data_dir = 'D:/greenwaves/data/DOGS Glostrup 2007'
Data_dir = 'D:\greenwaves\data\DOGS Herlev 2007'

def clean_n_conv csvfile
	puts "Cleaning '" + csvfile + "'..."
	tmpfile = csvfile + ".tmp"
	FileUtils.move csvfile, tmpfile
	contents = IO.read(tmpfile)
	
	newfile = File.new(csvfile.downcase,"w+")
	
	newfile.write contents.gsub(",",";").gsub(/OFF|END/,'')
	
	FileUtils.remove tmpfile
end

puts "begin"

Dir.chdir Data_dir
for csvfile in Dir['*.csv']
	clean_n_conv csvfile	
end

puts "end"