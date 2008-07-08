require 'const'
require 'vissim'

class Vissim
  def countadjust adjust_for_approaches = []
    @decisions.group_by{|dec|dec.original_approach}.each do |approach,downstream_decisions|
      upstream_decisions = (@decisions - downstream_decisions).map do |dec2|
        routes = find_routes(dec2, downstream_decisions)
    
        # must contain two decisions: the downstream decision and the upstream
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
      
          # adjust upstream fractions so that
          # they together they deliver the sum at N2
          # TODO: maintain turning fractions at upstream approaches
          if adjust_for_approaches.include?(approach)
            diff = downstreamsum - upstreamsum
            upstreamfractions.each do |fraction|
              fraction.adjust(diff / upstreamfractions.size) # split the load evenly
            end
            #puts "Adjusted from #{upstreamsum} to #{Fractions.sum(upstreamfractions)} to match #{downstreamsum}"
          end
        
          yield interval,approach,downstream_decisions,upstream_decisions,vehtype,downstreamsum,upstreamsum if block_given?
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

