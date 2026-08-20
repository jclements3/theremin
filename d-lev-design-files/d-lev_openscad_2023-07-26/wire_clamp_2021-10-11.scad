/* 
Wire clamp
*/

$fn=100;

// config params:
NZ_D=0.4;				// nozzle dia
NZ_H=0.25;				// nozzle height
// build switches:
RAD=1;					// enable end radius
BIG=1;					// big/small
//  params:
T=NZ_D*3;				// thickness
D=(BIG)?7.5:6;			// wires ID
H=10;						// height
HOLE_D=3.5;				// screw hole dia
// derived params:
GAP=T;					// gap
IR=D/2;					// wire IR
OR=IR+T;					// wire OR
OR2=IR-GAP;				// blend OR
IR2=OR2-T;				// blend IR
L=OR+H;					// bottom flat length
R=H*0.6;					// end radius
HOLE_E=HOLE_D/3;		// bottom screw hole elongation


module outer(){
	difference(){
		cylinder(r=OR, h=H);  // OR
		translate([0,0,-0.01]){
			cylinder(r=IR, h=H+0.02);  // IR
			cube([OR, OR, H+0.02]);  // quad cut
		}
	}
	translate([OR+IR2,0,0]){
		intersection(){
			difference(){
				cylinder(r=OR2, h=H);  // OR2
				translate([0,0,-0.01]) cylinder(r=IR2, h=H+0.02);  // IR2
			}
			rotate([0,0,90]) cube([OR, OR, H+0.02]); // quad retain
		}
	}
	translate([0,IR,0]) cube([L,T,H]);  // bottom flat
	translate([OR+IR2,IR2,0]) cube([L-OR-IR2,T,H]);  // top flat
}


module holes(){
	translate([L-H/2,IR2-0.01,H/2]) rotate([-90,0,0]) cylinder(d=HOLE_D, h=T+0.02);  // top hole
	translate([L-H/2,IR-0.01,H/2]) rotate([-90,0,0]){
		hull(){
			cylinder(d=HOLE_D, h=T+0.02);
			translate([-HOLE_E,0,0]) cylinder(d=HOLE_D, h=T+0.02);
		}
	}
}


module end_radius(){
	translate([0,0,H/2]) rotate([-90,0,0]){
		hull(){
			translate([L-R,0,0]) cylinder(r=R, h=OR*2, center=true);
			translate([-L+R,0,0]) cylinder(r=R, h=OR*2, center=true);
		}
	}
}

module w_no_radius(){
	difference(){
		outer();
		holes();
	}
}

module w_radius(){
	intersection(){
		w_no_radius();
		end_radius();
	}
}

if (RAD) w_radius();
else w_no_radius();