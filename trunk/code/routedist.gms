$eolcom //
option iterlim=999999999;     // avoid limit on iterations
option reslim=300;            // timelimit for solver in sec.
option optcr=0.0;             // gap tolerance
option solprint=ON;           // include solution print in .lst file
option limrow=100;            // limit number of rows in .lst file
option limcol=100;            // limit number of columns in .lst file
//--------------------------------------------------------------------

Sets
       	d   	"decision points"
	/	1*6		/
	
	t	"turning decisions at decision points"
	/	1*12		/
	
       	r   	"routes"
	/	1*8		/
;

Alias (d,d1);
Alias (d,d2);

Parameters
       	y(d) "flow to input decision points"
	/	1	150
		2	30
		3	25
		4	100	/

	P(d1,d2) "contributions to adjacent dp's"
	/	1 . 5 = 0.8
		2 . 5 = 0.5
		3 . 6 = 0.6
		4 . 6 = 0.9	/
;

Table
	D(d,r) "decision points 
;

Variables
	x(r)  "load on route r"
     	z     "result"
;

Positive Variable x;

Equations
	result		"relative route loads"
	turningprob(d)	"respect turning probabilities"
	flowbal(d)	"maintain flow balance between dp's"
;

result ..		z =e= 0;
turningprob(d)..	sum(r, a(i,j)*x(j)) =l= b(i);

Model problem /all/ ;

Solve problem using lp maximizing z;

DISPLAY x.M;
