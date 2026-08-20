/* 
antenna bolt, nut, knob, (split) ring, spacer
*/

$fn=100;

// common features
include <threads.scad>

// config params:
NZ_D=0.4;				// nozzle dia
NZ_H=0.25;				// nozzle height

// build options:
BOLT=1;					// bolt enable
KNOB=1;					// knob enable
RING=1;					// split ring enable
NUT=1;					// nut enable
SPACER=0;				// spacer enable

// debug options:
CUT=0;					// cutaway view
ASM=1;					// assembly view
THD_DBG=0;				// thread debug mode

// general:
P_OD=15.9;				// pipe OD
P_CL=0.5;				// pipe OD clearance
ID=P_OD+P_CL;			// default ID
CH=1;						// default chamfer height
CA=30;					// default chamfer angles (other than 45 deg)

// knob:
K_THD_D=28;				// knob thread diameter
K_THD_P=2;				// knob thread pitch
K_THD_A=30;				// knob_thread angle
K_THD_ID=K_THD_D-K_THD_P/tan(K_THD_A); // knob thread ID (approx)
K_THD_CL=0;				// knob thread clearance
K_OD=K_THD_D+8;		// knob OD
K_H=15;					// knob height
K_FH=3;					// knob face height (thickness)
K_ID=ID;					// knob ID (hole)
K_CH=7.5;				// knob ID chamfer height
K_CA=45;					// knob ID chamfer angle
K_NUBS=7;				// knob nubs
K_NUB_W=7;				// knob nub width
K_NUB_H=1.5;			// knob nub height (off diameter)
K_NUB_R=1;				// knob nub radius
K_NUB_A=45;				// knob nub angle

// nut:
N_THD_D=25;				// nut thread diameter
N_THD_P=3;				// nut thread pitch
N_THD_A=45;				// nut thread angle
N_THD_ID=N_THD_D-N_THD_P/tan(N_THD_A); // nut thread ID (approx)
N_THD_CL=-0.05;		// nut thread clearance
N_OD=N_THD_D+6;		// nut OD
N_SD=K_OD+4;			// nut skirt OD
N_SH=2;					// nut skirt height
N_H=15;					// nut height
N_FH=NZ_H*8;			// nut face height (thickness)
N_ID=3.5;				// nut ID (hole)
N_CH=N_THD_P;			// nut chamfer height
N_CA=45;					// nut chamfer angle
N_FINS=6;				// nut fins
N_FIN_W=NZ_D*12;		// nut fin width

// split ring:
R_A=15;					// ring angle
R_SD=1;					// ring spring factor (enlarge dia)
R_ID=(ASM)?ID:ID+R_SD;	// ring ID
R_OD=(ASM)?K_THD_ID:K_THD_ID+R_SD;	// ring OD (max)
R_H=10;					// ring height
R_SW=(ASM)?3:3+R_SD*PI;	// ring split width

// bolt:
B_KH=K_H+1.5;			// bolt knob side height
B_NH=N_H+8.5;			// bolt nut side height
B_FH=2;					// bolt face height
B_FA=45;					// bolt face angle
B_RCH=R_H-2;			// bolt ring chamfer height
B_LN=2;					// bolt locators
B_LD=5;					// bolt locator diameter
B_LH=B_NH-N_H;			// bolt locator height

// spacer:
S_ID=N_THD_D+1;		// spacer ID
S_H=0;					// spacer height


module bolt() {
	module positive(){
		h1 = tan(B_FA)*(K_OD-K_THD_ID)/2;  // face angle height
		h2 = B_NH-N_H;  // nut height from face
		h3 = (N_THD_D-N_THD_ID)/2;  // nut thread blend fillet height
		//
		threads(a=K_THD_A, d=K_THD_D, p=K_THD_P, h=B_KH, cl=0, int=false, b=1, t=0, debug=THD_DBG);  // knob thread
		translate([0,0,B_KH]) {  // @ back face
			threads(a=N_THD_A, d=N_THD_D, p=N_THD_P, h=B_NH, cl=0, int=false, b=0, t=1, debug=THD_DBG);  // nut thread
			translate([0,0,-B_FH]){
				cylinder(d=K_OD, h=B_FH);  // face
				translate([0,0,-h1]) cylinder(d1=K_THD_ID, d2=K_OD, h=h1);  // face angle
			}
			cylinder(d1=N_THD_D+2*CH, d2=N_THD_D, h=CH);  // back face blend fillet (45 deg)
			cylinder(d=N_THD_D, h=h2);  // shoulder od
			for (i=[0:B_LN-1]){
				rotate([0,0,i*360/B_LN]) {
					translate([N_THD_D/2,0,0]) {  // locator
						cylinder(d=B_LD, h=B_LH-B_LD/2);
						translate([0,0,B_LH-B_LD/2]) sphere(d=B_LD);
					}
				}
			}
			translate([0,0,h2]) cylinder(d1=N_THD_D, d2=N_THD_ID, h=h3);  // nut thread blend fillet (45 deg)
		}
	}
	module negative(){
		d1 = ID+2*B_RCH*tan(R_A); // split ring chamfer major dia
		translate([0,0,-0.01]) cylinder(d1=d1, d2=ID, h=B_RCH);  // split ring chamfer
		cylinder(d=ID, h=B_NH+B_KH+0.01);  // main id hole
	}
	difference(){
		positive();
		negative();
	}
}

module nubs(n, d, w, l, h, r, a){
	module nub(){
		dx = w/2-r;
		dy = l/2-h/tan(a)-r*cos(a);
		z = h-r;
		depth = d/2;
		//
		rotate([90,0,90]){
			hull(){
				intersection(){
					translate([0,0,-d/2]) rotate([90,0,0]) cylinder(d=d, h=l, center=true);
					translate([0,0,-depth/2]) cube([w,l,depth], center=true);
				}
				translate([dx,dy,z]) sphere(r);
				translate([-dx,dy,z]) sphere(r);
				translate([-dx,-dy,z]) sphere(r);
				translate([dx,-dy,z]) sphere(r);
			}
		}
	}
	for (i=[0:n-1]){
		rotate([0,0,i*360/n]) translate([d/2,0,0]) nub();
	}
}

module knob(){
	nub_l = K_H-2*CH;
	module positive(){
		d1 = K_OD-2*CH;  // big outer chamfers minor dia (45 deg)
		d2 = d1+K_H;  // big outer chamfers major dia (45 deg)
		//
		intersection(){
			union(){  // body & nubs
				cylinder(d=K_OD, h=K_H);
				translate([0,0,K_H/2]) nubs(n=K_NUBS, d=K_OD, w=K_NUB_W, l=nub_l, h=K_NUB_H, r=K_NUB_R, a=K_NUB_A);
			}
			union(){  // big outer chamfers
				cylinder(d1=d1, d2=d2, h=K_H/2);
				translate([0,0,K_H/2]) cylinder(d1=d2, d2=d1, h=K_H/2);
			}
		}
	}
	module negative(){
		d3 = K_ID+2*CH*tan(CA);  // bottom hole chamfer major dia
		h1 = tan(K_CA)*(K_OD-K_ID)/2;  // top chamfer height
		//
		translate([0,0,K_FH]) threads(a=K_THD_A, d=K_THD_D, p=K_THD_P, h=K_H-K_FH+0.01, cl=K_THD_CL, int=true, b=-1, t=1, debug=THD_DBG);
		translate([0,0,-0.01]) {
			cylinder(d=K_ID, h=K_FH+0.02);  // bottom hole
			cylinder(d1=d3, d2=K_ID, h=CH+0.01);  // bottom hole chamfer
		}
		translate([0,0,K_H-K_CH]) {
			cylinder(d1=K_ID, d2=K_OD, h=h1+0.01);  // top chamfer
		}
	}
	difference(){
		positive();
		negative();
	}
}

module fins(n, d, w, h, ch){
	intersection(){
		for (i=[0:n-1]){
			rotate([0,0,i*360/n]) translate([0,-w/2,0]) cube([d/2,w,h]);
		}
		union(){
			cylinder(d1=d-2*ch, d2=d, h=ch);  // bottom chamfer
			translate([0,0,ch]) cylinder(d=d, h=h-ch);  // fins OD
		}
	}
}

module nut(){
	nub_l = N_H-2*CH;
	module positive(){
		h1 = (N_SD-N_OD)/2;
		cylinder(d=N_OD, h=N_H);  // body
		fins(N_FINS, N_SD, N_FIN_W, N_H-N_FH, CH);  // fins
		translate([0,0,N_H-B_FH]) {
			cylinder(d=N_SD, h=B_FH);  // skirt
			translate([0,0,-h1]) cylinder(d1=N_OD, d2=N_SD, h=h1);  // skirt angle
		}
	}
	module negative(){
		d3 = N_ID+2*CH*tan(CA);  // bottom hole chamfer major dia
		h1 = tan(N_CA)*(N_OD-N_ID)/2;  // top chamfer height
		//
		translate([0,0,N_FH]) threads(a=N_THD_A, d=N_THD_D, p=N_THD_P, h=N_H-N_FH+0.01, cl=N_THD_CL, int=true, b=-1, t=1, debug=THD_DBG);
		translate([0,0,-0.01]) {
			cylinder(d=N_ID, h=N_FH+0.02);  // bottom hole
		}
		translate([0,0,N_H-N_CH]) {
			cylinder(d1=N_ID, d2=N_OD, h=h1+0.01);  // top chamfer
		}
	}
	difference(){
		positive();
		negative();
	}
}

module split_ring(){
	d1 = R_ID+2*R_H*tan(R_A);  // od chamfer major dia
	d2 = R_ID+2*CH*tan(CA);  // id chamfer major dia
	//
	difference(){
		intersection(){
			cylinder(d=R_OD, h=R_H);  // od vertical
			cylinder(d1=d1, d2=R_ID, h=R_H);  // od angled
		}
		translate([0,0,-0.01]) {
			cylinder(d=R_ID, h=R_H+0.02);  // id
			cylinder(d1=d2, d2=R_ID, h=CH+0.01);  // id chamfer
			translate([0,-R_SW/2,0]) cube([R_OD/2,R_SW,R_H+0.02]);  // split
		}
	}
}
	
module spacer(){
	difference(){
		union(){
			cylinder(d=N_OD, h=S_H);  // od
			cylinder(d=K_OD, h=B_FH);  // face
			translate([0,0,B_FH]) cylinder(d1=K_OD, d2=N_OD, h=(K_OD-N_OD)/2);  // face angle
		}
		translate([0,0,-0.01]) cylinder(d=S_ID, h=S_H+0.02);  // id
	}
}

// render
difference(){
	c2c = K_OD+10;
	z0 = B_KH+B_NH;
	z1 = z0+N_FH;
	z2 = z1-N_H;
	z3 = z2-S_H;
	//
	if (ASM) {
		union(){
			if (BOLT) bolt();
			if (KNOB) translate([0,0,-K_FH-1.2]) rotate([0,0,180]) knob();
			if (RING) translate([0,0,-1.1]) split_ring();
			if (NUT) translate([0,0,z1+0.2]) rotate([180,0,0]) nut();
		}  if (SPACER) translate([0,0,z3]) spacer();
	}
	else {
		union(){
			if (BOLT) bolt();
			if (KNOB) translate([BOLT*c2c,0,0]) knob();
			if (RING) translate([BOLT*-c2c,0,0]) split_ring();
			if (NUT) translate([BOLT*-c2c,0,0]) nut();
			if (SPACER) translate([BOLT*-c2c,0,0]) spacer();
		}
	}
	if (CUT){
		translate([-100,-K_OD,-10]) cube([200,K_OD,100]);
	}
	echo("minimum mounting wall thickness", z3-B_KH);
}
