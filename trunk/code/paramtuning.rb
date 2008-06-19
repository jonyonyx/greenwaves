require 'const'
require 'greenwave_eval'
require 'drb'
require 'ruby_test_server'

TIME = [0.5] # second

ALPHA = [0.9] #[0.8,0.85,0.9,0.95,0.98] # cooldown factors
TEMP = [100]#,200,300,400,500] # starting temperatures
JUMPSTART_THRESHOLD = [75] #[50,75,100,125,150]
OFFSET_SPLIT = [0,0.5,0.55,0.6,0.65,0.7,0.75,0.8,0.85,0.9,0.95,0.99,1.0]
RUNS = 10 

vissim = Vissim.new

HERLEV_CONTROLLERS = vissim.controllers.find_all{|sc|(1..5) === sc.number}
GLOSTRUP_CONTROLLERS = vissim.controllers.find_all{|sc|(9..12) === sc.number}

PROBLEMAREA = [
  {
    :name => 'Herlev', 
    :controllers => HERLEV_CONTROLLERS,
    :coordinations => parse_coordinations(HERLEV_CONTROLLERS,vissim)
  },    
  {
    :name => 'Glostrup', 
    :controllers => GLOSTRUP_CONTROLLERS,
    :coordinations => parse_coordinations(GLOSTRUP_CONTROLLERS,vissim)
  }
]

combinations = []

ALPHA.each do |alpha|
  TEMP.each do |temp|
    JUMPSTART_THRESHOLD.each do |th|
      combinations << {:start_temp => temp, :alpha => alpha, :no_improvement_action_threshold => th}
    end
  end
end

results = []

tester = Tester.new
while saparms = combinations.pop
  puts "Remaining tests: #{combinations.size}"
  OFFSET_SPLIT.each do |offset_split|
    PROBLEMAREA.each do |pa|
      TIME.each do |time|
        encumbent_values = []
        RUNS.times do
          result = tester.run_solver(saparms, time, 80, pa[:coordinations],offset_split) + saparms
          encumbent_values << result[:encumbent_value]
        end
        mean = encumbent_values.mean
        std = encumbent_values.deviation
        results << saparms + {:mean => mean, :std => std, :area => pa[:name], :offset_split => offset_split}
      end
    end
  end
end

sorted = results.sort{|r1,r2| r1[:mean] == r2[:mean] ? r1[:std] <=> r1[:std] : r1[:mean] <=> r2[:mean]}

data = [['Area','Cooling Factor','Starting Temperature','Jumpstart Threshold','Offset Probability','Mean','Deviation']]

PROBLEMAREA.map{|pa|pa[:name]}.each do |area|
  puts "Top results in #{area}:"
  sorted.find_all{|r|r[:area] == area}.each do |res|
    puts "alpha = #{res[:alpha]}, start temp = #{res[:start_temp]}, threshold = #{res[:no_improvement_action_threshold]} => " +
      "#{res[:mean]} (#{res[:std]})"
    data << [area,res[:alpha],res[:start_temp],res[:no_improvement_action_threshold],res[:offset_split],res[:mean],res[:std]]
  end
end

to_xls(data,'data_offset',File.join('d:','greenwaves','results','paramtuning.xls'))
