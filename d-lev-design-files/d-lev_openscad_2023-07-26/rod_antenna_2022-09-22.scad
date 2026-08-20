/* 
rod antenna tube
*/

$fn=100;

// config params:
NZ_D=0.4;					// nozzle dia
NZ_H=0.25;					// nozzle height
//
WC=3;							// wall count
WT=NZ_D*WC;					// wall thickness
ID=20;						// ID
OD=2*(ID/2+NZ_D*WC);		// OD
H=200;						// height
R=5;							// blend radius
SJ_H=20;						// slip joint height
SJ_CL=0.2;					// slip joint clearance (dia)
SJ_ID=OD+SJ_CL;			// slip joint ID
SJ_OD=OD+WT*2+SJ_CL;		// slip joint OD
SJ_CA=20;					// slip joint angle

dy = WT/tan(SJ_CA);
echo("OD", OD);

module profile_2d(){
	module poly(){
		x0 = 0;
		x1 = SJ_OD/2;
		x2 = OD/2;
		y0 = -R;
		y1 = SJ_H;
		y2 = SJ_H+dy;
		y3 = H+R;
		poly_points = [[x0,y0],[x1,y0],[x1,y1],[x2,y2],[x2,y3],[x0,y3],[x0,y0]];
		poly_paths = [[0,1,2,3,4,5,6]];
		polygon(poly_points, poly_paths, 10);
	}
	// fillet & radius
	module smooth_poly(){
		offset(r=R) offset(delta=-R) offset(r=-R) offset(delta=R) poly();
	}
	// inner & outer walls
	module profile(){
		difference(){
			smooth_poly();
			translate([-WT,0,0]) smooth_poly();
		}
	}
	// clip top and bottom
	intersection(){
		profile();
		square([OD,H]);
	}
}

rotate_extrude() profile_2d();
