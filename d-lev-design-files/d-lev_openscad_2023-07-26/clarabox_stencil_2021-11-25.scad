/* 
D-Lev stencil
*/

$fn=100;

// config params:
NZ_D=0.4;				// nozzle dia
NZ_H=0.25;				// nozzle height
// OK to change
W=200;					// width & overall scale factor
H=NZ_H*4;				// height
OSZ=0;					// oversize mm (for pen)
MIRROR=0;				// mirror about x
// derived params
TEXT_SCALE=W/12;		// text scale
L=W/5;					// length

module outline(){
	translate([0,0,H/2]) cube([W,L,H], center=true);
}

module text_2d(){
	text("CLARABOX", size=TEXT_SCALE, font="lintsec", halign="center", valign="center");
}	

module stencil(){
	difference(){
		outline();
		translate([0,0,-0.01]) linear_extrude(H+0.02) offset(r=OSZ) text_2d();
	}
}

if(MIRROR) mirror([1,0,0]) stencil();
else stencil();

