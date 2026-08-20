/* 
spacers between LCD and main PWB
need: 2 tall per unit
need: 6 short per unit if using LCD protection plate or non-low profile encoders
*/

$fn=100;

// config params:
NZ_D=0.4;						// nozzle dia
NZ_H=0.25;						// nozzle height
// build switches
TALL=1;							// height option
THIN=1;							// OD option
//
WC=(THIN)?4:8;					// wall count
ID=4;								// ID
OD=2*(ID/2+NZ_D*WC);			// OD
H=(TALL)?11:1;					// height
//
ROWS=(TALL)?4:6;				// rows
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
