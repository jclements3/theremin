/* 
Plate antenna bolt & nut
*/

$fn=100;

// common features
include <threads.scad>

// config params:
NZ_D=0.4;				// nozzle dia
NZ_H=0.25;				// nozzle height
// build options:
NUT=1;					// nut enable
BOLT=1;					// bolt enable
CH=0.5;					// all chamfers
P_T=13;					// plate thickness
W_T=1;					// washer thickness
// nut:
N_H=4;					// nut height
N_OD=20;					// nut OD
// bolt:
B_H=N_H;					// bolt head height
B_OD=N_OD;				// bolt OD
B_ID=6;					// bold ID (0 to disable)
// thread:
THD_D=12;				// thread diameter
THD_P=2;					// thread pitch
THD_A=45;				// thread angle
THD_CL=0;				// thread clearance (nut only)
THD_H=P_T+N_H+2*W_T;	// thread height (bolt only)
// nubs:
NUBS=7;					// nubs
NUB_D=10*NZ_D;			// nub dia
//
DEBUG_EN=0;				// thread debug mode

module body(d, h) {
	cylinder(d1=d-2*CH, d2=d, h=CH);  // chamfer
	translate([0,0,CH]) cylinder(d=d, h=h-2*CH);
	translate([0,0,h-CH]) cylinder(d1=d, d2=d-2*CH, h=CH);  // chamfer
	nubs(d, h);
}

module nubs(d, h){
	for (i=[0:NUBS-1]){
		rotate([0,0,i*360/NUBS]){
			translate([d/2-CH,0,(h-CH)/2]) cylinder(d=NUB_D, h=h-CH, center=true);
		}
	}
}

module bolt_hole() {
	translate([0,0,-0.01]) cylinder(d1=B_ID+2*CH, d2=B_ID, h=CH);  // chamfer
	cylinder(d=B_ID, h=B_H+THD_H);
	translate([0,0,B_H+THD_H-CH+0.01]) cylinder(d1=B_ID, d2=B_ID+2*CH, h=CH);  // chamfer
}

module nut_thread(){
	translate([0,0,-0.01]) threads(a=THD_A, d=THD_D, p=THD_P, h=N_H+0.02, cl=THD_CL, int=true, b=1, t=1, debug=DEBUG_EN);
}

module bolt_thread(){
	translate([0,0,B_H]) threads(a=THD_A, d=THD_D, p=THD_P, h=THD_H, cl=0, int=false, b=0, t=1, debug=DEBUG_EN);
}

module bolt(){
	difference(){
		union(){
			body(d=B_OD, h=B_H);
			bolt_thread();
		}
		if(B_ID) bolt_hole();
	}
}

module nut(){
	difference(){
		body(d=N_OD, h=N_H);
		nut_thread();
	}
}

// render
if(BOLT) bolt();
if(NUT) translate([25*BOLT,0,0]) nut();
