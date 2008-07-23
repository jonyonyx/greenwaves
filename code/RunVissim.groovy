import org.codehaus.groovy.scriptom.*

RUNS = 1
RESOLUTION = 3
TESTROOT = /C:\projects\\62832\test_scenarios/
N = Runtime.getRuntime().availableProcessors()

inpsToTest = []
new File(TESTROOT).eachFile{
    inpfiles = it.listFiles().grep(~/.*inp$/)
    inpfiles.each{inpsToTest << it.toString()}
}

//inpsToTest = inpsToTest[0..4]

println "Performing ${inpsToTest.size()} tests x $RUNS"

N.times{
    Thread.start(){
    Scriptom.inApartment
    {
            def vissim = new ActiveXObject('VISSIM.Vissim')
    
            // Setting graphics options for SPEED
            def vissimgraphics = vissim.Graphics
    
            vissimgraphics.AttValue['VISUALIZATION'] = false // no vehicles
            vissimgraphics.AttValue['DISPLAY'] = 2 // invisible network
    
            while(true){
                synchronized(this){
                    if(inpsToTest.empty)
                    break //  allow thread to die
    
                    inppath = inpsToTest.pop()
    
                    vissim.LoadNet(inppath)
                    println "Loaded Vissim network $inppath"
                }
    
                def viseval = vissim.Evaluation
    
                ['QUEUECOUNTER', 'DELAY'].each{viseval.AttValue[it] = true}
                ['NODE', 'TRAVELTIME', 'DATACOLLECTION'].each{viseval.AttValue[it] = false}
    
                def sim = vissim.Simulation
                sim.Speed = 0 // maximum speed
                sim.Resolution = RESOLUTION
    
                vissim.SaveNet()
    
                (1..RUNS).each{
                    synchronized(this){
                        println "Run $it of $RUNS"
                    }
                    sim.RunIndex = it - 1 // first run must have runindex 0
                    sim.RandomSeed = it * 200
                    sim.RunContinuous()
                }
            }
            vissim.Exit()
    }
    }
}