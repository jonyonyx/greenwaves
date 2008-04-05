# 
# To change this template, choose Tools | Templates
# and open the template in the editor.

Base_dir = "#{Dir.pwd.split('/')[0...-1].join("\\")}\\"
Data_dir = "#{Base_dir}data\\"
Herlev_dir = "#{Data_dir}DOGS Herlev 2007\\"
Glostrup_dir = "#{Data_dir}DOGS Glostrup 2007\\"
Vissim_dir = "#{Base_dir}Vissim\\o3_roskildevej-herlevsygehus\\"
Network_name = "tilpasset_model.inp"
Default_network = "#{Vissim_dir}#{Network_name}"

Time_fmt = '%H:%M:%S'
EU_date_fmt = '%d-%m-%Y'
Res = 15 # resolution in minutes of inputs
Minutes_per_hour = 60

RED,YELLOW,GREEN,AMBER = 'R','Y','G','A'

# DOGS priority levels
MINOR = 'Minor'
MAJOR = 'Major'
NONE = 'None'

# associated numbers with these vehicle types
Type_map = {'Cars' => 1001, 'Trucks' => 1002, 'Buses' => 1003}
Type_map_rev = {1001 => 'Cars', 1002 => 'Trucks'}
Cars_and_trucks = [1001, 1002]
Cars_and_trucks_str = ['Cars','Trucks']

EPS = 0.01
INPUT_FACTOR = 1.0 # factor used to adjust link inputs
ANNUAL_INCREASE = 1.015 # used in input generation for scaling
DOGS_LEVELS = 8
DOGS_LEVELDOWN_BUFFER = 0.1 # percentage of threshold value for current level
DOGS_TIME = 10 # number of seconds by which cycle time is increased for each dogs level
BUS_TIME = 10 # number of seconds to extend green time for bus stages
DOGS_LEVEL_GREEN = 10 # seconds green time associated with each dogs level change
BASE_CYCLE_TIME = 80 # seconds
CSPREFIX = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source="
DATAFILE = "#{Data_dir}data.xls" # main data file containing counts, sgp's, you name it
CS = "#{CSPREFIX}#{DATAFILE};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\";"
CSVCS = "#{CSPREFIX}#{Data_dir};Extended Properties=\"Text;HDR=YES;FTM=Delimited\";"
CSRESDB = "#{CSPREFIX}#{Vissim_dir}results.mdb;"
Accname = "acc_#{Res}m.csv"
ACCFILE = "#{Data_dir}#{Accname}"
ENABLE_VAP_TRACING = {:master => false, :slave => false} # write trace statements in vap code?

require 'dbi'
require 'fileutils'

module VissimOutput 
  def write
    section_contents = to_vissim # make sure this can be successfully generated
    FileUtils.cp Default_network, "#{ENV['TEMP']}\\#{Network_name}#{rand}" # backup
    inp = IO.readlines(Default_network)
    section_start = (0...inp.length).to_a.find{|i| inp[i] =~ section_header} + 1
    section_end = (section_start...inp.length).to_a.find{|i| inp[i] =~ /-- .+ --/ } - 1 
    File.open(Default_network, "w") do |file| 
      file << inp[0..section_start]
      file << "\n#{section_contents}\n"
      file << inp[section_end..-1]
    end
    puts "Wrote #{self.class} to '#{Default_network}'"
  end
end

def exec_query sql, conn_str = CS
  DBI.connect(conn_str) do |dbh|  
    return dbh.select_all(sql)
  end
end
class Array
  def sum ; inject{|a,x|x+a} ; end
  def mean ; sum.to_f/size ; end
  def median
    case size % 2
    when 0 then sort[size/2-1,2].mean
    when 1 then sort[size/2].to_f
    end if size > 0
  end
  # not quite correct version of quantile
  def quantile p
    i = (size*p).ceil - 1
    #puts i
    sort[i]
  end
  def squares ; inject{|a,x|x**2+a} ; end
  def variance ; squares.to_f/size - mean**2; end
  def deviation ; variance**(1/2) ; end
  def sample n=1 ; (0...n).collect{ self[rand(size)] } ; end
end