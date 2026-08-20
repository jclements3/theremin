/* 
I/O panel
*/

$fn=100;

// config params:
NZ_D=0.4;						// nozzle dia
NZ_H=0.25;						// nozzle height
DEBUG=0;							// debug mode
ROWS2=0;							// 1=2x3; 0=1x6
TOSLINK=1;						// 1=keystone
//
F_L=(ROWS2)?70:45;			// face length
F_W=(ROWS2)?100:180;			// face width
F_H=5;							// face height
F_R=6;							// face radius
F_CA=30;							// face chamfer angle (from vertical)
F_CH=1;							// face chamfer
// 
W_CL=(ROWS2)?10:10;			// wall clearance
W_L=F_L-W_CL*2;				// wall width
W_W=F_W-W_CL*2;				// wall width
W_H=10;							// wall height (total)
W_R=F_R;							// wall radius
W_F=1;							// wall fillet
//
F_DX=27;							// features dx
F_DY=25;							// features dy
//
S_D=3.5;							// screw hole dia
S_XY=F_R;						// screw X&Y offset from edge

// derived params:
x0 = F_W/2-F_R;
y0 = F_L/2-F_R;
z0 = -F_H-0.01;  // bottom face
h0 = F_H+W_H+0.02;

// faceplate
module faceplate(){
	z = F_H-F_CH;
	r = F_R-F_CH*tan(F_CA);
	rotate([0,180,0]){
		hull(){
			// bottom
			translate([x0,y0,0]) cylinder(r=F_R, h=z);
			translate([-x0,y0,0]) cylinder(r=F_R, h=z);
			translate([-x0,-y0,0]) cylinder(r=F_R, h=z);
			translate([x0,-y0,0]) cylinder(r=F_R, h=z);
			// top chamfer
			translate([x0,y0,z]) cylinder(r1=F_R, r2=r, h=F_CH);
			translate([-x0,y0,z]) cylinder(r1=F_R, r2=r, h=F_CH);
			translate([-x0,-y0,z]) cylinder(r1=F_R, r2=r, h=F_CH);
			translate([x0,-y0,z]) cylinder(r1=F_R, r2=r, h=F_CH);
		}
	}
}

module walls(){
	x0 = W_W/2-W_R;
	y0 = W_L/2-W_R;
	h = W_H-F_H;
	r1 = W_R+W_F;
	union(){
		hull(){  // fillet
			translate([x0,y0,0]) cylinder(r=W_R, h=h);
			translate([-x0,y0,0]) cylinder(r=W_R, h=h);
			translate([-x0,-y0,0]) cylinder(r=W_R, h=h);
			translate([x0,-y0,0]) cylinder(r=W_R, h=h);
		}
		hull(){ // walls
			translate([x0,y0,0]) cylinder(r1=r1, r2=W_R, h=W_F);
			translate([-x0,y0,0]) cylinder(r1=r1, r2=W_R, h=W_F);
			translate([-x0,-y0,0]) cylinder(r1=r1, r2=W_R, h=W_F);
			translate([x0,-y0,0]) cylinder(r1=r1, r2=W_R, h=W_F);
		}
	}
}

module screw_holes(){
	translate([x0,y0,z0]) cylinder(d=S_D, h=h0);
	translate([-x0,y0,z0]) cylinder(d=S_D, h=h0);
	translate([-x0,-y0,z0]) cylinder(d=S_D, h=h0);
	translate([x0,-y0,z0]) cylinder(d=S_D, h=h0);
	if(!ROWS2){
		translate([0,y0,z0]) cylinder(d=S_D, h=h0);
		translate([0,-y0,z0]) cylinder(d=S_D, h=h0);
	}
}

module keystone(){
	//  params:
	FACE_H=NZ_H*8;			// face height (z)
	HOLE_W=15;				// hole width (x)
	HOLE_L=16.5;			// hole length (y)
	HOLE_CH=NZ_D*2;		// hole top chamfer (y)
	SPRING_L=19;			// spring length (y)
	WALL_H=10;				// outer walls height (z)
	NOTCH_H=8.25;			// locking notch height (z)
	NOTCH_CL=NZ_D*4;		// locking notch clearance (y)

	module keyhole_poly(){
		x0 = -HOLE_L/2;
		x1 = x0-NOTCH_CL;
		x2 = x0-HOLE_CH;
		x3 = x0+SPRING_L;
		x4 = x3+HOLE_CH;
		x5 = x3+NOTCH_CL;
		x6 = -x0;
		//
		y0 = 0;
		y1 = FACE_H;
		y2 = NOTCH_H;
		y3 = WALL_H;
		y4 = y3-HOLE_CH;
		y5 = x5-x6;
		y_0 = y0-0.01;
		y_3 = y3+0.01;
		hole_poly_points = [[x0,y_0],[x6,y_0],[x5,y5],[x5,y2],[x3,y2],[x3,y4],[x4,y_3],[x2,y_3],[x0,y4],[x0,y2],[x1,y2],[x1,y1],[x0,y1]];
		hole_poly_paths = [[0,1,2,3,4,5,6,7,8,9,10,11,12]];
		polygon(hole_poly_points, hole_poly_paths, 10);
	}

	// do hole
	translate([0,HOLE_W/2,0])
	rotate([90,0,0])
	linear_extrude(height=HOLE_W, center=false) { keyhole_poly(); }
	
}

module din(view_f){
	DIN_D=15.5;						// din dia
	DIN_SD=3.5;						// DIN screw hole dia
	DIN_SX=22.2;					// DIN screws distance
	DIN_SA=-33.3;					// DIN screws angle
	// debug view
	if (view_f) {
		d0 = 19;
		d1 = 6.8;
		x0 = DIN_SX/2;
		h0 = 1.3;
		# difference(){
			rotate([0,0,DIN_SA]){
				hull(){
					translate([0,0,z0-h0]) cylinder(d=d0, h=h0);
					translate([x0,0,z0-h0]) cylinder(d=d1, h=h0);
					translate([-x0,0,z0-h0]) cylinder(d=d1, h=h0);
				}
			}
			translate([0,0,-h0-0.01]) din(false);
		}
	}
	// holes
	else {
		// holes
		x0 = DIN_SX/2;
		rotate([0,0,DIN_SA]){
			translate([0,0,z0]) cylinder(d=DIN_D, h=h0);
			translate([x0,0,z0]) cylinder(d=DIN_SD, h=h0);
			translate([-x0,0,z0]) cylinder(d=DIN_SD, h=h0);
		}
	}
}

module rocker(){
	ROCKER_L=12.7;					// rocker switch hole length
	ROCKER_LC=2;					// rocker switch length clearance
	ROCKER_W=19.05;				// rocker switch hole width
	ROCKER_WC=5;					// rocker switch width clearance
	ROCKER_FH=NZ_H*8;				// rocker switch face height
	//
	w0 = ROCKER_W;
	w1 = w0+ROCKER_WC;
	l0 = ROCKER_L;
	l1 = l0+ROCKER_LC;
	z1 = z0+ROCKER_FH;
	h0 = ROCKER_FH+0.01;
	h1 = F_H+W_H-ROCKER_FH+0.01;
	translate([-w0/2,-l0/2,z0]) cube([w0,l0,h0], center=false);  // hole
	translate([-w1/2,-l1/2,z1]) cube([w1,l1,h1], center=false);  // clearance
}

module headphone_jack(){
	ID=9.75;	// thru hole dia
	CL=22;	// back clearance dia
	FH=4;		// face height (thickness)
	translate([0,0,z0]) cylinder(d=ID, h=h0);  // hole
	translate([0,0,z0+FH]) cylinder(d1=CL, d2=CL, h=h0);  // clearance
}
	
module aviation(){
	ID=16;	// thru hole dia
	FW=14.8;	// flats width
	CL=22;	// back clearance dia
	FH=4;		// face height (thickness)
	translate([0,0,z0]) {
		intersection(){
			cylinder(d=ID, h=h0, center=true);  // hole
			cube ([FW,ID,ID], center=true);  // hole
		}
	translate([0,0,FH]) cylinder(d=CL, h=h0);  // clearance
	}
}

module io_panel(){
	difference(){
		union() { 
			faceplate(); 
			walls(); 
		}
		screw_holes();
		if (ROWS2){
			translate([-F_DX,-F_DY/2,0]) rocker();
			translate([-F_DX, F_DY/2,-F_H]) keystone();
			translate([F_DX,F_DY/2,0]) {
				din(false);
				din(DEBUG);
			}
			translate([0,-F_DY/2,0]) headphone_jack();

			if (TOSLINK){ translate([F_DX,-F_DY/2,-F_H]) rotate([0,0,180]) keystone(); }
			else { translate([F_DX,-F_DY/2,0]) headphone_jack(); }
			translate([0, F_DY/2,0]) aviation();
		}
		else {
			translate([-F_DX/2,0,0]) rocker();
			translate([-F_DX*3/2,0,-F_H]) keystone();
			translate([-F_DX*5/2,0,0]) {
				din(false);
				din(DEBUG);
			}
			translate([F_DX*3/2,0,0]) headphone_jack();
			if (TOSLINK){ translate([F_DX*5/2,0,-F_H]) rotate([0,0,180]) keystone(); }
			else { translate([F_DX*5/2,0,0]) headphone_jack(); }
			translate([F_DX/2,0,0]) aviation();
		}
	}
}

io_panel();

