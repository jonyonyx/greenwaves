
require 'vissim'

lines = IO.readlines(File.join(Vissim_dir,'amagermotorvejen_avedore-havnevej.mes'))

next until lines.shift =~ /File:\s+(.+)/
inpfile = $1

vissim = Vissim.new(inpfile)

# assume measurement points are created using Auto (all) ie 1-1 mapping
# assume dcp position links are Decisions!

require 'cowi_tests'

data = [['Approach','Decision','Lane','From','To','Observed Cars','Expected Cars','Observed Trucks', 'Expected Trucks']]

while line = lines.shift
  next unless line =~ /(\d+);(\d+);(\d+);(\d+);(\d+)/
  measurement = $1.to_i
  dcp = vissim.collection_points.find{|dcp|dcp.number == measurement}
  carsobs = $4.to_i
  trucksobs = $5.to_i
  
  tstart = vissim.simulation_starttime + $2.to_i
  tend = vissim.simulation_starttime + $3.to_i
  interval = Decision::Interval.new(tstart,tend)
  
  decision = dcp.position_link
  
  carsexp = decision.fractions.filter(interval,:cars).sum
  trucksexp = decision.fractions.filter(interval,:trucks).sum
  
  next if [carsexp,trucksexp].any?{|exp|exp.nil?} # they are out of the measuring period (heating)
  
  data << [
    decision.original_approach,
    decision.decid,
    dcp.lane,
    tstart.to_hm,
    tend.to_hm,
    carsobs,
    dcp.lane > 1 ? '' : carsexp.round,
    trucksobs,
    dcp.lane > 1 ? '' : trucksexp.round
  ]
end

#for row in data
#  puts row.inspect
#end

to_xls(data,'data',File.join(Base_dir,'data','flowcontrol.xls'))
