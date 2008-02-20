$eolcom //
option iterlim=999999999;     // avoid limit on iterations
option reslim=300;            // timelimit for solver in sec.
option optcr=0.0;             // gap tolerance
option solprint=ON;           // include solution print in .lst file
option limrow=100;            // limit number of rows in .lst file
option limcol=100;            // limit number of columns in .lst file
//--------------------------------------------------------------------

Sets
       	i   	"functional constraints"
	/	a, b 		/ 

	j	"beams"
	/ 	1, 2, 3, 4	/
;

Parameters

       	b(i)	"limits"
	/	a	0.4
		b	0.5	/

	c(j)	"values"
	/	1	-2.7
		2	6
		3	-6
		4	6	/
	
;

Table a(i,j) "radiation values"
		1	2	3	4
	a	0.3	0.5	-0.5	0.6
	b	0.1	0.5	-0.5	0.4

Variables
	x(j)  "radiation from beam j"
     	z     "result"
;

Positive Variable x;

Equations
	result		"resulting radiation"
	constraints(i)	"constraint matrix"
;

result ..		z =e= sum(j, x(j)*c(j));
constraints(i)..	sum(j, a(i,j)*x(j)) =l= b(i);

Model problem /all/ ;

Solve problem using lp maximizing z;

DISPLAY x.M;
