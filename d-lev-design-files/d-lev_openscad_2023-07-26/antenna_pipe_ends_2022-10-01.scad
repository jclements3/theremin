/* 
PEX antenna ends
*/

$fn=100;

// common features
include <threads.scad>

// config params:
NZ_D=0.4;			// nozzle dia
NZ_H=0.25;			// nozzle height

// build options:
EP=0;					// end plug enable
EC=1;					// end connector enable

// debug options:
CUT=1;				// cutaway view

// defaults:
CH=1;					// chamfer height
CL=0.1;				// diameter clearance
DT=0.1;				// diameter taper

// pipe:
P_OD=15.875;		// od
P_ID=12.0;			// id

// end plug:
EP_OD=P_OD-CL;		// od
EP_ID=P_ID-CL;		// id
EP_OH=3;				// outer height
EP_IH=8;				// inner height

// spring:
S_WD=0.4;			// wire dia
S_OD=4.5;			// od
S_P=14/9;			// pitch
S_H=24;				// height
S_T=S_H/S_P;		// turns

// end connector:
EC_OD=P_OD-CL;		// od
EC_ID=P_ID-CL;		// id
EC_OH=2;				// outer height
EC_TH=S_P*4;		// spring thread height
EC_TD=S_OD+0.2;		// spring thread dia
EC_TA=45;			// spring thread angle
EC_SCH=10;			// spring clearance height
EC_SCD=6.5;			// spring clearance diameter


module end_plug(){
	cylinder(d1=EP_OD-CH, d2=EP_OD, h=CH);  // od chamfer
	translate([0,0,CH]) cylinder(d1=EP_OD, d2=EP_OD-DT, h=EP_OH-CH);  // od
	translate([0,0,EP_OH]) { 
		cylinder(d=EP_ID, h=EP_IH-CH);  // inner dia
		translate([0,0,EP_IH-CH]) cylinder(d1=EP_ID, d2=EP_ID-CH, h=CH);  // inner chamfer
	}
}

module spring(){
	linear_extrude(height = S_H, convexity = 10, twist = 360*S_T, $fn = 100)
	translate([(S_OD-S_WD)/2, 0, 0])
	circle(d=0.4);
}


module end_connector(){
	h0 = EC_SCH+EC_TH;
	module pos(){
		cylinder(d1=EC_OD-CH, d2=EC_OD, h=CH);  // od chamfer
		translate([0,0,CH]) cylinder(d1=EC_OD, d2=EC_OD-DT, h=EC_OH-CH);  // od
		cylinder(d=EC_ID, h=h0-CH);  // inner dia
		translate([0,0,h0-CH]) cylinder(d1=EC_ID, d2=EC_ID-CH, h=CH);  // inner chamfer
	}
	module neg(){
		translate([0,0,EC_SCH]) mirror([1,0,0]) threads(a=EC_TA, d=EC_TD, p=S_P, h=EC_TH+0.01, cl=0, int=true, b=1.5, t=1);  // thread
		cylinder(d1=EC_SCD+CH, d2=EC_SCD, h=CH);  // spring clearance dia
		cylinder(d=EC_SCD, h=EC_SCH);  // spring clearance dia
	}
	difference(){
		pos();
		neg();
	}
}

difference(){
	if (EC) end_connector();
	if (EP) end_plug();
	if (CUT){
		translate([-100,-EC_OD,-10]) cube([200,EC_OD,100]);
	}
}

