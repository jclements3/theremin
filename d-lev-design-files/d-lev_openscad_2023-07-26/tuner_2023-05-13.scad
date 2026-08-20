/* 
Tiny LED tuner plate
*/

$fn=100;

// common features
include <d-lev_common.scad>;

// config params:
NZ_D=0.4;						// nozzle dia
NZ_H=0.25;						// nozzle height
TINY=1;							// tiny tuner
CSINK=0;							// countersink mounting holes
DEBUG=1;							// debug mode (show pcb & leds)
CENTER=1;						// note circle @ center
JIG=0;							// 0=normal; 1=3D jig; 2=2D jig
//
F_W=(TINY)?125:155;			// face width
F_L=(TINY)?80:90;				// face length
F_H=5;							// face height
F_R=6;							// face radius
F_CA=30;							// face chamfer angle (from vertical)
F_CH=1;							// face chamfer
//
S_D=3.5;							// screw hole dia
S_CD=(CSINK)?6.5:S_D;		// screw countersink dia
S_CA=90;							// screw countersink angle (included)
S_CH=1;							// screw countersink height (depth)
S_XY=F_R;						// screw X&Y offset
//
SEG7_W=(TINY)?12.8:24;		// 7-segment width
SEG7_L=(TINY)?19.2:34;		// 7-segment length
SEG7_H=(TINY)?8:10.5;		// 7-segment height (mounted flush, s/b 8)
//
SEG7_CC=1;						// 7-segment countersink clearance
SEG7_CW=SEG7_W+SEG7_CC;		// 7-segment countersink width
SEG7_CL=SEG7_L+SEG7_CC;		// 7-segment countersink length
SEG7_CH=3;						// 7-segment countersink height (depth)
//
SEG7_WC=2;						// 7-segment window clearance (ledge)
SEG7_WW=SEG7_W-SEG7_WC;		// 7-segment window width
SEG7_WL=SEG7_L-SEG7_WC;		// 7-segment window length
SEG7_WA=30;						// 7-segment window angle (from vertical)
SEG7_WR=1;						// 7-segment window radius
SEG7_WH=1;						// 7-segment window height (depth)
//
LED_D=(TINY)?8:10;			// LED diameter
LED_DC=0.25;					// LED diameter clearance
LED_SD=(TINY)?9:11;			// LED skirt diameter
LED_SH=2;						// LED skirt height
LED_H=(TINY)?11:13.5;		// LED height (mounted flush)
LED_CA=SEG7_WA;				// LED countersink angle (from vertical)
LED_CH=SEG7_WH;				// LED countersink height (depth)
//
PCB_SD=2.6;						// PCB screw dia (was 2.5)
PCB_HD=3.5;						// PCB hole dia
PCB_PD=(TINY)?9:11;			// PCB post dia
PCB_PH=SEG7_H-SEG7_CH;		// PCB post height
PCB_PF=1;						// PCB post fillet
PCB_SX=(TINY)?46.503:2.4*25.4;	// PCB hole X loc
PCB_SY=(TINY)?26.1875:1.15*25.4;	// PCB hole Y loc
PCB_W=(TINY)?101.6:132;		// PCB width
PCB_L=(TINY)?60.96:69;		// PCB length
PCB_H=1.5;						// PCB height
PCB_R=5;						// PCB radius
//
LED_VX0=(TINY)?-42.16:-2.16*25.4;	// volume LED X center loc
LED_VYD=(TINY)?11.798:0.5*25.4;		// volume LED Y delta
LED_PX0=(CENTER)?0:(TINY)?24.6421:1.258*25.4;	// pitch LED X center loc
LED_PXD=(TINY)?11.684:0.6*25.4;		// pitch LED X delta
LED_PYD=(TINY)?10.1092:0.52*25.4;	// pitch LED Y delta
SEG7_X=(CENTER)?-LED_VX0:(TINY)?-17.721:-0.8936*25.4;	// 7-segment X loc
//
RIB_H=PCB_PH;					// rib height
RIB_T=NZ_D*5;					// rib thickness
RIB_F=PCB_PF;					// rib fillet
//
B_HC=3.5;						// back height clearance
B_H=PCB_PH-B_HC;				// back height
//
J_H=NZ_H*10;					// jig height
J_W=F_W;							// jig width
J_L=F_L;							// jig length
J_Y=20;							// jig y offset (dist to top edge)
J_GL=NZ_D*5;					// jig guide length (thickness)
J_GH=J_H+NZ_H*12;				// jig guide height (from zero)
J_GD=3;							// jig guide hole dia

// render all
module tuner(c="Gray"){
	color(c) difference(){
		union(){
			plate();
			pcb_posts();
			ribs();
		}
		pcb_holes();
		seg7_csink();
		vol_holes(x=LED_VX0);  // clean out fillets
	}
}

module jig(){
	sy = (F_L+PCB_L)/4;
	module stop(){  // the stop
		translate([0,-(J_L/2+J_Y+J_GL/2),J_GH/2]) cube([J_W,J_GL,J_GH], center=true);
	}
	module face_proj(){  // front face with holes
		projection(cut=false) tuner();
	}
	module back_proj(){  // back plate w/ no noles
		hull() projection(cut=true) translate([0,0,-PCB_PF]) tuner();
	}
	module fb_minus_bp(){
		difference(){
			face_proj();
			back_proj();
		}
	}
	module guide(){
		difference(){
			hull(){
				if(JIG==1) projection(cut=false) stop();
				face_proj();
			}
			hull() fb_minus_bp();
		}
	}
	module extruded(){
		linear_extrude(height=J_H){
			fb_minus_bp();
			guide();	
		}
	}
	if(JIG==1) stop();  // add stop
	difference(){  // subtract guide holes
		extruded();
		translate([0,sy,J_H/2]) cylinder(d=J_GD,h=J_H+0.02,center=true);
		translate([0,-sy,J_H/2]) cylinder(d=J_GD,h=J_H+0.02,center=true);
	}
}

if(JIG==2) projection(cut=false) jig();
else if(JIG) jig();
else tuner();

// face with screw & LED holes
module plate(){
	rotate([180,0,0]){
		difference(){
			face();
			screw_holes();
			pitch_holes(x=LED_PX0);
			vol_holes(x=LED_VX0);
			seg7_window();
		}
	}
}

module face(){
	faceplate(F_W, F_W, F_L, F_H, F_CA, F_CH, F_R);
	translate([0,0,-B_H]) backplate(h=B_H);
}

// backplate
module backplate(h){
	hull(){
		translate([PCB_SX,PCB_SY,0]) cylinder(d=PCB_PD, h=h);
		translate([-PCB_SX,PCB_SY,0]) cylinder(d=PCB_PD, h=h);
		translate([-PCB_SX,-PCB_SY,0]) cylinder(d=PCB_PD, h=h);
		translate([PCB_SX,-PCB_SY,0]) cylinder(d=PCB_PD, h=h);
	}
}

module ribs(){
	x = PCB_SX+(PCB_PD-RIB_T)/2;
	y = PCB_SY+(PCB_PD-RIB_T)/2;
	rib(-PCB_SX, y, PCB_SX, y, RIB_H, RIB_H, RIB_T, RIB_F);  // top
	rib(-PCB_SX, -y, PCB_SX, -y, RIB_H, RIB_H, RIB_T, RIB_F);  // bottom
	rib(x, -PCB_SY, x, PCB_SY, RIB_H, RIB_H, RIB_T, RIB_F);  // right
	rib(-x, -PCB_SY, -x, PCB_SY, RIB_H, RIB_H, RIB_T, RIB_F);  // left
}

module pcb_posts(){
	translate([PCB_SX,PCB_SY,0]) post(d=PCB_PD, h=PCB_PH, f=PCB_PF);
	translate([-PCB_SX,PCB_SY,0]) post(d=PCB_PD, h=PCB_PH, f=PCB_PF);
	translate([-PCB_SX,-PCB_SY,0]) post(d=PCB_PD, h=PCB_PH, f=PCB_PF);
	translate([PCB_SX,-PCB_SY,0]) post(d=PCB_PD, h=PCB_PH, f=PCB_PF);
}

module pcb_holes(){  // post holes!
	z = -F_H+2;  // 2mm face thickness
	h = PCB_PH-z+0.01;
	translate([PCB_SX,PCB_SY,z]) cylinder(d=PCB_SD,h=h);
	translate([-PCB_SX,PCB_SY,z]) cylinder(d=PCB_SD,h=h);
	translate([-PCB_SX,-PCB_SY,z]) cylinder(d=PCB_SD,h=h);
	translate([PCB_SX,-PCB_SY,z]) cylinder(d=PCB_SD,h=h);
}

module screw_holes(){
	x = F_W/2-S_XY;
	y = F_L/2-S_XY;
	translate([x,y,0]) screw_hole(S_D, S_CD, F_H, S_CH, S_CA);
	translate([-x,y,0]) screw_hole(S_D, S_CD, F_H, S_CH, S_CA);
	translate([-x,-y,0]) screw_hole(S_D, S_CD, F_H, S_CH, S_CA);
	translate([x,-y,0]) screw_hole(S_D, S_CD, F_H, S_CH, S_CA);
}

module pitch_holes(x=0, y=0){
	translate([x,y,0]){
		led_hole(0,2*LED_PYD);
		//
		led_hole(-LED_PXD*3/2,LED_PYD);
		led_hole(-LED_PXD/2,LED_PYD);
		led_hole(+LED_PXD/2,LED_PYD);
		led_hole(+LED_PXD*3/2,LED_PYD);
		//
		led_hole(-LED_PXD,0);
		led_hole(0,0);
		led_hole(LED_PXD,0);
		//
		led_hole(-LED_PXD*3/2,-LED_PYD);
		led_hole(-LED_PXD/2,-LED_PYD);
		led_hole(+LED_PXD/2,-LED_PYD);
		led_hole(+LED_PXD*3/2,-LED_PYD);
		//
		led_hole(0,-2*LED_PYD);
	}
}

module vol_holes(x=0, y=0){
	translate([x,y,0]){
		led_hole(0,LED_VYD*3/2);
		led_hole(0,LED_VYD/2);
		led_hole(0,-LED_VYD/2);
		led_hole(0,-LED_VYD*3/2);
	}
}

module led_hole(x=0, y=0){
	id = LED_D+LED_DC;
	d2 = id+2*LED_CH*tan(LED_CA);
	h = F_H+B_H;
	translate([x,y,0]){
		translate([0,0,-B_H-0.01]) cylinder(d=id, h=h+0.02);  // thru hole
		translate([0,0,F_H-LED_CH]) cylinder(d1=id, d2=d2, h=LED_CH+0.01);  // csink
	}
}

module seg7_window(){
	translate([SEG7_X,0,-0.01]) tapered_window(SEG7_WW, SEG7_WL, F_H, SEG7_WA, SEG7_WH, SEG7_WR);
}

module seg7_csink() {
	h = B_H+SEG7_CH;
	translate([SEG7_X-SEG7_CW/2,-SEG7_CL/2,-SEG7_CH]) cube([SEG7_CW, SEG7_CL, h+0.01]);
}

// show pcb (debug):
if(DEBUG){
	echo("THICKNESS", F_H+B_H);
	translate([0,0,PCB_PH]){
		rotate([180,0,0]){
			pcb();
			pitch_leds(x=LED_PX0);
			vol_leds(x=LED_VX0);
			seg7(x=SEG7_X);
		}
	}
}

module pcb(c="Green", t=0.5){
	x = PCB_W/2 - PCB_R;
	y = PCB_L/2 - PCB_R;
	h = PCB_H;
	difference(){
		color(c, t) hull(){  // pcb
			translate([x,y,-h]) cylinder(r=PCB_R, h=h);
			translate([-x,y,-h]) cylinder(r=PCB_R, h=h);
			translate([-x,-y,-h]) cylinder(r=PCB_R, h=h);
			translate([x,-y,-h]) cylinder(r=PCB_R, h=h);
		}  // holes
		translate([PCB_SX,PCB_SY,-h-0.01]) cylinder(d=PCB_HD,h=h+0.02);
		translate([-PCB_SX,PCB_SY,-h-0.01]) cylinder(d=PCB_HD,h=h+0.02);
		translate([-PCB_SX,-PCB_SY,-h-0.01]) cylinder(d=PCB_HD,h=h+0.02);
		translate([PCB_SX,-PCB_SY,-h-0.01]) cylinder(d=PCB_HD,h=h+0.02);
	}
}

module seg7(x=0, y=0, c="Blue", cb="Black", t=0.9){
	translate([x,y,0]){
		color(cb) translate([0,0,SEG7_H/2]) cube([SEG7_W,SEG7_L,SEG7_H], center=true);  // seg7
		color(c, t) scale([0.5,0.5,1]) linear_extrude(SEG7_H+0.01) import("7-seg.svg", center=true);
	}
}

module pitch_leds(x=0, y=0, c="White", cc="Blue", t=0.4){
	translate([x,y,0]){
		color(cc, t) led(0,0);
		color(c, t){
			led(0,2*LED_PYD);
			//
			led(-LED_PXD*3/2,LED_PYD);
			led(-LED_PXD/2,LED_PYD);
			led(+LED_PXD/2,LED_PYD);
			led(+LED_PXD*3/2,LED_PYD);
			//
			led(-LED_PXD,0);
			led(LED_PXD,0);
			//
			led(-LED_PXD*3/2,-LED_PYD);
			led(-LED_PXD/2,-LED_PYD);
			led(+LED_PXD/2,-LED_PYD);
			led(+LED_PXD*3/2,-LED_PYD);
			//
			led(0,-2*LED_PYD);
		}
	}
}

module vol_leds(x=0, y=0, c="Blue", t=0.4){
	color(c, t) translate([x,y,0]){
		led(0,LED_VYD*3/2);
		led(0,LED_VYD/2);
		led(0,-LED_VYD/2);
		led(0,-LED_VYD*3/2);
	}
}

module led(x=0, y=0){
	translate([x,y,0]){
		cylinder(d=LED_SD, h=LED_SH);
		cylinder(d=LED_D, h=LED_H-LED_D/2);
		translate([0,0,LED_H-LED_D/2]) sphere(d=LED_D);
	}
}

