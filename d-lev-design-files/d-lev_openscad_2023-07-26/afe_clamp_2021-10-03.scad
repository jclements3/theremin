/* 
AFE clamp
*/

$fn=100;

// config params:
NZ_D=0.4;				// nozzle dia
NZ_H=0.25;				// nozzle height
VERT=0;					// vertical/horizontal build switch
//
W0=(VERT)?60:90;		// basic width
L0=(VERT)?90:60;		// basic length
R0=5;						// basic radius
OSZ=NZ_D*2;				// walls oversize
W=W0+OSZ*2;				// width
L=L0+OSZ*2;				// length
R=R0+OSZ;				// radius
H=8;						// height
T=NZ_D*4;				// wall thickness
//
F_W=H+T;					// foot width
F_T=NZ_D*10;			// foot thickness
F_F=3;					// foot fillet
//
H_D=3.5;					// hole dia
H_CD=H;					// hole csink dia

module foot(){
	x = W/2+F_W/2;
	y = F_T/2;
	z = H/2;
	f = F_F*sqrt(2);
	translate([x,y,z]){
		cube([F_W,F_T,H], center=true);  // foot
		translate([T-F_W/2,F_T/2,0]) rotate([0,0,45]) cube([f,f,H], center=true);  // fillet
	}
}

module outer_wall(){
	x = W/2-R;
	y = L-R;
	hull(){
		translate([x,y,0]) cylinder(r=R+T, h=H);
		translate([0,y,0]) cylinder(r=R+T, h=H);
		translate([0,0,0]) cylinder(r=R+T, h=H);
		translate([x,0,0]) cylinder(r=R+T, h=H);
	}
}

module inner_wall(){
	x = W/2-R;
	y = L-R;
	hull(){
		translate([x,y,-0.01]) cylinder(r=R, h=H+0.02);
		translate([0,y,-0.01]) cylinder(r=R, h=H+0.02);
		translate([0,0,-0.01]) cylinder(r=R, h=H+0.02);
		translate([x,0,-0.01]) cylinder(r=R, h=H+0.02);
	}
}

module hole(){
	x = W/2+T+H/2;
	y = F_T/2;
	z = H/2;
	translate([x,y,z]){
		rotate([90,0,0]) cylinder(d=H_D, h=F_T+0.02, center=true);  // hole
		translate([0,y+F_F/2,0]) rotate([90,0,0]) cylinder(d=H_CD, h=F_F, center=true);  // csink
	}
}

module quadrant_cube(){
	cube([W/2+F_W,L+T,H]);
}


module half(){
	intersection(){
		difference(){
			union(){
				outer_wall();
				foot();
				}
			inner_wall();
			hole();
		}
		quadrant_cube();
	}
}

// render
half();
mirror([1,0,0]) half();
