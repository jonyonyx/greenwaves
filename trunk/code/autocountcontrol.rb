require 'const'
require 'vissim'

vissim = Vissim.new

data = [
  [
    'From',
    'To',
    'Approach',
    'Approach Decisions',
    'Upstream Decisions',
    'Vehicle Type',
    'Approach Sum',
    'Inflow from Upstream',
    'Proportion'
  ]  
]

vissim.decisions.group_by{|dec|dec.original_approach}.each do |approach,downstream_decisions|
  upstream_decisions = (vissim.decisions - downstream_decisions).map do |dec2|
    routes = vissim.find_routes(dec2, downstream_decisions)
    
    routes.delete_if{|r|r.decisions.size != 2}
    
    next if routes.empty?
    
    routes.map{|r|r.decisions}.flatten.uniq - downstream_decisions
  end.flatten.uniq - [nil]
  
  next if upstream_decisions.empty?
  
  [:cars,:trucks].each do |vehtype|
    downstream_decisions.map{|dec|dec.time_intervals}.flatten.uniq.sort.each do |interval|
      upstreamfractions = upstream_decisions.map{|dec|dec.fractions.filter(interval,vehtype)}.flatten
      downstreamfractions = downstream_decisions.map{|dec|dec.fractions.filter(interval,vehtype)}.flatten
      upstreamsum = Fractions.sum(upstreamfractions)
      downstreamsum = Fractions.sum(downstreamfractions)
      data << [
        interval.tstart.to_hm,
        interval.tend.to_hm,
        approach,
        "#{downstream_decisions.join_by(:decid, ' ')}",
        "#{upstream_decisions.join_by(:decid, ' ')}",
        vehtype.to_s.capitalize,
        downstreamsum,
        upstreamsum,
        downstreamsum / upstreamsum
      ]
    end
  end
end

#for row in data
#  puts row.inspect
#end

to_xls(data,'data',File.join(Base_dir,'data','countcontrol.xls'))

