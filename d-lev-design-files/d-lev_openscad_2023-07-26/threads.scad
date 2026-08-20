/*
Metric Thread for plastic 3D printing

a:			thread angle (e.g. 30 for ~iso)
d:			thread major dia mm (e.g. 10 for M10)
p:			thread pitch mm
h:			threads height mm
cl:		thread clearance adder (0=nominal, see notes)
int:		internal (female) thread
b:			leadin @ bottom (1=nominal)
t:			leadin @ top (1=nominal)
debug:	true=no threads

Notes:
- Variable angle thread.
- Peak & valley clearances are identically located at H/8 points.
- Nominal face to face clearance is 0.25mm (0.125mm to centerline).

*/

module threads(a=45, d=20, p=2, h=20, cl=0, int=false, b=1, t=1, debug=false) {

	thread();  // do thread

	// derived thread params
	H=p/(2*tan(a));			// basic thread factor
	CL=(0.25+2*cl)/sin(a);	// thread clearance dia adder
	OD=(int)?d+CL:d-CL;		// major thread dia
	PR=OD/2-(3/8)*H;			// pitch radius
	ID=2*(PR-(3/8)*H);		// minor thread dia
	// poly params
	POLYS_PER_ROT=4;			// polyhedrons in one full rotation
	POLYS=ceil((2+h/p)*POLYS_PER_ROT);	// total number of polyhedrons
	POLY_A=360/POLYS_PER_ROT;	// angle one polyhedron fills

	// thread polyhedron
	module thd_poly(){
		// local params
		OR=PR+H/2;				// max x for triangle
		IR=PR-H/2;				// min x for triangle
		// points to form polyhedron w/ triangular cross-section
		function thd_p0(a) = [IR*cos(a), IR*sin(a), p*a/360];
		function thd_p1(a) = [IR*cos(a), IR*sin(a), p+p*a/360];
		function thd_p2(a) = [OR*cos(a), OR*sin(a), p/2+p*a/360];
		// other calcs
		segs=ceil($fn/POLYS_PER_ROT);
		angle=POLY_A/segs+0.01;  // for tiny overlap to next poly
		last=3*(segs-1);
		//echo("angle", angle);
		polyhedron(
			points=[for(i=[0:segs]) each [thd_p0(i*angle), thd_p1(i*angle), thd_p2(i*angle)]],
			faces=[[0,1,2],[last+4,last+3,last+5], each [for(i=[0:3:last]) each [[i,i+2,i+5,i+3],[i+1,i,i+3,i+4],[i+2,i+1,i+4,i+5]]]]
		);
	}

	// thread slug
	module slug(){
		intersection(){
			cylinder(d=OD, h=h);  // OD
			union(){
				cylinder(d=ID, h=h);  // ID
				translate([0,0,-p]) for (i=[0:POLYS-1]){ translate([0,0,i*p/POLYS_PER_ROT]) rotate([0,0,i*POLY_A]) thd_poly(); }
			}
		}
	}

	module thread(){
		ch = (3/8)*p;					// nominal leadin height
		b_ch = abs(b)*ch;				// bottom leadin height
		t_ch = abs(t)*ch;				// top leadin height
		b_dd = b_ch*2/tan(a);		// bottom leadin delta diameter
		t_dd = t_ch*2/tan(a);		// top leadin delta diameter
		b_d = (!int || (int && b<0)) ? OD-b_dd : OD; // bottom diameter
		t_d = (!int || (int && t<0)) ? OD-t_dd : OD; // top diameter
		//
		intersection(){
			union(){
				slug();  // thread slug
				if(debug) cylinder(d=OD, h=h);  // OD slug (debug)
			}
			union(){
				cylinder(d1=b_d, d2=OD, h=b_ch);  // bottom chamfer / fillet
				translate([0,0,b_ch]) cylinder(d=OD, h=h-b_ch-t_ch);  // OD
				translate([0,0,h-t_ch]) cylinder(d1=OD, d2=t_d, h=t_ch);  // top chamfer / fillet
			}
		}
		if(int && b>0) cylinder(d1=ID+b_dd, d2=ID, h=b_ch);  // bottom fem chamfer
		if(int && t>0) translate([0,0,h-t_ch]) cylinder(d1=ID, d2=ID+t_dd, h=t_ch);  // top fem chamfer
	}

}

