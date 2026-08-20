/* 
mic stand mount trim ring
*/

$fn=100;


// config params:
NZ_D=0.4;		// nozzle dia
NZ_H=0.25;		// nozzle height

// debug options:
DEBUG=0;			// show adapter & stuff
RUBBER=0;		// rubber or not

// mount (metal)
F_H=3.6;			// flange height
F_D=60;			// flange OD
N_H=18-3.6;		// neck height
N_D=20;			// neck OD
N_ID=15;			// neck thread ID
H_N=3;			// hole count
H_D=4.5;			// hole ID
H_BC=21.8*2;	// hole bolt circle

// rubber
R_H=3;			// rubber height

// plywood
P_H=5;			// ply height
P_WL=80;			// ply length & width

// trim ring
TR_H=3;			// trim ring height
TR_OD=F_D;		// trim ring OD
TR_ID=N_D+0.5;	// trim ring ID
TR_CH=01;		// trim ring chamfers
TR_HD=4.3;		// holes ID
TR_CS_D=7.3;	// countersink ID
TR_CS_H=1.5;	// countersink height (from bottom)


module trim_ring(){
	module pos(){
		cylinder(d=TR_OD, h=TR_H-TR_CH);  // od
		translate([0,0,TR_H-TR_CH]) cylinder(d1=TR_OD, d2=TR_OD-2*TR_CH, h=TR_CH);  // od chamfer
	}
	module neg(){
		for (i=[0:H_N-1]){ 
			rotate([0,0,i*360/H_N]){
				translate([H_BC/2,0,-0.01]) cylinder(d=TR_HD, h=TR_H+0.02); // hole
				translate([H_BC/2,0,TR_CS_H]) cylinder(d=TR_CS_D, h=TR_H+0.02); // csink
			}
		}
		translate([0,0,-0.01])cylinder(d=TR_ID, h=TR_H+0.02);  // id
		translate([0,0,TR_H-TR_CH])cylinder(d1=TR_ID, d2=TR_ID+2*TR_CH, h=TR_CH+0.01);  // id chamfer
	}
	difference(){
		pos();
		neg();
	}
}

trim_ring();

module mount(){
	module pos(){
		cylinder(d=F_D, h=F_H);
		cylinder(d=N_D, h=N_H+F_H);
	}
	module neg(){
		for (i=[0:H_N-1]){ rotate([0,0,i*360/H_N]) translate([H_BC/2,0,-0.01]) cylinder(d=H_D, h=F_H+0.02); }
		translate([0,0,-0.01])cylinder(d=N_ID, h=F_H+N_H+0.02);
	}
	difference(){
		pos();
		neg();
	}
}

module rubber(){
	module pos(){
		cylinder(d=F_D, h=R_H);
	}
	module neg(){
		for (i=[0:H_N-1]){ rotate([0,0,i*360/H_N]) translate([H_BC/2,0,-0.01]) cylinder(d=H_D, h=R_H+0.02); }
		translate([0,0,-0.01]) cylinder(d=N_D, h=R_H+0.02);
	}
	difference(){
		pos();
		neg();
	}
}

module ply(){
	module pos(){
		translate([0,0,P_H/2]) cube([P_WL, P_WL, P_H], center=true);
	}
	module neg(){
		for (i=[0:H_N-1]){ rotate([0,0,i*360/H_N]) translate([H_BC/2,0,-0.01]) cylinder(d=H_D, h=P_H+0.02); }
		translate([0,0,-0.01]) cylinder(d=N_D, h=P_H+0.02);
	}
	difference(){
		pos();
		neg();
	}
}

module stuff(){
	rh = (RUBBER) ? R_H : 0;
	translate([0,0,-2*P_H-rh-F_H]) mount();
	if (RUBBER) translate([0,0,-2*P_H-rh]) rubber();
	translate([0,0,-2*P_H]) ply();
	translate([0,0,-P_H]) ply();
}

if (DEBUG) #stuff();
