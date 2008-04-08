# 
# collect results from vissim results .mdb file

require 'const'
require 'vissim'
require 'vissim_routes'
require 'win32ole'

class TravelTimeResult
  attr_reader :testname, :tt, :value
  def initialize name, tt, value
    @testname = name
    @tt = tt
    @value = value
  end
  def <=>(ttres)
    (@tt == ttres.tt) ? (@testname <=> ttres.testname) : (@tt <=> ttres.tt)
  end
end
class TravelTimeResults < ThreadSafeArray
  #travel times are inserted "raw" ie in chronological
  # order and the vehicles (Veh) column indicates the total number of vehicles
  # that participated in this travel time measurement. below is
  # SQL to fetch the last entry into TRAVELTIMES. 
  @@ttsql = 'SELECT 
              TRAVELTIMES.[No_], 
              Trav,
              Veh
             FROM TRAVELTIMES 
             INNER JOIN (SELECT [No_], MAX([Time]) As T FROM TRAVELTIMES GROUP BY [No_]) As MAXTIMES
             ON TRAVELTIMES.[Time] = MAXTIMES.T'
  
  def initialize vissim
    @vissim = vissim
  end
  
  def extract_results name, resdir
    
    for row in exec_query(@ttsql, "#{CSPREFIX}#{File.join(resdir,'results.mdb')};")
      ttnum = row[0]
    
      # find the traveltime entry in order to gain additional insight
      tt = @vissim.tt_map[ttnum]
    
      self << TravelTimeResult.new(name, tt, row[1].to_i)
    end
  end
  def to_xls xlsfile = "#{Base_dir}results\\results.xls"
        
    insect_info = exec_query "SELECT Name, Number FROM [intersections$]"
    routes = get_full_routes(@vissim, @vissim.input_links + @vissim.links.find_all{|l| l.is_bus_input})
          
    excel = WIN32OLE::new('Excel.Application')
    wb = excel.Workbooks.Open(xlsfile)
    
    datash = wb.Sheets('data')    
    
    datash.cells.clear
    
    ['TT Number','Test Name', 'Travel Time', 'Vehicle Type', 'Traffic Type', 'From Link', 
      'To Link', 'From Dec', 'To Dec', 'From IS', 'To Is'].each_with_index do |header,i|
      datash.cells(1,i+1).Value = header
    end
    
    j = 2 # excel row number
    for tt in map{|res| res.tt}.uniq.sort
      from, to = tt.from, tt.to
      route = routes.find{|r| r.start == from and r.exit == to}
      raise "No route found from #{from} to #{to}!" if route.nil?
      
      # extract the decisions which are traversed first and last on this route
      firstdec = route.decisions.first
      lastdec = route.decisions.last
      
      fromis = insect_info.find{|r| r['Number'] == firstdec.intersection}['Name']
      tois = insect_info.find{|r| r['Number'] == lastdec.intersection}['Name']
      
      veh_types = tt.vehicle_classes.join(' & ')
      
      # 'arterial' traffic exits in either end of the arterial
      traffic_type = if not (['N','S'] & [firstdec.from,lastdec.from]).empty? and lastdec.turning_motion == 'T'
        'Arterial'
      else
        'Crossing'
      end
      
      # insert a row for all results for this tt fella in each test
      for ttres in find_all{|res| res.tt == tt}
        [tt.number, ttres.testname, ttres.value, veh_types, traffic_type, from.number, to.number, 
          firstdec, lastdec, fromis, tois].each_with_index do |value,i|
          datash.cells(j,i+1).Value = value.to_s
        end
        j += 1
      end
            
    end
    
    datash.Range("a1").Autofilter
    datash.Columns.Autofit
    
    wb.Save
    
    excel.Quit
  end
end