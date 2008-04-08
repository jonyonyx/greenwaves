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
class TravelTimeResults < Array
  def initialize vissim
    @vissim = vissim
  end
  def extract_results name

    ttsql = 'SELECT [No_], AVG(Trav) FROM TRAVELTIMES GROUP BY [No_]'
    
    for row in exec_query(ttsql, CSRESDB)
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
    
    ['Test Name','TT Number','Travel Time', 'From Link', 
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
      
      # insert a row for all results for this tt fella in each test
      for ttres in find_all{|res| res.tt == tt}
        [ttres.testname, tt.number, ttres.value, link_desc(from), link_desc(to), 
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

def link_desc link
  "#{link.number}#{link.name ? " #{link.name}" : ''}"
end


if __FILE__ == $0
  vissim = Vissim.new(Default_network)
  results = TravelTimeResults.new(vissim)
  results.extract_results 'test'
  results.extract_results 'test2'
  results.to_xls
end