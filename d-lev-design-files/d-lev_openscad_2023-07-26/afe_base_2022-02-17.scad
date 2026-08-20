/* 
AFE clamp base
*/

$fn=100;

// config params:
NZ_D=0.4;				// nozzle dia
NZ_H=0.25;				// nozzle height
VERT=1;					// vertical/horizontal build switch
TALL=0;					// tall AFE box build switch (0=pitch, 1=volume)
JIG=0;					// 0=normal; 1=3D jig; 2=2D jig
//
W0=(VERT)?60:90;		// basic width
L0=(TALL)?110:100;	// basic length
R0=5;						// basic radius
OSZ=NZ_D*2;				// walls oversize
W=W0+OSZ*2;				// box width
L=L0+8*NZ_H;			// box length
R=R0+OSZ;				// box radius
H=8;						// height
T=NZ_D*4;				// wall thickness
//
F_OSZ=NZ_D;				// foot oversize
F_L=H;					// foot length
F_W=F_L+T;				// foot width
F_T=NZ_D*10;			// foot thickness
//
H_D=3.5;					// hole dia
//
B_WT=NZ_D*4;			// base wall thickness
B_H=NZ_H*12;			// base height (above 0)
B_T=NZ_H*6;				// base thickness (below 0)
//
S=(TALL)?75:65;		// separation distance
//
J_H=NZ_H*12;					// jig height
J_W=W+2*F_W+F_OSZ+2*B_WT;	// jig width
J_L=S+F_L+F_OSZ+2*B_WT;		// jig length
J_X=23;							// jig x offset (box side to edge)
J_Y=25;							// jig y offset (box end to edge)
J_GL=NZ_D*4;					// jig guide length (thickness)
J_GH=J_H+NZ_H*12;				// jig guide height (from zero)

module base(){
	w = W/2+F_W+F_OSZ/2+B_WT;
	l = F_L+F_OSZ+2*B_WT;
	h = B_T+B_H;
	translate([w/2,0,h/2-B_T]) cube([w,l,h], center=true);
}

module foot(){
	x = W/2+F_W/2;
	y = 0;
	z = F_T/2;
	translate([x,y,z]){
		cube([F_W+F_OSZ,F_L+F_OSZ,F_T], center=true);  // foot
	}
}

module wall(){
	x = W/2-R;
	y = R;
	h = F_L+F_OSZ+2*B_WT+0.01;
	hull(){
		translate([0,0,y]){
			rotate([90,0,0]){
				translate([0,0,0]) cylinder(r=R, h=h, center=true);
				translate([x,0,0]) cylinder(r=R, h=h, center=true);
			}
		}
	}
}

module hole(){
	x = W/2+T+H/2;
	translate([x,0,-B_T/2]) cylinder(d=H_D, h=B_T+0.02, center=true);
}

module quarter(){
	difference(){
		base();
		wall();
		foot();
		hole();
	}
}

module half(){
	quarter();
	mirror([1,0,0]) quarter();
}

module connector(){
	y = S/2;
	l = F_L+F_OSZ+2*B_WT;
	h = B_T;
	hull(){
		translate([0,y,-h/2]) cylinder(d=l, h=h, center=true);
		translate([0,-y,-h/2]) cylinder(d=l, h=h, center=true);
	}
}
	
module afe_base(){
	translate([0,-S/2,0]) half();
	translate([0,S/2,0]) half();
	connector();
}

module jig(){
	l = L/2+J_L/2+J_Y+10;
	y = l/2-J_L/2-10;
	y2 = y+l/2+J_GL/2;
	difference(){
		union(){
			translate([0,y,J_H/2]) cube([W+J_X*2,l,J_H], center=true);
			if(JIG==1) translate([0,y2,J_GH/2]) cube([W+J_X*2,J_GL,J_GH], center=true);
		}
		translate([0,0,J_H/2]) cube([J_W+0.01,J_L+0.01,J_H+0.01], center=true);
	}
}
	

// render
if(JIG==2) projection(cut=false) jig();
else if(JIG) jig();
else afe_base();

