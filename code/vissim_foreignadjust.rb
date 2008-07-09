require 'vissim'

class Vissim  
  def foreignadjust
    # For decisions which are made at upstream decision points, make 
    # adjustments to maintain ratios
    @decisions.find_all{|d|d.foreign_decision?}.group_by{|d|d.decide_at}.each do |dp,foreign_decisions|
      # Assume all foreign decisions draw their traffic from the (singular) donor decision
      donor_candidates = @decisions.find_all{|d|d.decide_at == dp} - foreign_decisions
      
      # delete donor candidate that does not have a route to each foregin decision
      donor_candidates.delete_if do |dc|
        routes = find_routes(dc, foreign_decisions)
        not foreign_decisions.all?{|fd|routes.any?{|r|r.include?(fd)}}
      end
      
      raise "Invalid number of donor candidates for #{foreign_decisions.join_by(:decid,' ')}: #{donor_candidates.join_by(:decid,' ')}, expected only one" if donor_candidates.size != 1
      
      donor_decision = donor_candidates.first
      
      # for every time interval adjust the fractions of
      # the affected decisions to maintain their relative proportions to the donor decision
      foreign_decisions.map{|d|d.time_intervals}.flatten.uniq.each do |interval|
        [:cars,:trucks].each do |vehtype|
          decision_fractions = {} # decision => list of fractions
          decision_quantity = {} # decision => quantity
          
          foreign_decisions.each do |dec|
            fractions = dec.fractions.filter(interval,vehtype)
            decision_fractions[dec] = fractions              
            decision_quantity[dec] = fractions.sum
          end
          
          # calculate the difference of how much is requested from donor decision
          # and how much the donor can offer          
          donor_sum = donor_decision.fractions.filter(interval,vehtype).sum # availability
          foreign_sum = foreign_decisions.map{|d|d.fractions.filter(interval,vehtype).sum}.sum # demand
          
          newsum = 0
          
          foreign_decisions.each do |dec|
            fractions = dec.fractions.filter(interval,vehtype)    
            decision_quantity = fractions.sum            
            newvalue = donor_sum * (decision_quantity / foreign_sum)
            
            newsum += newvalue
            
            #puts "#{dec.decid} weighs #{decision_quantity / foreign_sum} adjust from #{decision_quantity} to #{newvalue}"
            fractions.each{|f|f.set(newvalue)}
          end
          
          raise "Adjusted sum of foreign demand #{newsum} does not match donor decision availability #{donor_sum} for donor #{donor_decision}" if (newsum-donor_sum).abs > EPS
        end
      end
    end
  end
end