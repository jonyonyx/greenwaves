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
DOGS_MAJOR_FACTOR = 0.8
DOGS_MINOR_FACTOR = 1.0 - DOGS_MAJOR_FACTOR
DOGS_MAX_LEVEL = 5
BUS_TIME = 10 # number of seconds to extend green time for bus stages
DOGS_CNT_BOUNDS_FACTOR = 0.8 # adjust the aggresiveness of DOGS. Lower => more aggressive to increase cycle times.
DOGS_OCC_BOUNDS_FACTOR = 0.8
# associated numbers with these vehicle types
Type_map = {:cars => 1001, :trucks => 1002, :buses => 1003}
RESULTS_FILE = "#{Base_dir}results\\results.xls"
RESULTS_FILE_CS = "#{CSPREFIX}#{RESULTS_FILE};Extended Properties=\"Excel 8.0;HDR=Yes;IMEX=1\""
  
  
Project = 'dtu'


Herlev_dir = "#{Data_dir}DOGS Herlev 2007\\"
Glostrup_dir = "#{Data_dir}DOGS Glostrup 2007\\"
MIN_STAGE_LENGTH = 6 # used when DOGS changes level and a stage jump maybe be considered