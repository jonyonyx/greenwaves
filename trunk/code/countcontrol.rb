require 'const'
require 'vissim'

vissim = Vissim.new

decisions = vissim.decisions.find_all{|dec|%w{N2T E2L N3T N3L}.include?(dec.decid)}
upstream = decisions.find_all{|dec|dec.intersection == 2}
downstream = decisions - upstream

#decisions.each do |dec|
#  puts dec.time_intervals
#end

[:cars,:trucks].each do |vehtype|
  decisions.map{|dec|dec.time_intervals}.flatten.uniq.sort.each do |interval|
    upstreamfractions = upstream.map{|dec|dec.fractions.filter(interval,vehtype)}.flatten
    downstreamfractions = downstream.map{|dec|dec.fractions.filter(interval,vehtype)}.flatten
    upstreamsum = Fractions.sum(upstreamfractions)
    downstreamsum = Fractions.sum(downstreamfractions)
    puts "#{interval} #{vehtype} #{upstreamsum/downstreamsum}"
  end
end
