/* 
parameterized socket wrench for encoders and such
*/

// precision:
$fn=100;

// config params:
NZ_D=0.4;					// nozzle dia
NZ_H=0.25;					// nozzle height
// build params:
DEBUG=0;						// show cross-section
//
H=25;							// overall height
//
HEX_WALLS=4;				// wall count
HEX_WW=HEX_WALLS*NZ_D;	// wall width
HEX_FD=10.4;				// flats diameter
HEX_PD=HEX_FD/cos(30);	// points diameter
HEX_IH=2;					// inner nut height
HEX_CH=NZ_H*4;				// chamfer
HEX_OH=HEX_IH+1;			// outer height to fillet
//
GRIP_WALLS=4;				// wall count
GRIP_WW=GRIP_WALLS*NZ_D;// wall width
GRIP_ID=7;					// id min
GRIP_OD=11;					// od max
GRIP_DIPS=6;				// dip count
GRIP_DIPS_R=4;				// dip radius


module hex_id_2d(){
	translate([0,0,-0.01]) circle(d=HEX_PD, $fn=6);
}

module hex_id(){
	ch_xz = GRIP_ID/2+HEX_CH;
	translate([0,0,-0.01]) linear_extrude(HEX_IH+0.01) hex_id_2d();
	translate([0,0,HEX_IH-0.01]) cylinder(r1=ch_xz, d2=0, h=ch_xz, center=false);  // chamfer
}

module hex_od(){
	f_xz = HEX_PD/2+HEX_WW+HEX_OH;
	intersection(){
		linear_extrude(f_xz) offset(r=HEX_WW) hex_id_2d();
		cylinder(r1=f_xz, d2=0, h=f_xz, center=false);  // fillet
	}
}

module grip_id_2d(){
	difference(){
		r = GRIP_OD/2-GRIP_WW;
		circle(r=r);
		tx = GRIP_ID/2+GRIP_DIPS_R;
		for (i=[0:GRIP_DIPS-1]){
			rotate([0,0,i*360/GRIP_DIPS])
				translate([tx,0,0]) circle(r=GRIP_DIPS_R);
		}
	}
}

module grip_od(){
	linear_extrude(H) offset(r=GRIP_WW) grip_id_2d();
}

module grip_id(){
	linear_extrude(H+0.01) grip_id_2d();
}

module outer(){
	hex_od();
	grip_od();
}

module inner(){
	hex_id();
	grip_id();
}

module tool(){
	difference(){
		outer();
		inner();
	}
}

translate([0,0,H]) rotate([180,0,0]){
	if(DEBUG){
		x = HEX_PD+HEX_WW*2;
		difference(){
			tool();
			translate([-x/2,-x,-0.01]) cube([x,x, H+0.02], center=false);
		}
	}
	else{
		tool();
	}
}
