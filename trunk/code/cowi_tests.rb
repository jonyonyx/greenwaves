require 'const'

class TestPrograms
  attr_reader :name,:from,:to
  def duration
    @to - @from
  end
  def to_s
    @name
  end
end

MORNING = TestPrograms.new! :name => 'Morgen', :from => Time.parse('7:00'), :to => Time.parse('9:00')
DAY = TestPrograms.new! :name => 'Dag', :from => Time.parse('12:00'), :to => Time.parse('13:00'), :network_dir => 'dagstrafik'
AFTERNOON = TestPrograms.new! :name => 'Eftermiddag', :from => Time.parse('15:00'), :to => Time.parse('17:00')

TESTQUEUE = [
  {
    :name => 'Basis', 
    :programs => [MORNING,DAY,AFTERNOON]
  }, {
    :name => 'Trafikstyring 1', 
    :programs => [MORNING,DAY,AFTERNOON], 
    :signal_scheme => 1
  }, {
    :name => 'Trafikstyring 2', 
    :programs => [DAY], 
    :signal_scheme => 2
  }, {
    :name => 'Dobbelt venstreving', 
    :programs => [MORNING,AFTERNOON], 
    :signal_scheme => 1
  }, {
    :name => 'Ekstra spor på rampe fra København', 
    :programs => [MORNING,AFTERNOON], 
    :signal_scheme => 1
  }, {
    :name => 'Højere omløbstid (100s)', 
    :programs => [MORNING,AFTERNOON], 
    :signal_scheme => 1
  }, {
    :name => 'Længere grøntid til venstresving', 
    :programs => [MORNING,AFTERNOON], 
    :signal_scheme => 1
  }
]

require 'vap_avedoere-havnevej' # methods for generating H&H master and slave controllers

# north and south junction has 3 stages
# A is north-south going
# Av is for left-turning down on highway
# B is for traffic coming off the highway and up from the ramp
STAGES = {
  'nord' => [
    ExtendableStage.new!(:name => 'A1',  :number => 1,
      :greentime => {MORNING => [12,30], DAY => [12,20], AFTERNOON => [12,20]}
    ),
    ExtendableStage.new!(:name => 'At1', :number => 2, :wait_for_sync => true,
      :greentime => {MORNING => [22-12, 44-30], DAY => [22-12,41-20], AFTERNOON => [24-12,50-20]}
    ),
    ExtendableStage.new!(:name => 'B1',  :number => 3,
      :greentime => {MORNING => [10,23], DAY => [10,16], AFTERNOON => [10,17]}
    )
  ],
  'syd' => [
    ExtendableStage.new!(:name => 'A2',  :number => 1,
      :greentime => {MORNING => [21-12, 38-21], DAY => [21-12,41-26], AFTERNOON => [21-12,55-34]}
    ),
    ExtendableStage.new!(:name => 'At2', :number => 2, :wait_for_sync => true,
      :greentime => {MORNING => [12,21], DAY => [12,26], AFTERNOON => [12,34]}
    ),
    ExtendableStage.new!(:name => 'B2',  :number => 3,
      :greentime => {MORNING => [10,29], DAY => [10,16], AFTERNOON => [10,12]}
    )
  ]
}

def generate_controllers1(vissim, is_traffic_actuated, program, output_dir)
  if is_traffic_actuated 
    generate_master output_dir
    SLAVES.each{|slave|generate_slave(slave,STAGES[slave.name],program)}
  else
    vissim.controllers_with_plans.each do |sc|
      gen_vap sc, output_dir, sc.offset
      gen_pua sc, output_dir
    end
  end
end

if __FILE__ == $0
  generate_controllers1(Vissim.new, false, AFTERNOON, Vissim_dir)
end
