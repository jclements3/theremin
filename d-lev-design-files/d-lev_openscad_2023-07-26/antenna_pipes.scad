/* 
antenna pipes

It seems pipes mostly just contract when heated and bent, 
and not expand and contract on either side of the centerline.
*/

$fn=100;

// general:
PR=15.9/2;		// pipe radius
BR=38;			// bend radius (thru centerline)
// lengths (centerline dims)
L0=210;
L1=35;
L2=70;
L3=80;
// angles
A0=90;
A1=A0;
//A2=2*(180-(A1+A0));
A2=45;
A3=0;
//

// elbow and rod
// a=0 gives only rod of length l along x axis
module elbow_rod(a, l){
	translate([0,BR,0]){
		rotate([0,0,-90]) rotate_extrude(angle=a, convexity=10) translate([BR,0,0]) circle(PR);
		rotate([0,0,a]) translate([0,-BR,0]) rotate([0,90,0]) cylinder(r=PR,h=l);
	}
}

module volume_loop(a0,a1,a2,a3,l0,l1,l2,l3){
	translate([-l3,BR,0]) rotate([0,0,-a3]) translate([0,-BR,0]){
		translate([-l2,BR,0]) rotate([0,0,-a2]) translate([0,-BR,0]){
			translate([-l1,BR,0]) rotate([0,0,-a1]) translate([0,-BR,0]){
				translate([-l0,BR,0]) rotate([0,0,-a0]) translate([0,-BR,0]) elbow_rod(a0, l0);
				elbow_rod(a1, l1);
			}
			elbow_rod(a2, l2);
		}
		elbow_rod(a3, l3);
	}
}


mirror([0,1,0]) volume_loop(A3,A2,A1,A0,L3,L2,L1,L0);

blen0 = (BR-PR)*2*PI*A0/360;
blen1 = (BR-PR)*2*PI*A1/360;
blen2 = (BR-PR)*2*PI*A2/360;

bloc0 = L0+blen0/2;
bloc1 = L0+blen0+L1+blen1/2;
bloc2 = L0+blen0+L1+blen1+L2+blen2/2;

elen = L0+blen0+L1+blen1+L2+blen2+L3;

echo("BEND 0 LOC:", bloc0);
echo("BEND 1 LOC:", bloc1);
echo("BEND 2 LOC:", bloc2);
echo("EFFECTIVE LENGTH:", elen);
