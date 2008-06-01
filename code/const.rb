# 
# To change this template, choose Tools | Templates
# and open the template in the editor.

require 'rubygems'
require 'sequel'
Project = 'dtu'
#Project = 'cowi'

CSPREFIX = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source="
if Project == 'dtu'
  Base_dir = "#{Dir.pwd.split('/')[0...-1].join("\\")}\\"
  Network_name = "tilpasset_model.inp"
  Vissim_dir = "#{Base_dir}Vissim\\o3_roskildevej-herlevsygehus\\"
  DOGSAGGRFILE = "#{Base_dir}data\\aggr.xls"
  DOGSAGGRCS = "#{CSPREFIX}#{DOGSAGGRFILE};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\""
  DOGSDB = Sequel.dbi DOGSAGGRCS
  
  PROGRAM = 'P1'
  
  USEDOGS = true
  
  # definition of extreme ends of artery
  ARTERY = {
    :sc1 => {:from_direction => 'N', :scno => 1}, 
    :sc2 => {:from_direction => 'S', :scno => 12}
  }
  
  ARTERY_DIRECTIONS = ARTERY.map{|sc,info|info[:from_direction]}
   
  # DOGS priority levels
  MINOR = 'Minor'
  MAJOR = 'Major'
  NONE = 'None'
  DOGS_LEVELS = 8
  DOGS_LEVEL_GREEN = 10 # seconds green time associated with each dogs level change
  DOGS_LEVELDOWN_BUFFER = 0.1 # percentage of threshold value for current level
  DOGS_TIME = 10 # number of seconds by which cycle time is increased for each dogs level
  BUS_TIME = 10 # number of seconds to extend green time for bus stages
  MIN_STAGE_LENGTH = 6 # used when DOGS changes level and a stage jump maybe be considered
  DOGS_CNT_BOUNDS_FACTOR = 0.8 # adjust the aggresiveness of DOGS. Lower => more aggressive to increase cycle times.
  DOGS_OCC_BOUNDS_FACTOR = 0.8
  # associated numbers with these vehicle types
  Type_map = {'Cars' => 1001, 'Trucks' => 1002, 'Buses' => 1003}
elsif Project == 'cowi'
  Base_dir = "C:\\projects\\62832\\"
  Network_name = "amagermotorvejen_avedore-havnevej.inp"
  Vissim_dir = "#{Base_dir}network\\"
  
  PROGRAM = 'M80'
  
  USEDOGS = false
  
  # associated numbers with these vehicle types
  Type_map = {'Cars' => 10, 'Trucks' => 20}
end

Tempdir = ENV['TEMP'].gsub("\\",'/')
Data_dir = "#{Base_dir}data\\"
Default_network = "#{Vissim_dir}#{Network_name}"
  
Herlev_dir = "#{Data_dir}DOGS Herlev 2007\\"
Glostrup_dir = "#{Data_dir}DOGS Glostrup 2007\\"
  
Time_fmt = '%H:%M:%S'
EU_date_fmt = '%d-%m-%Y'
Res = 15 # resolution in minutes of inputs
MINUTES_PER_HOUR = 60
Seconds_per_minute = 60

RED,YELLOW,GREEN,AMBER = 'R','Y','G','A'

# reverse the type map so that composition numbers point to the text description
# assume 1-to-1 mapping
Type_map_rev = []
Type_map.each{|k,v| Type_map_rev[v] = k}

# strings and composition numbers for cars and trucks (buses are handled separately
Cars_and_trucks_str = ['Cars','Trucks']
Cars_and_trucks = Type_map.map{|k,v| Cars_and_trucks_str.include?(k) ? v : nil} - [nil]

EPS = 0.01
INPUT_FACTOR = 1.0 # factor used to adjust link inputs
ANNUAL_INCREASE = 1.005 # used in input generation for scaling
BASE_CYCLE_TIME = 80 # seconds
DATAFILE = "#{Data_dir}data.xls" # main data file containing counts, sgp's, you name it
CS = "#{CSPREFIX}#{DATAFILE};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\""
CSVCS = "#{CSPREFIX}#{Data_dir};Extended Properties=\"Text;HDR=YES;FTM=Delimited\""
CSRESDB = "#{CSPREFIX}#{Vissim_dir}results.mdb"
Accname = "acc_#{Res}m.csv"
ACCFILE = "#{Data_dir}#{Accname}"
ENABLE_VAP_TRACING = {:master => false, :slave => false} # write trace statements in vap code?

# the following is used in input and route generation
# denotes the *end* times of data collection intervals eg 7:00 to 7:15
#PERIOD_START, PERIOD_END = '15:15', '17:00'
PERIOD_START, PERIOD_END = '7:15', '9:00'
START_TIME = Time.parse('7:00') # for counting seconds

require 'dbi'
require 'fileutils'
require 'win32ole'

DB = Sequel.dbi CS
LINKS = DB[:'[links$]']
BUSES = DB[:'[buses$]']

def exec_query sql, conn_str = CS
  DBI.connect(conn_str) do |dbh|  
    return dbh.select_all(sql)
  end
end
# Indicates from which direction traffic comes from eg. North
def get_from_direction(fromsc,tosc)
  ((fromsc.number < tosc.number) ? ARTERY[:sc1] : ARTERY[:sc2])[:from_direction]  
end
def to_tex(table, user_opts = {})
  default_opts = {:center => true, :sep_cols => true, :col_align => 'l'}
  opts = default_opts.merge(user_opts)  
  lines = ['\begin{table}[!ht]']
  lines << '\begin{center}' if opts[:center]
  headers = table.first
  lines << "\\begin{tabular}{#{headers.map{opts[:col_align]}.join(opts[:sep_cols] ? '|' : '')}}"
  headers_in_bold = headers.map{|header| (header.nil? or header.empty?) ? '' : "\\textbf{#{header}}"}
  lines << headers_in_bold.join(' & ') + '\\\\ \\hline'
  table[1..-1].each{|row| lines << row.join(' & ') + '\\\\'}
  lines << '\end{tabular}'
  lines << '\end{center}' if opts[:center]
  lines << "\\caption{#{opts[:caption]}}" if opts[:caption]
  lines << "\\label{#{opts[:label]}}" if opts[:label]
  lines << '\end{table}'
  lines.join("\n")
end
# create an array of linearly spaced numbers
def linspace(from,step,limit)
  a = []
  from.step(limit,step){|x| a << x}
  a
end
def numbers(from,step,count)
  linspace(from,step,count * step + from)
end
def to_xls rows, sheetname, xlsfile = DATAFILE
   
  begin
    excel = WIN32OLE::new('Excel.Application')
    wb = excel.Workbooks.Open(xlsfile)
    
    datash = wb.Sheets(sheetname)    
    
    datash.cells.clear
    
    # all-in-one insertion
    datash.range("a1").resize(rows.size, rows[0].size).Value = rows
      
    datash.Range("a1").Autofilter
    datash.Rows(1).Font.Bold = true
    datash.Columns.Autofit
    
    wb.Save
  rescue Error => e
    raise(e, "Failed to write #{rows.size} rows and #{rows.first.size} columns", rows)
  ensure
    excel.DisplayAlerts = false # avoid excel nag to save book
    excel.Quit
  end      
end
class Array
  def sum ; inject{|a,x|x+a} ; end
  def mean ; sum.to_f/size ; end
  def median
    case size % 2
    when 0 then sort[size/2-1,2].mean
    when 1 then sort[size/2].to_f
    end if size.nonzero?
  end
  def squares ; inject{|a,x|x**2+a} ; end
  def variance ; squares.to_f/size - mean**2; end
  def deviation ; variance**(1/2) ; end
  def sample n=1 ; (0...n).collect{ self[Kernel::rand(size)] } ; end
  def rand ; self[Kernel::rand(size)] ; end
  def copy
    inject([]){|a,el|a << (el.respond_to?(:copy) ? el.copy : el)}
  end
end

class Point
  attr_reader :x, :y, :z
  def initialize x, y, z = 0.0
    @x, @y, @z = x, y, z
  end
  def to_s
    "#{@x} #{@y}"
  end
  # calculate the distance between self and point
  def distance point
    dx = @x - point.x
    dy = @y - point.y
    Math.sqrt(dx**2 + dy**2)
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

class Hash
  def self.new_nested_hash
    new{|h,k| h[k] = new(&h.default_proc) }
  end
  def copy
    h = Hash.new(default_proc) 
    each{|k,v|h[k]=v}
    h
  end
  def +(h)
    copy.merge(h.copy)
  end
  def retain_keys!(*keys)
    delete_if{|k,| not keys.include? k}
  end
end