/* 
AFE box back & front
*/

$fn=100;

// common features
include <d-lev_common.scad>;

// config params:
NZ_D=0.4;				// nozzle dia
NZ_H=0.25;				// nozzle height
BACK=1;					// back/front build switch
//
W_W=60;					// wall width
W_L=90;					// wall length
W_H=7;					// wall height
W_R=5;					// wall radius
W_T=6*NZ_D;				// wall thickness
W_F=1;					// wall inner fillet
W_C=0.5;					// wall chamfer
//
F_H=NZ_H*4;				// face height
F_CL=NZ_D*3;			// face clearance to edge
F_R=W_R+F_CL;			// face radius
//
N_H=1.2;					// nib height
N_F=1.0;					// nib flat
N_T=5;					// nib taper
N_Z=W_H/2;				// nib z
//
P_H=10;					// pipe height
P_T=4*NZ_D;				// pipe wall thickness
P_OD=34.25;				// pipe OD (35 minus some tolerance)
P_ID=P_OD-2*P_T;		// pipe ID
P_C=W_C;					// pipe top chamfer
P_F=W_F;					// pipe inner fillet
P_Y=W_L/2-W_W/2;		// pipe y offset
//
H_D=(BACK)?16:8;		// hole diameter
H_TD=20;					// hole top diameter
H_H=F_H;					// hole height (above face)
H_Y=20-W_L/2;			// hole y offset

// render it all
difference(){
	union(){
		face();
		wall();
		reinforce();
		pipe();
	}
	translate([0,H_Y,0]) cylinder(d=H_D, h=H_H*4, center=true);  // offset hole
}


module nibs(){
	x = W_W/2+0.01;
	y = W_L/2+0.01;
	xr = x-W_R;
	yr = y-W_R;
	translate([0,-y,N_Z]) nib(l=xr*2, h=N_H, f=N_F, t=N_T);
	rotate([0,0,180]) translate([0,-y,N_Z]) nib(l=xr*2, h=N_H, f=N_F, t=N_T);
	rotate([0,0,90]) translate([0,-x,N_Z]) nib(l=yr*2, h=N_H, f=N_F, t=N_T);
	rotate([0,0,-90]) translate([0,-x,N_Z]) nib(l=yr*2, h=N_H, f=N_F, t=N_T);
}

module face(){
	x = W_W/2+F_CL-F_R+0.01;
	y = W_L/2+F_CL-F_R+0.01;
	hull(){
		translate([x,y,-F_H]) cylinder(r=F_R, h=F_H);
		translate([-x,y,-F_H]) cylinder(r=F_R, h=F_H);
		translate([-x,-y,-F_H]) cylinder(r=F_R, h=F_H);
		translate([x,-y,-F_H]) cylinder(r=F_R, h=F_H);
	}
}

module wall(){
	x = W_W/2-W_R;
	y = W_L/2-W_R;
	h = W_H-W_C;
	r1 = W_R-W_T;
	r2 = r1-W_F;
	r3 = W_R-W_C;
	difference(){
		hull(){
			translate([x,y,0]) cylinder(r=W_R, h=h);
			translate([-x,y,0]) cylinder(r=W_R, h=h);
			translate([-x,-y,0]) cylinder(r=W_R, h=h);
			translate([x,-y,0]) cylinder(r=W_R, h=h);
			//
			translate([x,y,h]) cylinder(r1=W_R, r2=r3, h=W_C);
			translate([-x,y,h]) cylinder(r1=W_R, r2=r3, h=W_C);
			translate([-x,-y,h]) cylinder(r1=W_R, r2=r3, h=W_C);
			translate([x,-y,h]) cylinder(r1=W_R, r2=r3, h=W_C);
		}
		hull(){
			translate([x,y,0]) cylinder(r1=r2, r2=r1, h=W_F);
			translate([-x,y,0]) cylinder(r1=r2, r2=r1, h=W_F);
			translate([-x,-y,0]) cylinder(r1=r2, r2=r1, h=W_F);
			translate([x,-y,0]) cylinder(r1=r2, r2=r1, h=W_F);
			//
			translate([x,y,W_F]) cylinder(r=r1, h=W_H);
			translate([-x,y,W_F]) cylinder(r=r1, h=W_H);
			translate([-x,-y,W_F]) cylinder(r=r1, h=W_H);
			translate([x,-y,W_F]) cylinder(r=r1, h=W_H);
		}
		nibs();
	}
}

module reinforce(){
	translate([0,H_Y,0]) cylinder(d1=H_TD+2*H_H, d2=H_TD, h=H_H, center=false);
}

module pipe(){
	translate([0,P_Y,0]) {
		difference(){
			union() {
				cylinder(d=P_OD, h=P_H-P_C, center=false);
				translate([0,0,P_H-P_C]) cylinder(d1=P_OD, d2=P_OD-2*P_C, h=P_C, center=false);
			}
			cylinder(d1=P_ID-2*P_F, d2=P_ID, h=P_F+0.01, center=false);
			translate([0,0,P_F]) cylinder(d=P_ID, h=P_H+0.01, center=false);
		}
	}
}

