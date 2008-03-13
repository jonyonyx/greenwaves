# 
# To change this template, choose Tools | Templates
# and open the template in the editor.

require 'dbi'

require 'network'
require 'signal'

Base_dir = 'D:\\greenwaves\\'
Herlev_dir = Base_dir + 'data\\DOGS Herlev 2007\\'
Glostrup_dir = Base_dir + 'data\\DOGS Glostrup 2007\\'
Vissim_dir = Base_dir + 'Vissim\\o3_roskildevej-herlevsygehus\\'

Time_fmt = '%H:%M:%S'
Res = 15 # resolution in minutes of inputs

RED,YELLOW,GREEN,AMBER = 'R','Y','G','A'

# DOGS priority levels
MINOR = 'Minor'
MAJOR = 'Major'
NONE = 'None'

# associated numbers with these vehicle types
Type_map = {'Cars' => 1001, 'Trucks' => 1002, 'Buses' => 1003}
EPS = 0.01
INPUT_FACTOR = 1.0 # factor used to adjust link inputs
ANNUAL_INCREASE = 1.015 # used in input generation for scaling
DOGS_LEVELS = 8
DOGS_LEVELDOWN_BUFFER = 0.1 # percentage of threshold value for current level
DOGS_TIME = 10 # number of seconds by which cycle time is increased for each dogs level
DOGS_LEVEL_GREEN = 10 # seconds green time associated with each dogs level change
BASE_CYCLE_TIME = 80 # seconds
DATAFILE = "../data/data.xls" # main data file containing counts, sgp's, you name it
CS = "DBI:ADO:Provider=Microsoft.Jet.OLEDB.4.0;Data Source=#{DATAFILE};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\";"

def exec_query sql, conn_str = CS
  DBI.connect(conn_str) do |dbh|  
    return dbh.select_all(sql)
  end
end
def get_links attributes = {}
  type_filter = attributes['TYPE'].downcase if attributes.has_key?('TYPE')
    
  links_map = {}
  ObjectSpace.each_object(Link){|link| links_map[link.number] = link}
    
  links = []
    
  for row in exec_query 'SELECT NUMBER, NAME, [FROM], TYPE FROM [links$] As LINKS'
    number = row['NUMBER'].to_i    
            
    if links_map.has_key?(number)
      # enrich the existing object with data from the database
      link = links_map[number]
      link.update row
    else
      next if type_filter and row['TYPE'].downcase != type_filter
      link = Link.new(number,row)
    end
    links << link
  end
  links
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
  def variance ; squares.to_f/size - mean.square; end
  def deviation ; Math::sqrt( variance ) ; end
  def sample n=1 ; (0...n).collect{ self[rand(size)] } ; end
end