# 
# To change this template, choose Tools | Templates
# and open the template in the editor.

#Project = 'dtu'
Project = 'cowi'

if Project == 'dtu'
  Base_dir = "#{Dir.pwd.split('/')[0...-1].join("\\")}\\"
  Network_name = "tilpasset_model.inp"
  Vissim_dir = "#{Base_dir}Vissim\\o3_roskildevej-herlevsygehus\\"
  
  USEDOGS = true
  
  # associated numbers with these vehicle types
  Type_map = {'Cars' => 1001, 'Trucks' => 1002, 'Buses' => 1003}
elsif Project == 'cowi'
  Base_dir = "C:\\projects\\62832\\"
  Network_name = "amagermotorvejen_avedore-havnevej.inp"
  Vissim_dir = "#{Base_dir}network\\"
  
  USEDOGS = false
  
  # associated numbers with these vehicle types
  Type_map = {'Cars' => 5, 'Trucks' => 6, 'Buses' => 7}
end

Tempdir = ENV['TEMP'].gsub("\\",'/')
Data_dir = "#{Base_dir}data\\"
Herlev_dir = "#{Data_dir}DOGS Herlev 2007\\"
Glostrup_dir = "#{Data_dir}DOGS Glostrup 2007\\"
Default_network = "#{Vissim_dir}#{Network_name}"

Time_fmt = '%H:%M:%S'
EU_date_fmt = '%d-%m-%Y'
Res = 15 # resolution in minutes of inputs
Minutes_per_hour = 60
Seconds_per_minute = 60

RED,YELLOW,GREEN,AMBER = 'R','Y','G','A'

# DOGS priority levels
MINOR = 'Minor'
MAJOR = 'Major'
NONE = 'None'

# reverse the type map so that composition numbers point to the text description
# assume 1-to-1 mapping
Type_map_rev = []
Type_map.each{|k,v| Type_map_rev[v] = k}
  
# strings and composition numbers for cars and trucks (buses are handled separately
Cars_and_trucks_str = ['Cars','Trucks']
Cars_and_trucks = Type_map.map{|k,v| Cars_and_trucks_str.include?(k) ? v : nil} - [nil]

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

MIN_ROUTE_LENGTH = 5 # the minimum length of routes which are measured on for travel times

PERIOD_START, PERIOD_END = '07:00', '09:00' # used in input and route generation

require 'dbi'
require 'fileutils'

module VissimOutput 
  def write
    section_contents = to_vissim # make sure this can be successfully generated before opening the network file!
    network = Default_network
    networkname = network.split("\\").last
    FileUtils.cp network, "#{ENV['TEMP']}\\#{networkname}#{rand}" # backup
    inp = IO.readlines(network)
    section_start = (0...inp.length).to_a.find{|i| inp[i] =~ section_header} + 1
    section_end = (section_start...inp.length).to_a.find{|i| inp[i] =~ /-- .+ --/ } - 1 
    File.open(network, "w") do |file| 
      file << inp[0..section_start]
      file << "\n#{section_contents}\n"
      file << inp[section_end..-1]
    end
    puts "Wrote#{respond_to?(:length) ? " #{length}" : ''} #{self.class} to '#{network}'"
  end
end
def change_in_file(file, find, replace)
  text = File.read file
  File.open(file, 'w') do |f| 
    f << text.gsub(find, replace)
  end
end
def exec_query sql, conn_str = CS
  #puts conn_str
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
  def chunk(pieces)
    return [] if pieces.zero?
    piece_size = (length.to_f / pieces).ceil
    [first(piece_size), *last(length - piece_size).chunk(pieces - 1)]
  end
end

class ThreadSafeArray
  def initialize
    @mutex = Mutex.new
    @internalArray = []    
  end
  def method_missing method, *args, &block    
    @mutex.lock
    begin
      @internalArray.send method, *args, &block
    ensure
      @mutex.unlock
    end
  end
end

class Class
  def new!(*args, &block)
    # make sure we have arguments
    if args and args.size > 0      
      # if it's not a Hash, perform a normal "new"
      return new(*args, &block) unless Hash === args.last      

      init = args.pop
      
      # create the object and set its fields
      obj = new(*args, &block)
      init.each{|k, v| obj.instance_variable_set("@#{k}", v)}      
    else
      # no args, just do a normal "new" with any block passed
      obj = new(&block)
    end
    obj
  end
end

class Object  
  def update opts
    opts.each{|k,v| instance_variable_set("@#{k}",v)}
  end
end

