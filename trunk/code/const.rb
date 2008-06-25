# Generic and project specific constants.
# Utility methods.

require 'rubygems'
require 'sequel'

CSPREFIX = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source="

require "#{ARGV.first || 'thesis'}_settings" # load project specific constants

Tempdir = ENV['TEMP'].gsub("\\",'/')
Default_network = File.join(Vissim_dir,Network_name)
  
Time_fmt = '%H:%M:%S'
EU_date_fmt = '%d-%m-%Y'
Res = 15 # resolution in minutes of inputs
MINUTES_PER_HOUR = Seconds_per_minute = 60

RED,YELLOW,GREEN,AMBER = 'R','Y','G','A'

# reverse the type map so that composition numbers point to the text description
# assume 1-to-1 mapping
Type_map_rev = []
Type_map.each{|k,v| Type_map_rev[v] = k}

# strings and composition numbers for cars and trucks (buses are handled separately
Cars_and_trucks_str1 = [:cars,:trucks]
Cars_and_trucks = Type_map.map{|k,v| Cars_and_trucks_str1.include?(k) ? v : nil} - [nil]

EPS = 0.01
ANNUAL_INCREASE = 1.005 # used in input generation for scaling
BASE_CYCLE_TIME = 80 # seconds
DATAFILE = File.join(Base_dir,'data',"data.xls") # main data file containing counts, sgp's, you name it
CS = "#{CSPREFIX}#{DATAFILE};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\""
ENABLE_VAP_TRACING = {:master => false, :slave => false} # write trace statements in vap code?

# the following is used in input and route generation
# denotes the *end* times of data collection intervals eg 7:00 to 7:15
#PERIOD_START, PERIOD_END = '15:15', '17:00'
PERIOD_START, PERIOD_END = '7:15', '9:00'
START_TIME = Time.parse('7:00') # for counting seconds
END_TIME = Time.parse('9:00')

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
  default_opts = {:center => true, :sep_cols => true, :col_align => 'l', :row_sep => "\r"}
  opts = default_opts.merge(user_opts)  
  lines = ['\begin{table}[ht]']
  lines << '\centering' if opts[:center]
  headers = table.first
  lines << "\\begin{tabular}{#{headers.map{opts[:col_align]}.join(opts[:sep_cols] ? '|' : '')}}"
  headers_in_bold = headers.map{|header| (header.nil? or header.to_s.empty?) ? '' : "\\textbf{#{header}}"}
  lines << headers_in_bold.join(' & ') + '\\\\ \\hline'
  table[1..-1].each{|row| lines << row.join(' & ') + '\\\\'}
  lines << '\end{tabular}'
  lines << "\\caption{#{opts[:caption]}}" if opts[:caption]
  lines << "\\label{#{opts[:label]}}" if opts[:label]
  lines << '\end{table}'
  lines.join(opts[:row_sep])
end
# create an array of linearly spaced numbers
def linspace(from,step,limit)
  a = []
  from.step(limit,step){|x| a << x}
  a
end
class Time
  def to_hm
    strftime "%H:%M"
  end
end
def numbers(from,step,count)
  linspace(from,step,(count - 1) * step + from)
end
def maybe?
  rand < 0.5
end
def to_xls rows, sheetname, xlsfile
   
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
  rescue Exception => e
    raise(e, "Failed to write #{rows.size} rows and #{rows.first.size} columns to sheet '#{sheetname}' of excel file '#{xlsfile}'")
  ensure
    excel.DisplayAlerts = false # avoid excel nag to save book
    excel.Quit
  end      
end
class Array
  def sum ; inject{|a,x|x+a} ; end
  def mean ; sum.to_f/size ; end
  def variance
    mu = mean
    inject{|a,x|(x - mu)**2 + a}
  end
  def deviation 
    Math.sqrt(variance)
  end
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

class Range
  def overlap? other
    include?(other.first) or other.include?(first)
  end
end

class Integer
  def fact
    return 1 if self <= 1
    (1..self).inject { |i,j| i*j }
  end
end

if __FILE__ == $0
  puts Project
end