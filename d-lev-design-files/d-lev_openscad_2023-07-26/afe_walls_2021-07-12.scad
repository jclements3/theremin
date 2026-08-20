/* 
Antenna walls
*/

$fn=100;

// common features
include <d-lev_common.scad>;

// config params:
NZ_D=0.4;				// nozzle dia
NZ_H=0.25;				// nozzle height
TALL=0;					// tall/short build switch
//
W=90;						// width
L=60;						// length
R=5;						// radius
H=(TALL)?110:100;		// height
T=NZ_D*2;				// thickness
//
N_H=1.2;					// nib height
N_F=1;					// nib flat
N_T=5;					// nib taper
N_Z=3.5;					// nib z
//
C_NW=5;					// corrugations (width)
C_NL=3;					// corrugations (length)
C_H=2;					// corrugation height (depth)
C_W=R;					// corrugation width (min)
C_L=H-(C_H+8)*2;		// corrugation length (min)


// render
difference(){
	union(){
		walls();
		corrugations(o=true);
		translate([0,0,N_Z]) nibs(N_F);  // bottom nib
		translate([0,0,H-N_Z]) nibs(N_F);  // top nib
	}
	corrugations(o=false);
}


module nibs(f=1){
	x = W/2;
	y = L/2;
	xn = x-R;
	yn = y-R;
	h = N_H;
	translate([0,-y,0]) nib(l=xn*2, h=h, f=f, t=N_T);
	rotate([0,0,180]) translate([0,-y,0]) nib(l=xn*2, h=h, f=f, t=N_T);
	rotate([0,0,90]) translate([0,-x,0]) nib(l=yn*2, h=h, f=f, t=N_T);
	rotate([0,0,-90]) translate([0,-x,0]) nib(l=yn*2, h=h, f=f, t=N_T);
}

module walls(){
	x = W/2-R;
	y = L/2-R;
	difference(){
		hull(){ // outer wall
			translate([x,y,0]) cylinder(r=R+T, h=H);
			translate([-x,y,0]) cylinder(r=R+T, h=H);
			translate([-x,-y,0]) cylinder(r=R+T, h=H);
			translate([x,-y,0]) cylinder(r=R+T, h=H);
		}
		hull(){ // inner wall
			translate([x,y,-0.01]) cylinder(r=R, h=H+0.02);
			translate([-x,y,-0.01]) cylinder(r=R, h=H+0.02);
			translate([-x,-y,-0.01]) cylinder(r=R, h=H+0.02);
			translate([x,-y,-0.01]) cylinder(r=R, h=H+0.02);
		}
	}
}

module corrugations(o=true){
	x = (o) ? W/2 : W/2+T+0.01;
	y = (o) ? L/2 : L/2+T+0.01;
	z = H/2;
	dx = W/(C_NW+1);
	dy = L/(C_NL+1);
	a = T*tan(45/2);
	w = (o) ? C_W+2*a : C_W;
	l = (o) ? C_L+2*a : C_L;
	h = C_H;
	translate([0,-y,z]) corrs(w=w, l=l, h=h, n=C_NW, dx=dx);
	translate([0,y,z]) rotate([0,0,180]) corrs(w=w, l=l, h=h, n=C_NW, dx=dx);
	//
	translate([-x,0,z]) rotate([0,0,-90]) corrs(w=w, l=l, h=h, n=C_NL, dx=dy);
	translate([x,0,z]) rotate([0,0,90]) corrs(w=w, l=l, h=h, n=C_NL, dx=dy);
}

module corrs(w=1, l=1, h=1, n=1, dx=10){
	t = dx*(n-1);
	rotate([-90,0,0]){
		for (i=[0:n-1]){
			translate([i*dx-t/2,0,0]) corr(w=w, l=l, h=h);
		}
	}
}

module corr(w=1, l=1, h=1){
	r2 = w/2;
	y = l/2-r2;
	r1 = r2+h;
	hull(){
		translate([0,y,0]) cylinder(r1=r1, r2=r2, h=h);
		translate([0,-y,0]) cylinder(r1=r1, r2=r2, h=h);
	}
}
