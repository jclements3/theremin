/* 
D-Lev common stuff
*/

// stiffening rib w/ fillets & rounded ends
// [x0,y0,h0] = start pos & height
// [x1,y1,h1] = end pos & height
// t = thickness (width)
// f = fillet height (45 deg)
module rib(x0=0, y0=0, x1=10, y1=0, h0=10, h1=10, t=2, f=2){
	hull(){
		translate([x0,y0,0]) cylinder(d1=t+2*f, d2=t, h=f);
		translate([x1,y1,0]) cylinder(d1=t+2*f, d2=t, h=f);
	}
	hull(){
		translate([x0,y0,0]) cylinder(d=t, h=h0);
		translate([x1,y1,0]) cylinder(d=t, h=h1);
	}
}

// stiffening rib w/ radius & fillets (flat ends)
// [x,y] = center
// r = radius
// a0 = start angle
// a1 = sweep angle
// h = height
// t = thickness (width)
// f = fillet height (45 deg)
module rib_radius(x=0, y=0, r=50, a0=0, a1=90, h=10, t=2, f=2){
	translate([x,y]) rotate([0,0,a0]) rotate_extrude(angle=a1) translate([r,0,0])	projection(){
		rotate([-90,0,0]){
			cylinder(d1=t+2*f, d2=t, h=f);
			cylinder(d=t, h=h);
		}
	}
}

// faceplate with front & back widths
module faceplate(wf=10, wb=10, l=10, h=5, ca=30, ch=1, r=2) {
	dxf = wf/2-r;
	dxb = wb/2-r;
	dy = l/2-r;
	dz = h-ch;
	dr = ch*tan(ca);
	r2 = r-dr;
	hull(){
		// bottom
		translate([dxb,dy,0]) cylinder(r=r, h=dz);
		translate([-dxb,dy,0]) cylinder(r=r, h=dz);
		translate([-dxf,-dy,0]) cylinder(r=r, h=dz);
		translate([dxf,-dy,0]) cylinder(r=r, h=dz);
		// top w/ chamfer
		translate([dxb,dy,dz]) cylinder(r1=r, r2=r2, h=ch);
		translate([-dxb,dy,dz]) cylinder(r1=r, r2=r2, h=ch);
		translate([-dxf,-dy,dz]) cylinder(r1=r, r2=r2, h=ch);
		translate([dxf,-dy,dz]) cylinder(r1=r, r2=r2, h=ch);
	}
}

module tapered_window(w=10, l=5, h=1, ca=30, ch=2, r=2){
	dr = ch*tan(ca);
	dx = w/2-r;
	dy = l/2-r;
	dxt = dx+dr;
	dyt = dy+dr;
	dz = h-ch;
	dh = 0.02;
	hull(){  // thru hole
		translate([dx,dy,0]) cylinder(r=r, h=h);
		translate([-dx,dy,0]) cylinder(r=r, h=h);
		translate([dx,-dy,0]) cylinder(r=r, h=h);
		translate([-dx,-dy,0]) cylinder(r=r, h=h);
	}
	translate([0,0,dz]){
		hull(){
			// window bottom
			translate([dx,dy,0]) cylinder(r=r, h=dh);
			translate([-dx,dy,0]) cylinder(r=r, h=dh);
			translate([-dx,-dy,0]) cylinder(r=r, h=dh);
			translate([dx,-dy,0]) cylinder(r=r, h=dh);
			// window top
			translate([dxt,dyt,ch]) cylinder(r=r, h=dh);
			translate([-dxt,dyt,ch]) cylinder(r=r, h=dh);
			translate([-dxt,-dyt,ch]) cylinder(r=r, h=dh);
			translate([dxt,-dyt,ch]) cylinder(r=r, h=dh);
		}
	}
}
	
// post w/ fillet
module post(d=5, h=10, f=1){
	cylinder(d=d, h=h);  // post
	cylinder(d1=d+2*f, d2=d, h=f);  // fillet
}

// screw hole
// ca = included angle (180 is flat bottom)
// ch = full dia countersink depth
module screw_hole(d=3, cd=6, h=6, ch=3, ca=90){
	dh = (cd/2-d/2)/tan(ca/2);
	translate([0,0,-0.01]) cylinder(d=d, h=h+0.02);  // thru hole
	translate([0,0,h-ch-dh]) cylinder(d1=d, d2=cd, h=dh+0.01);  // screw seat
	translate([0,0,h-ch]) cylinder(d=cd, h=ch+0.01);  // csink hole
}

// 45 degree nib
// l = length
// h = height
// f = flat (truncates height)
// t = taper length
module nib(l=10, h=1, f=1, t=10){
	r = 1;
	x = l/2;
	x1 = x-t;
	y = r;
	y1 = y+f;
	difference(){
		rotate([90,0,90]) linear_extrude(height=l, center=true) polygon(points=[[0,-h],[h,0],[0,h]]);  // nib
		hull(){
			translate([x,y,0]) cylinder(r=r, h=2*h, center=true);
			translate([x1,y1,0]) cylinder(r=r, h=2*h, center=true);
		}
		hull(){
			translate([-x,y,0]) cylinder(r=r, h=2*h, center=true);
			translate([-x1,y1,0]) cylinder(r=r, h=2*h, center=true);
		}
		hull(){
			translate([x1,y1,0]) cylinder(r=r, h=2*h, center=true);
			translate([-x1,y1,0]) cylinder(r=r, h=2*h, center=true);
		}
	}
}

// oval raft to purge bad filament
module raft(x=0, y=0, z=0, w=8, l=2, h=1, a=45){
	translate([x,y,z]){
		rotate([0,0,a]){
			hull(){
				translate([-(w-l)/2,0,0]) cylinder(d=l,h=h);
				cylinder(d=l,h=h);
			}
		}
	}
}


////////////////////
// CODE GRAVEYARD //
////////////////////
/*
// 45 degree nib w/ radius
// r = radius
// a = angle
// h = height
// f = flat (truncates height)
module nib_radius(r=50, a=90, h=1, f=0.5){
	difference(){
		rotate([0,0,180]) rotate_extrude(angle=a) translate([-r,0,0]) polygon(points=[[0,-h],[h,0],[0,h]]);
		cylinder(r=r-f, h=2*h, center=true);
	}
}
*/