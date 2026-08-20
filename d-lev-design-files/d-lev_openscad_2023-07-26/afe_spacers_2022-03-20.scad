/* 
simple spacer for AFEs
*/

$fn=100;

// config params:
NZ_D=0.4;						// nozzle dia
NZ_H=0.25;						// nozzle height
//
WC=8;								// wall count
ID=3.6;							// ID
OD=2*(ID/2+NZ_D*WC);			// OD
H=2;								// height
//
ROWS=4;							// rows
COLS=6;							// columns
DIST=2;							// distance between

module spacer(){
	translate([0,0,H/2]){
		difference(){
			cylinder(d=OD, h=H, center=true);  // OD
			cylinder(d=ID, h=H+0.01, center=true);  // ID
		}
	}
}

module spacers(){
	for (c=[0:COLS-1]){
		for (r=[0:ROWS-1]){
			translate([c*(OD+DIST),r*(OD+DIST),0]) spacer();
		}
	}
}

spacers();

echo("OD", OD);
