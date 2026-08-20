/* 
D-Lev logo plate
*/

$fn=100;

// config params:
NZ_D=0.4;				// nozzle dia
NZ_H=0.25;				// nozzle height
// OK to change
W=125;					// width & overall scale factor
H=NZ_H*4;				// height
OSZ=0;					// oversize mm (for pen)
MIRROR=0;				// mirror about x
// derived params
TEXT_SCALE=W/5.5;		// text scale
TEXT_BASE=-W/9;		// text baseline loc
L=W/3;					// length

module outline(){
	translate([0,0,H/2]) cube([W,L,H], center=true);
}

module arrow_2d(){
	x = -TEXT_BASE/3;
	y = -TEXT_BASE;
	r = -TEXT_BASE/15;
	offset(r=-r) offset(delta=r) offset(r=r) offset(delta=-r){
		polygon([[x,0],[x,-y],[-x,-y],[-x,0],[-2*x,0],[0,y],[2*x,0]]);
	}
}

module text_arrows_2d(){
	x = 2*TEXT_SCALE;  // L & R arrow loc
	y = TEXT_BASE;  // text baseline loc
	tx = TEXT_BASE/20;	// text x offset (kerning with arrows)
	translate([-x,0,0]) arrow_2d();
	translate([x,0,0]) arrow_2d();
	translate([tx,y,0]) text("ClaraBOX", size=TEXT_SCALE, font="lintsec", halign="center", valign="baseline");
}	

module stencil(){
	difference(){
		outline();
		translate([0,0,-0.01]) linear_extrude(H+0.02) offset(r=OSZ) text_arrows_2d();
	}
}

if(MIRROR) mirror([1,0,0]) stencil();
else stencil();

