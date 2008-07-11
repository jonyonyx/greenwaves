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
  def interval
    (@from..@to)
  end
  def resolution_in_seconds
    @resolution * 60
  end
  # the number of intervals when
  # dividing the timespan of from-to by the resolution
  def interval_count
    (@to - @from).round / (@resolution * 60)
  end
  def to_s
    @name
  end
  def vissim_start_time
    (@from - (@repeat_first_interval ? resolution_in_seconds : 0)).to_hms
  end
end

MORNING = TestPrograms.new!(
  :name => 'Morgen', 
  :resolution => 15, 
  :from => Time.parse('7:00'), 
  :to => Time.parse('9:00'), 
  :repeat_first_interval => true
)

DAY = TestPrograms.new!(
  :name => 'Dag', 
  :resolution => 60, 
  :from => Time.parse('12:00'), 
  :to => Time.parse('13:00'), 
  :repeat_first_interval => true
)

AFTERNOON = TestPrograms.new!(
  :name => 'Eftermiddag', 
  :resolution => 15,
  :from => Time.parse('15:00'), 
  :to => Time.parse('17:00'), 
  :repeat_first_interval => true
)

FIXED_TIME_PROGRAM_NAME = {MORNING => 'M80', DAY => 'D60', AFTERNOON => 'E80'}

class VissimTest
  attr_reader :name,:programs
  def initialize name, programs, options = {}
    @name,@programs = name,programs
    @opts = options
  end
  def get_output_dir program
    File.join(Base_dir,'test_scenarios', "scenario_#{@name.downcase.gsub(/\s+/, '_')}_#{program.name.downcase}")
  end
  def setup
    
    # for each time-of-day program in the test
    @programs.each do |program|
  
      output_dir = get_output_dir(program)
      
      begin
        Dir.mkdir output_dir
      rescue
        # workdir already exists, clear it
        FileUtils.rm Dir[File.join(output_dir,'*')]
      end
    
      # move into the default vissim directory for this project
      # or the directory of the requested vissim network in order to copy it to
      # a temporary location
      vissim_dir = @opts[:network_dir] ? File.join(Base_dir,@opts[:network_dir]) : Vissim_dir
      
      # copy all relevant files to the instance workdir, first from try the main network
      # dir then the specific network dir
      [Vissim_dir,vissim_dir].uniq.each do |vissim_source_dir|
        Dir.chdir(vissim_source_dir)
        FileUtils.cp(%w{pua knk mdb szp fzi pua vap mes qmk}.map{|ext| Dir["*.#{ext}"]}.flatten, output_dir)
      end
      
      FileUtils.cp(Dir[File.join(vissim_dir,'*.inp')],output_dir)
      
      inpfilename = Dir['*.inp'].first # Vissim => picky
      inppath = File.join(output_dir,inpfilename)
      
      puts "Preparing '#{@name}' #{program}"
      Dir.chdir output_dir
      inpname = Dir['*.inp'].first
      raise "INP file not found in '#{output_dir}'" unless inpname
      inppath = File.join(output_dir,inpname)
  
      vissim = Vissim.new(inppath) # reload network to avoid backreferences
  
      # generate link inputs and routes using the time frame of the test program
      # write them to the vissim file in the workdir
      vissim.foreignadjust(true,'N2')
      vissim.get_inputs(program).write(inppath)  
      vissim.get_routing_decisions(program).write(inppath)
      
      if @opts[:detector_scheme] # => traffic actuated, otherwise fixed signal timing 
        generate_master output_dir
        SLAVES.each do |slave|
          generate_slave(slave,STAGES[slave.name],program,@opts[:detector_scheme],output_dir)
      
          # copy a PUA file tailored for the traffic actuation scheme
          name = slave.name.downcase
          FileUtils.cp(File.join(Vissim_dir,"slave_#{name}.pua"),
            File.join(output_dir,"#{name}.pua"))
        end
    
        # gammel køge landevej remains pretimed - loss of coordination
        gkl = vissim.controllers_with_plans.find{|sc|sc.number == 1} 
    
        generate_controller(gkl,output_dir,FIXED_TIME_PROGRAM_NAME[program])
      else
        vissim.controllers_with_plans.each do |sc|
          program_name = FIXED_TIME_PROGRAM_NAME[program]
          
          if @opts[:alternative_signal_program] # program (Morning...) => program name (M100...)
            altprogname = @opts[:alternative_signal_program][program]          
            program_name = altprogname if sc.program[altprogname]
          end
          
          generate_controller(sc,output_dir,program_name)
        end
      end
      
      yield inppath, program.vissim_start_time, program.name if block_given?      

    end # end for each test program (eg. morning, afternoon)
  end
end

TESTQUEUE = [
  VissimTest.new('Basis', [MORNING,DAY,AFTERNOON]), 
  VissimTest.new('Trafikstyring 1', [MORNING,DAY,AFTERNOON], :detector_scheme => 1), 
  VissimTest.new('Trafikstyring 2', [DAY], :detector_scheme => 2), 
  VissimTest.new('Dobbelt venstresving', [MORNING,AFTERNOON], 
    :network_dir => 'dobbelt_venstre', :detector_scheme => 1), 
  VissimTest.new('Ekstra spor', [MORNING,AFTERNOON], 
    :network_dir => 'ekstra_spor',
    :alternative_signal_program => {MORNING => 'M80-2',AFTERNOON => 'E80-2'}
  ), 
  VissimTest.new('Hoejere omloebstid', [MORNING,AFTERNOON],
    :signal_program_scheme => 3,
    :alternative_signal_program => {MORNING => 'M100',AFTERNOON => 'E100'}
  ), 
  VissimTest.new('Laengere groentid', [MORNING,AFTERNOON], 
    :detector_scheme => 1
  )
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

def generate_controller sc, output_dir, program_name  
  gen_vap sc, output_dir, program_name
  gen_pua sc, output_dir, program_name
end

if __FILE__ == $0
  networks = [['Path','Start Time']]
  TESTQUEUE.each do |test|
    test.setup do |inppath,simstarttime|
      networks << [inppath,simstarttime]
    end
  end
  puts "Prepared #{networks.size-1} scenarios"

  to_xls(networks,'networks to test',File.join(Base_dir,'results','results.xls'))
end
