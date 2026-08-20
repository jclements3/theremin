/* 
simple washer
*/

$fn=100;

// config params:
NZ_D=0.4;						// nozzle dia
NZ_H=0.25;						// nozzle height
GIANT=0;							// build param for ID & OD
SMALL=0;							// build param for OD
THICK=0;							// build param for thickness
//
WC=(GIANT)?23:(SMALL)?8:12;// wall count
LC=(THICK)?6:4;				// layer count
ID=(GIANT)?12:3.3;			// ID
OD=2*(ID/2+NZ_D*WC);			// OD
H=NZ_H*LC;						// height (thickness)
CH=H/2;							// chamfer height
//
ROWS=3;							// rows
COLS=6;							// columns
DIST=2;							// distance between

module outer(){
	cylinder(d1=OD-2*CH, d2=OD, h=CH);  // chamfer
	translate([0,0,CH]) cylinder(d=OD, h=H-CH);  // OD
}

module washer(){
	difference(){
		outer();
		translate([0,0,-0.01]) cylinder(d=ID, h=H+0.02);  // hole
	}
}

module washers(){
	for (c=[0:COLS-1]){
		for (r=[0:ROWS-1]){
			translate([c*(OD+DIST),r*(OD+DIST),0]) washer();
		}
	}
}

washers();

echo("OD", OD);
echo("thickness", H);
