/* 
parameterized communications type knob
*/

// precision:
$fn=100;

// config params:
NZ_D=0.4;					// nozzle dia
NZ_H=0.25;					// nozzle height
// build params:
DEBUG=0;						// show cross-section
SHORT=0;						// for short shaft encoder
//
TOP_D=SHORT?10.5:10;		// top diameter (at TOP_CH)
TOP_H=SHORT?11:16;		// top height (from base)
TOP_A=4;						// top angle (from vertical)
TOP_CH=1;					// top chamfer height
TOP_CA=45;					// top chamfer angle (from vertical)
//
BOT_D=15;					// bottom diameter (at BOT_CH)
BOT_H=2.5;					// bottom height (base to transition)
BOT_A=4;						// bottom angle (from vertical)
BOT_CA=45;					// bottom chamfer angle (from vertical)
BOT_CH=0.25;				// bottom chamfer height (at very bottom, 45 deg)
//
RIBS=10;						// ribs
RIB_W=1.5;					// rib width
RIB_D=0.4;					// rib depth
//
CS_D=12;						// countersink diameter
CS_H=3.5;					// countersink height (depth)
CS_F=1;						// countersink fillet (45 deg)
CS_CH=0.25;					// countersink chamfer (45 deg)
//
HOLE_D=6.50;				// hole diameter (was 6.35)
HOLE_H=SHORT?9.5:14.5;	// hole height (depth from base)
HOLE_F=0.25;				// hole fillet (45 deg)
HOLE_CH=0.25;				// hole chamfer (45 deg)
//
KNURLS=3;					// knurls (2, 3, 6, 9, 18)
KNURL_W=0.25;				// knurl width (into dia)
KNURL_H=SHORT?4:6;		// knurl height


module knob(){
	knurls();
	difference(){
		outer();
		csink();
		hole();
	}
}

translate([0,0,TOP_H]) rotate([180,0,0]){
	if(DEBUG){
		difference(){
			knob();
			translate([-BOT_D/2,-BOT_D,-0.01]) cube([BOT_D,BOT_D,TOP_H+0.02], center=false);
		}
	}
	else{
		knob();
	}
}

module outer(){
	bottom();
	intersection(){
		union(){
			ribs();
			top(dr=RIB_D);
		}
		top(0);
	}
}

module bottom(){
	r1 = BOT_D/2;
	r0 = r1-BOT_CH;
	h1 = BOT_CH;
	z1 = h1;
	h2 = BOT_H-h1;
	r2 = r1-h2*tan(BOT_A);
	z2 = z1+h2;
	r3 = TOP_D/2;
	h3 = (r2-r3)/tan(BOT_CA);
	cylinder(r1=r0, r2=r1, h=h1, center=false);  // lower chamfer
	translate([0,0,z1]) cylinder(r1=r1, r2=r2, h=h2, center=false);  // bottom
	translate([0,0,z2]) cylinder(r1=r2, r2=r3, h=h3, center=false);  // upper transition
}


module top(dr=0){
	h2 = TOP_CH;
	r1 = TOP_D/2-dr;
	h1 = TOP_H-h2;
	z1 = h1;
	r0 = r1+h1*tan(TOP_A);
	r2 = (dr) ? r1-h2*tan(TOP_A) : r1-h2*tan(TOP_CA);  // kill upper chamfer if inner
	cylinder(r1=r0, r2=r1, h=h1, center=false);  // top
	translate([0,0,z1]) cylinder(r1=r1, r2=r2, h=h2, center=false);  // upper chamfer
}

module ribs(){
	for (i=[0:RIBS-1]){
		rotate([0,0,i*360/RIBS])
			translate([BOT_D/2,0,TOP_H/2]) cube([BOT_D, RIB_W, TOP_H], center=true);
	}
}

module csink(){
	r4 = HOLE_D/2;
	r3 = r4+HOLE_CH;
	r1 = CS_D/2;
	r2 = r1-CS_F;
	r0 = r1+CS_CH;
	h1 = CS_CH;
	h2 = CS_H-CS_F;
	h3 = CS_F;
	h4 = HOLE_CH;
	z2 = h2;
	z3 = z2+h3;
	translate([0,0,-0.01]) cylinder(r1=r0, r2=r1, h=h1+0.01, center=false);  // csink chamfer
	translate([0,0,-0.01]) cylinder(r=r1, h=h2+0.01, center=false);  // csink
	translate([0,0,z2-0.01]) cylinder(r1=r1, r2=r2, h=h3+0.01, center=false);  // csink fillet
	translate([0,0,z3-0.01]) cylinder(r1=r3, r2=r4, h=h4+0.01, center=false);  // hole chamfer
}

module hole(){
	r0 = HOLE_D/2;
	r1 = r0-HOLE_F;
	h1 = HOLE_H-HOLE_F;
	h2 = HOLE_F;
	z1 = h1;
	cylinder(r=r0, h=h1+0.01, center=false);  // hole
	translate([0,0,z1]) cylinder(r1=r0, r2=r1, h=h2+0.01, center=false);  // fillet @ top
}

module knurls(){
	z0 = HOLE_H-KNURL_H/2;
	w0 = KNURL_W*sqrt(2);
	for (i=[0:KNURLS-1]){
		rotate([0,0,i*360/KNURLS]){
			translate([HOLE_D/2,0,z0]){
				rotate([0,0,45]){
					cube([w0, w0, KNURL_H], center=true);
				}
			}
		}
	}
}
