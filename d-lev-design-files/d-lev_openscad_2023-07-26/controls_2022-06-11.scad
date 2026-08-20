/* 
LCD & encoders plate
*/

$fn=100;

// common features
include <d-lev_common.scad>;

// config params:
NZ_D=0.4;					// nozzle dia
NZ_H=0.25;					// nozzle height
WIDE=0;						// encoders off to sides
ENC_LP=0;					// encoders low profile
CSINK=0;						// countersink mounting holes
DEBUG=0;						// debug mode (show LCD & PCBs)
JIG=0;						// 0=normal; 1=3D jig; 2=2D jig
//
F_W=(WIDE)?185:125;		// face width
F_L=(WIDE)?125:165;		// face length
F_H=5;						// face height
F_R=6;						// face radius
F_CA=30;						// face chamfer angle (from vertical)
F_CH=1;						// face chamfer
//
B_W=F_W-20;					// back width
B_L=F_L-20;					// back length
B_H=F_H;						// back height
B_R=F_R;						// back radius
B_F=1;						// back fillet (with face)
//
J_H=NZ_H*12;				// jig height
J_W=F_W;						// jig width
J_L=F_L;						// jig length
J_Y=20;						// jig y offset (dist to bottom edge)
J_GL=NZ_D*5;				// jig guide length (thickness)
J_GH=J_H+NZ_H*12;			// jig guide height (from zero)
J_GD=3;						// jig guide hole dia

// render it all
module lcd_encoders(){
	difference(){
		union(){
			plate();
			pcb_lcd();
		}
		pcb_lcd(neg=true);
		encoders(neg=true);
	}
}

module jig(){
	sy = (F_L+B_L)/4;
	module stop(){  // the stop
		translate([0,-(J_L/2+J_Y+J_GL/2),J_GH/2]) cube([J_W,J_GL,J_GH], center=true);
	}
	module face_proj(){  // front face with holes
		projection(cut=false) lcd_encoders();
	}
	module back_proj(){  // back plate w/ no noles
		hull() projection(cut=true) translate([0,0,-B_F]) lcd_encoders();
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
else lcd_encoders();

// transparent guides
if (DEBUG) {
	pcb_lcd(trans=true);
	encoders(trans=true);
}

module plate() {
	rotate([0,180,0]) difference(){
		faceplate(F_W,F_W,F_L,F_H,F_CA,F_CH,F_R);
		faceplate_screws();
	}
	backplate(B_W,B_L,B_H,B_F,B_R);
}

module backplate(w, l, h, f, r) {
	dx = w/2-r;
	dy = l/2-r;
	r2 = r+f;
	hull(){
		// main
		translate([dx,dy,0]) cylinder(r=r, h=h);
		translate([-dx,dy,0]) cylinder(r=r, h=h);
		translate([-dx,-dy,0]) cylinder(r=r, h=h);
		translate([dx,-dy,0]) cylinder(r=r, h=h);
	}
	hull(){
		// fillet
		translate([dx,dy,0]) cylinder(r1=r2, r2=r, h=f);
		translate([-dx,dy,0]) cylinder(r1=r2, r2=r, h=f);
		translate([-dx,-dy,0]) cylinder(r1=r2, r2=r, h=f);
		translate([dx,-dy,0]) cylinder(r1=r2, r2=r, h=f);
	}
}

module faceplate_screws(){
	s_d = 3.5;							// screw hole dia
	s_cd = (CSINK) ? 6.5 : s_d;	// screw countersink dia
	s_ca = 90;							// screw countersink angle (included)
	s_ch = 1;							// screw countersink height (depth)
	//
	xr = F_W/2-F_R;
	yr = F_L/2-F_R;
	//
	translate([xr, yr, 0]) screw_hole(s_d, s_cd, F_H, s_ch, s_ca);
	translate([-xr, yr, 0]) screw_hole(s_d, s_cd, F_H, s_ch, s_ca);
	translate([-xr, -yr, 0]) screw_hole(s_d, s_cd, F_H, s_ch, s_ca);
	translate([xr, -yr, 0]) screw_hole(s_d, s_cd, F_H, s_ch, s_ca);
}


// PCB & LCD
module pcb_lcd(neg=false, trans=false){
	lcd_pw = 98;				// lcd pcb width (s/b 98)
	lcd_pl = 60;				// lcd pcb length (s/b 60))
	lcd_ph = 1.6;				// lcd pcb height (s/b 1.6)
	lcd_bw = 97;				// lcd bezel width (s/b 97)
	lcd_bl = 40;				// lcd bezel length (s/b 40)
	lcd_bh = 9.72;				// lcd bezel height (s/b 9.72)
	lcd_dw=76;					// lcd display area width (s/b 76)
	lcd_dl=25.8;				// lcd display area length (s/b 25.8)
	lcd_ww=lcd_dw-1;			// lcd window width
	lcd_wl=lcd_dl-1;			// lcd window length
	lcd_wa=F_CA;				// lcd window angle (from vertical)
	lcd_wr=2;					// lcd window radius
	lcd_wh=1;					// lcd window height (depth)
	lcd_sd = 3.5;				// lcd screw hole dia
	lcd_sx = 93/2;				// lcd screw hole X dim
	lcd_sy = 55/2;				// lcd screw hole Y dim
	lcd_spacer_h = 11;		// spacer height (s/b 11)
	lcd_cw = lcd_bw+2;		// lcd countersink width
	lcd_cl = lcd_bl+2;		// lcd countersink length
	lcd_z = 2-F_H;				// lcd face Z location (2mm face thickness)
	//
	pcb_w = 100;				// pcb width
	pcb_l = 100;				// pcb length
	pcb_h = 1.5;				// pcb height
	pcb_sd = lcd_sd;			// pcb screw hole dia
	pcb_sx = lcd_sx;			// pcb screw hole x dim
	pcb_sy0 = 3;				// pcb screw hole y dim (relative to front edge)
	pcb_sy1 = pcb_sy0+39;	// pcb screw hole y dim
	pcb_sy2 = pcb_sy1+lcd_sy*2;	// pcb screw hole y dim
	//
	post_d = 10;				// post dia
	post_f = 0.5;				// post fillet
	post_sd = 2.6;				// pcb screw hole dia (was 2.5)
	//
	lcd_y = -pcb_l/2+pcb_sy1+lcd_sy;
	pcb_z = lcd_z+lcd_bh+lcd_ph+lcd_spacer_h;
	trans_y = (WIDE)?0:20;
	//
	module pcb(){
		translate([0,-pcb_l/2,pcb_z]){  // pcb
			difference(){
				translate([-pcb_w/2,0,0]) cube([pcb_w,pcb_l,pcb_h]);  // pcb
				// pcb holes
				translate([pcb_sx,pcb_sy0,-0.01]) cylinder(d=pcb_sd, h=pcb_h+0.02);
				translate([-pcb_sx,pcb_sy0,-0.01]) cylinder(d=pcb_sd, h=pcb_h+0.02);
				translate([pcb_sx,pcb_sy1,-0.01]) cylinder(d=pcb_sd, h=pcb_h+0.02);
				translate([-pcb_sx,pcb_sy1,-0.01]) cylinder(d=pcb_sd, h=pcb_h+0.02);
				translate([pcb_sx,pcb_sy2,-0.01]) cylinder(d=pcb_sd, h=pcb_h+0.02);
				translate([-pcb_sx,pcb_sy2,-0.01]) cylinder(d=pcb_sd, h=pcb_h+0.02);
			}
		}
	}
	module lcd(){
		translate([0,lcd_y,lcd_bh+lcd_z]){  // lcd
			difference(){
				union(){
					translate([0,0,lcd_ph/2]) cube([lcd_pw,lcd_pl,lcd_ph], center=true);  // pcb
					translate([0,0,-lcd_bh/2]) cube([lcd_bw,lcd_bl,lcd_bh], center=true);  // metal bezel
				}
				// lcd holes
				translate([lcd_sx,lcd_sy,-0.01]) cylinder(d=lcd_sd, h=lcd_ph+0.02);
				translate([-lcd_sx,lcd_sy,-0.01]) cylinder(d=lcd_sd, h=lcd_ph+0.02);
				translate([-lcd_sx,-lcd_sy,-0.01]) cylinder(d=lcd_sd, h=lcd_ph+0.02);
				translate([lcd_sx,-lcd_sy,-0.01]) cylinder(d=lcd_sd, h=lcd_ph+0.02);
			}
		}
	}
	module posts(){
		h0 = lcd_z+lcd_bh-B_H;
		h1 = pcb_z-B_H;
		translate([0,lcd_y,0]){  // lcd posts
			translate([lcd_sx,lcd_sy,B_H]) post(d=post_d,h=h0,f=post_f);
			translate([-lcd_sx,lcd_sy,B_H]) post(d=post_d,h=h0,f=post_f);
			translate([-lcd_sx,-lcd_sy,B_H]) post(d=post_d,h=h0,f=post_f);
			translate([lcd_sx,-lcd_sy,B_H]) post(d=post_d,h=h0,f=post_f);
		}
		translate([0,-pcb_l/2,0]){  // pcb posts
			translate([lcd_sx,pcb_sy0,B_H]) post(d=post_d,h=h1,f=post_f);
			translate([-lcd_sx,pcb_sy0,B_H]) post(d=post_d,h=h1,f=post_f);
		}
	}
	module holes(){
		translate([0,lcd_y,0]){  // lcd window and csink
			translate([0,0,-0.01]) rotate([0,180,0]) tapered_window(lcd_ww,lcd_wl,F_H,lcd_wa,lcd_wh,lcd_wr);
			translate([0,0,lcd_z+lcd_bh/2]) cube([lcd_cw,lcd_cl,lcd_bh+0.01], center=true);  // csink
		}
		translate([0,lcd_y,lcd_z]){  // lcd post holes
			translate([lcd_sx,lcd_sy,0]) cylinder(d=post_sd, h=lcd_bh+0.01);
			translate([-lcd_sx,lcd_sy,0]) cylinder(d=post_sd, h=lcd_bh+0.01);
			translate([-lcd_sx,-lcd_sy,0]) cylinder(d=post_sd, h=lcd_bh+0.01);
			translate([lcd_sx,-lcd_sy,0]) cylinder(d=post_sd, h=lcd_bh+0.01);
		}
		translate([0,-pcb_l/2,0]){  // pcb post holes
			translate([lcd_sx,pcb_sy0,0]) cylinder(d=post_sd, h=pcb_z+0.01);
			translate([-lcd_sx,pcb_sy0,0]) cylinder(d=post_sd, h=pcb_z+0.01);
		}
	}

	// instantiate stuff (and translate in y)
	translate([0,trans_y,0]){
		if(neg) { holes(); }
		else if(trans) { %pcb(); %lcd(); }
		else { posts(); }
	}
}


// encoder holes, csinks, pwbs
module encoders(neg=false, trans=false) {
	enc_d = 7.2;				// encoder hole diameter
	enc_w = 14;					// encoder width (csink)
	enc_l = 13;					// encoder length (csink)
	enc_h = (ENC_LP)?4:6;	// encoder height (face to pwb - osz)
	enc_x = (WIDE)?65:20.32;	// encoder X
	enc_y = 20.32;				// encoder Y
	enc_dy = (WIDE)?0:-27;	// encoder Y offset
	enc_z = 4-F_H;				// encoder Z location (for 4mm face thickness)
	enc_pw = 26;				// encoder pcb width
	enc_pl = 20;				// encoder pcb length
	enc_ph = 1.6;				// encoder pcb height (thickness)
	enc_pz = enc_z+enc_h;	// encoder pcb location (from z=0)
	enc_cw = enc_pw+2;		// encoder csink width (@ top)
	enc_cl = enc_pl+2;		// encoder csink length (@ top)
	enc_ch = enc_ph+4;		// encoder csink height (@ top)
	//
	module hole() {
		translate([0,0,-F_H-0.01]) cylinder(d=enc_d, h=enc_z+F_H+0.02);  // hole
	}
	module csink() {
		translate([0,0,enc_z]){
			hull(){  // countersink
				translate([0,0,0.5]) cube([enc_w, enc_l, 1], center=true);  // @ face
				translate([0,0,enc_h+enc_ch/2]) cube([enc_cw,enc_cl,enc_ch], center=true);  // pcb
			}
		}
	}
	module pwb() {
		translate([0,0,enc_pz]){
			translate([0,0,enc_ph/2]) cube([enc_pw,enc_pl,enc_ph], center=true);  // pcb
		}
	}
	module inst() {
		// instantiate stuff
		if(neg) { hole(); csink(); }
		else if(trans) { %pwb(); }
		else { }
	}
	// do 8x
	translate([enc_x,enc_dy+3*enc_y/2,0]) inst();
	translate([enc_x,enc_dy+enc_y/2,0]) inst();
	translate([enc_x,enc_dy-enc_y/2,0]) inst();
	translate([enc_x,enc_dy-3*enc_y/2,0]) inst();
	//
	translate([-enc_x,enc_dy+3*enc_y/2,0]) inst();
	translate([-enc_x,enc_dy+enc_y/2,0]) inst();
	translate([-enc_x,enc_dy-enc_y/2,0]) inst();
	translate([-enc_x,enc_dy-3*enc_y/2,0]) inst();
}

