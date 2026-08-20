/* 
Keystone - centered up on the hole length and width, not the walls
*/

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

	module keyhole(){
		translate([0,HOLE_W/2,0])
		rotate([90,0,0])
		linear_extrude(height=HOLE_W, center=false) { keyhole_poly(); }
	}
	
	keyhole();
	
}