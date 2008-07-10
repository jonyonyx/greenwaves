require 'const'
require 'vissim'

class Vissim
  def countadjust adjust_foreign_approaches = false
    @decisions.group_by{|dec|dec.original_approach}.each do |approach,approach_decisions|
      upstream_decisions = (@decisions - approach_decisions).map do |upstream_decision|
        routes = find_routes(upstream_decision, approach_decisions)
    
        # must contain two decisions: the downstream decision and the upstream
        routes.delete_if{|r|r.decisions.size != 2}
    
        next if routes.empty?
    
        routes.map_by(:decisions).flatten.uniq - approach_decisions
      end.flatten.uniq - [nil]
  
      next if upstream_decisions.empty?
      
      [:cars,:trucks].each do |vehtype|
        approach_decisions.map_by(:time_intervals).flatten.uniq.sort.each do |interval|
          approach_fractions = approach_decisions.map{|dec|dec.fractions.filter(interval,vehtype)}.flatten
          approach_sum = Fractions.sum(approach_fractions)
      
          # the fractions of the approach decisions must be adjusted to fully
          # cover the load of the upstream decision(s), which is not being used as a route
          if adjust_foreign_approaches and approach_decisions.all?{|dec|dec.foreign_decision?}
            
            no_route_decisions = upstream_decisions.find_all{|dec|dec.disable_route?}
            upstreamfractions = no_route_decisions.map{|dec|dec.fractions.filter(interval,vehtype)}.flatten
            
            upstreamsum = Fractions.sum(upstreamfractions)
            
            proportion = {}
            approach_fractions.each do |fraction|
              # split the load according to original fractions
              proportion[fraction] = fraction.quantity / approach_sum
              fraction.set(upstreamsum * proportion[fraction])
            end
            
            newapproachsum = Fractions.sum(approach_fractions)
            raise "Adjusted fractions for #{vehtype} #{interval} at #{approach_decisions.join_by(:decid,' ')} (#{newapproachsum}) differs from fractions of upstream no-route decisions #{no_route_decisions.join_by(:decid,' ')} (#{upstreamsum})" if (upstreamsum-newapproachsum).abs > EPS
            raise "Adjusted fractions for #{vehtype} #{interval} caused incorrect relative proportions in #{approach_decisions.join_by(:decid,' ')}" if approach_fractions.any?{|f|(proportion[f] - f.quantity / newapproachsum).abs > EPS}
          end
        end
      end
    end
  end

  # performs a checkup on the per interval and per veh type
  # flow into each approach from upstream decisions. writes the results into
  # the given excel file in the given sheet name
  def countcontrol xlsfile,sheetname
    
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
    
    countadjust do |interval,approach,downstream_decisions,upstream_decisions,vehtype,downstreamsum,upstreamsum|
      data << [
        interval.tstart.to_hm,interval.tend.to_hm,
        approach,
        downstream_decisions.join_by(:decid,' '),
        upstream_decisions.join_by(:decid,' '),
        vehtype.to_s.capitalize,
        downstreamsum,
        upstreamsum
      ]
    end
    
    for row in data
      puts row.inspect
    end

    to_xls(data,sheetname,xlsfile)
  end
end

if __FILE__ == $0
  vissim = Vissim.new
  vissim.countcontrol 'data', File.join(Base_dir,'data','countcontrol.xls')
end

