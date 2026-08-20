/* 
button panel
*/

$fn=100;

// common features
include <threads.scad>;

// config params:
NZ_D=0.4;						// nozzle dia
NZ_H=0.25;						// nozzle height
DEBUG=0;							// debug mode (show led)
LED_5MM=1;						// 5MM LED option (else 8mm)
//
F_L=LED_5MM?62:65;			// face length
F_W=25;							// face width
F_H=2;							// face height
F_CA=30;							// face chamfer angle (from vertical)
F_CH=1;							// face chamfer
//
B_H=4;							// back height
W_T=NZ_D*4;						// back walls thickness
//
S_D=3.5;							// screw hole dia
S_Y=5;							// screw hole offset from edge
//
PB_D=12.3;						// pushbutton hole dia
PB_CH=NZ_H*2;					// pushbutton hole chamfer height
PB_DY=LED_5MM?14:15;			// pushbutton delta Y (also led)
//
LED_D=LED_5MM?5:8;			// LED diameter
LED_DC=0.2;						// LED diameter clearance
LED_SD=LED_5MM?6:9.25;		// LED skirt diameter
LED_SH=LED_5MM?1:2;			// LED skirt height
LED_H=LED_5MM?8:11;			// LED height (mounted flush)
LED_CA=F_CA;					// LED countersink angle (from vertical)
LED_CH=F_CH;					// LED countersink height (depth)
LED_FH=LED_5MM?1:2;			// LED face height (protrusion)
//
THD_D=LED_5MM?9:12;			// thread dia
THD_P=LED_5MM?1.5:2;			// thread pitch
THD_A=45;						// thread angle
THD_H=LED_5MM?5:6;			// thread height
THD_CL=0;						// thread clearance
THD_OD=THD_D+2*W_T;			// thread outer barrel

// derived params:
y0 = PB_DY;  // pb & led locs
z0 = -F_H-0.01;  // bottom face
z1 = LED_H-F_H-LED_FH-LED_SH+THD_H;  // top of led socket
h0 = F_H+B_H+0.02;  // front & back thickness
h1 = z1+F_H+0.02;  // front & socket thickness

// faceplate
module faceplate(){
	r1 = F_W/2;
	dy = F_L/2-r1;
	dz = F_H-F_CH;
	dr = F_CH*tan(F_CA);
	r2 = r1-dr;
	rotate([0,180,0]){
		hull(){
			// bottom
			translate([0,dy,0]) cylinder(r=r1, h=dz);
			translate([0,-dy,0]) cylinder(r=r1, h=dz);
			// top chamfer
			translate([0,dy,dz]) cylinder(r1=r1, r2=r2, h=F_CH);
			translate([0,-dy,dz]) cylinder(r1=r1, r2=r2, h=F_CH);
		}
	}
}

module back(){
	d = PB_D+W_T*2;
	cylinder(d=THD_OD, h=z1);  // led
	hull(){
		translate([0,-y0,0]) cylinder(d=d, h=B_H);
		translate([0,y0,0]) cylinder(d=d, h=B_H);
	}
}
	
	
module screw_holes(){
	y = F_L/2-S_Y;
	translate([0,y,z0]) cylinder(d=S_D, h=h0);
	translate([0,-y,z0]) cylinder(d=S_D, h=h0);
}

module pb_hole(){
	d1 = PB_D+PB_CH*2;
	cylinder(d1=d1, d2=PB_D, h=PB_CH);
	cylinder(d=PB_D, h=h0);
}

module pb_holes(){
	translate([0,-y0,z0]) pb_hole();
	translate([0,y0,z0]) pb_hole();
}

module led_hole(){
	d2 = LED_D+LED_DC;
	d1 = d2+2*LED_CH*tan(LED_CA);
	translate([0,0,z0]) cylinder(d1=d1, d2=d2, h=LED_CH+0.01);  // csink
	translate([0,0,-B_H-0.01]) cylinder(d=d2, h=h1);  // thru hole
	translate([0,0,z1-THD_H]) threads(a=THD_A, d=THD_D, p=THD_P, h=THD_H+0.01, cl=THD_CL, int=true, b=0, t=1, debug=false);
}

module button_panel(){
	difference(){
		union(){ faceplate(); back(); }
		screw_holes();
		pb_holes();
		led_hole();
	}
}

button_panel();

module led(x=0, y=0){
	translate([x,y,0]){
		cylinder(d=LED_SD, h=LED_SH);
		cylinder(d=LED_D, h=LED_H-LED_D/2);
		translate([0,0,LED_H-LED_D/2]) sphere(d=LED_D);
	}
}

if (DEBUG){
	translate([0,0,LED_H-F_H-LED_FH]) rotate([180,0,0]) #led();
}
