require 'vissim'

class Vissim  
  def foreignadjust adjust_foreign_approaches = false, *adjust_upstream_for_approaches
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
      
          # the fractions of the approach decisions must be adjusted to fully
          # cover the load of the upstream decision(s), which is not being used as a route
          if adjust_foreign_approaches and approach_decisions.all?{|dec|dec.foreign_decision?}
            
            no_route_decisions = upstream_decisions.find_all{|dec|dec.disable_route?}
            
            make_adjustments approach_decisions,no_route_decisions,interval,vehtype,false
            
          elsif adjust_upstream_for_approaches.include?(approach)  
            # the upstream decisions does not feed the approach sufficiently or
            # they overfeed it and should be adjust to match the expected traffic
            make_adjustments approach_decisions, upstream_decisions,interval,vehtype,true
          end
        end
      end
    end
  end
  def make_adjustments approach_decisions,upstream_decisions,interval,vehtype,adjust_upstream
    upstream_fractions = upstream_decisions.map{|dec|dec.fractions.filter(interval,vehtype)}.flatten            
    upstreamsum = Fractions.sum(upstream_fractions)
    
    approach_fractions = approach_decisions.map{|dec|dec.fractions.filter(interval,vehtype)}.flatten
    approachsum = Fractions.sum(approach_fractions)
    
    fractions_to_adjust = (adjust_upstream ? upstream_fractions : approach_fractions)
    originalsum = (adjust_upstream ? upstreamsum : approachsum)
    desiredsum = (adjust_upstream ? approachsum : upstreamsum)
    
    proportion = {}    
    fractions_to_adjust.each do |fraction|
      # split the load according to original fractions
      proportion[fraction] = fraction.quantity / originalsum
      fraction.set(desiredsum * proportion[fraction])
    end
    
    newsum = Fractions.sum(fractions_to_adjust)
    
    adjusted_decisions = adjust_upstream ? upstream_decisions : approach_decisions
    role_decisions = adjust_upstream ? approach_decisions : upstream_decisions
    
    raise "Adjusted fractions for #{vehtype} #{interval} at #{adjusted_decisions.join_by(:decid,' ')} (#{newsum}) differs from fractions of decisions to match #{role_decisions.join_by(:decid,' ')} (#{desiredsum})" if (desiredsum-newsum).abs > EPS
    raise "Adjusted fractions for #{vehtype} #{interval} caused incorrect relative proportions in #{adjusted_decisions.join_by(:decid,' ')}" if fractions_to_adjust.any?{|f|(proportion[f] - f.quantity / newsum).abs > EPS}
  
  end; private :make_adjustments
end