/* 
parameterized funnel
*/

// config params:
$fn=100;						// precision
NZ_D=0.4;					// nozzle dia
NZ_H=0.20;					// nozzle height
// build switches
TINY=1;						// height
//
T=(TINY)?NZ_D*2:NZ_D*4;	// wall thickness (min)
R=(TINY)?2:10;				// radii
// outer diameters (over ribs):
D0=(TINY)?30:150;			// bottom dia
D1=(TINY)?25:140;			// mid dia
D2=(TINY)?8:44;			// neck dia
D3=(TINY)?7:42;			// top dia
// heights:
H01=(TINY)?10:50;			// height D0 to D1
H23=(TINY)?10:50;			// height D2 to D3
// rib dims:
RIBS=8;						// rib count
RIB_W=(TINY)?1:4;			// rib width
RIB_T=T;						// rib thickness (radial)
//
DEBUG=0;						// show cutaway


// common stuff:
r0 = D0/2;
r1 = D1/2;
r2 = D2/2;
r3 = D3/2;
z2 = H01+r1-r2;
z3 = z2+H23;

echo("total height =", z3);

if(DEBUG){
	difference(){
		funnel();
		translate([0,-r0,0]) cube([D0,D0,z3]);
	}
}
else{
	funnel();
}

module funnel(){
	difference(){
		union(){
			// bottom lip
			intersection(){
			cylinder(d=D0, h=RIB_W);
				walls(offs=0);
			}
			// ribs
			intersection(){
				if(RIBS) ribs();
				walls(offs=0);
			}
			// outer walls
			walls(offs=-RIB_T);
		}
		// inner walls
		walls(offs=-RIB_T-T);
		// top chamfer
		difference(){
			translate([0,0,z3-RIB_T-1]) cylinder(r=r3+1, h=r3);
			translate([0,0,z3-RIB_T-1]) cylinder(r1=r3+1, r2=0, h=r3);
		}
	}
}


module walls(offs=0){
	a = [[-R,-R],[r0,-R],[r1,H01],[r2,z2],[r3,z3+R],[-R,z3+R]];  // profile
	b = [[0,0],[r0,0],[r0,z3],[0,z3]];  // chop: top, bottom, left, ch
	rotate_extrude(){
		intersection(){
			offset(offs){
				offset(r=R) offset(delta=-R) offset(r=-R) offset(delta=R) polygon(a);
			}
			polygon(b);
		}
	}
}

module ribs(){
	for (i=[0:RIBS-1]){
		rotate([0,0,i*360/RIBS])
			translate([0,-RIB_W/2,0]) cube([r0, RIB_W, z3]);
	}
}


