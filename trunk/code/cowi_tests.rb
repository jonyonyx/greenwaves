require 'const'
require 'vissim_input'
require 'turningprob'

class TestPrograms
  attr_reader :name,
    :from,:to, # start- and end times of the simulation
  :network_dir, # alternative network directory to copy from
  :resolution, # the resolution of traffic is minutes
  :repeat_first_interval # use for sim heating
  def duration
    @to - @from
  end  
  # the number of intervals when
  # dividing the timespan of from-to by the resolution
  def interval_count
    (@to - @from).round / (@resolution * 60)
  end
  def to_s
    @name
  end
end

MORNING = TestPrograms.new! :name => 'Morgen', :resolution => 15, :from => Time.parse('7:00'), :to => Time.parse('9:00'), :repeat_first_interval => true
DAY = TestPrograms.new! :name => 'Dag', :resolution => 60, :from => Time.parse('11:00'), :to => Time.parse('13:00')
AFTERNOON = TestPrograms.new! :name => 'Eftermiddag', :resolution => 15,:from => Time.parse('15:00'), :to => Time.parse('17:00'), :repeat_first_interval => true
FIXED_TIME_PROGRAM_NAME = {'Morgen' => 'M80', 'Dag' => 'D60', 'Eftermiddag' => 'E80'}

TESTQUEUE = [
  {
    :name => 'Basis', 
    :programs => [MORNING,DAY,AFTERNOON]
  }, {
    :name => 'Trafikstyring 1', 
    :programs => [MORNING,DAY,AFTERNOON], 
    :detector_scheme => 1
  }, {
    :name => 'Trafikstyring 2', 
    :programs => [DAY], 
    :detector_scheme => 2
  }, {
    :name => 'Dobbelt venstreving', 
    :programs => [MORNING,AFTERNOON], 
    :network_dir => 'dobbelt_venstre',
    :detector_scheme => 1
  }, {
    :name => 'Ekstra spor på rampe fra København', 
    :programs => [MORNING,AFTERNOON], 
    :network_dir => 'ekstra_spor',
    :detector_scheme => 1
  }, {
    :name => 'Fast tidsstying med højere omløbstid (100s)', 
    :programs => [MORNING,AFTERNOON]
  }, {
    :name => 'Længere grøntid til venstresving', 
    :programs => [MORNING,AFTERNOON], 
    :detector_scheme => 1
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
      :greentime => {MORNING => [12,30], DAY => [12,20], AFTERNOON => [12,20]},
      :detectors => [7,8,20]
    ),
    ExtendableStage.new!(:name => 'At1', :number => 2, :wait_for_sync => true,
      :greentime => {MORNING => [22-12, 44-30], DAY => [22-12,41-20], AFTERNOON => [24-12,50-20]},
      :detectors => [9,10,15]
    ),
    ExtendableStage.new!(:name => 'B1',  :number => 3,
      :greentime => {MORNING => [10,23], DAY => [10,16], AFTERNOON => [10,17]},
      :detectors => [11,12,21,22,23] # NB 21 only used in trafikstyring 2
    )
  ],
  'syd' => [
    ExtendableStage.new!(:name => 'A2',  :number => 1,
      :greentime => {MORNING => [21-12, 38-21], DAY => [21-12,41-26], AFTERNOON => [21-12,55-34]},
      :detectors => [5,6,14]
    ),
    ExtendableStage.new!(:name => 'At2', :number => 2, :wait_for_sync => true,
      :greentime => {MORNING => [12,21], DAY => [12,26], AFTERNOON => [12,34]},
      :detectors => [3,4]
    ),
    ExtendableStage.new!(:name => 'B2',  :number => 3,
      :greentime => {MORNING => [10,29], DAY => [10,16], AFTERNOON => [10,12]},
      :detectors => [1,2,17,18,19] # NB 17 only used in trafikstyring 2
    )
  ]
}

# prepare link inputs, routing decisions and signal controllers before the test is run
def setup_test(detector_scheme, program, output_dir)  
  puts "Preparing '#{detector_scheme ? "Trafikstyring #{detector_scheme}" : FIXED_TIME_PROGRAM_NAME[program.name]}' #{program}"
  Dir.chdir output_dir
  inpname = Dir['*.inp'].first
  raise "INP file not found in '#{output_dir}'" unless inpname
  inppath = File.join(output_dir,inpname)
  
  vissim = Vissim.new(inppath) # reload network to avoid backreferences
  
  # generate link inputs and routes using the time frame of the test program
  # write them to the vissim file in the workdir
  get_inputs(vissim,program).write(inppath)
  
  # there are no traffic counts for traffic
  get_routing_decisions(vissim, program).write(inppath)
  
  if detector_scheme # => traffic actuated, otherwise fixed signal timing 
    generate_master output_dir
    SLAVES.each do |slave|
      generate_slave(slave,STAGES[slave.name],program,detector_scheme)
      
      # copy a PUA file tailored for the traffic actuation scheme
      name = slave.name.downcase
      FileUtils.cp(File.join(Vissim_dir,"slave_#{name}.pua"),
        File.join(output_dir,"#{name}.pua"))
    end
  else
    # copy 'a' master program to avoid a nag - it is not used
    FileUtils.cp(File.join(Vissim_dir,'master.vap'), output_dir) unless output_dir == Vissim_dir
    vissim.controllers_with_plans.each do |sc|
      gen_vap sc, output_dir, FIXED_TIME_PROGRAM_NAME[program.name]
      gen_pua sc, output_dir, FIXED_TIME_PROGRAM_NAME[program.name]
    end
  end
end

if __FILE__ == $0
  #puts AFTERNOON.interval_count
  setup_test(nil, MORNING, Vissim_dir)
end
