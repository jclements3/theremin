/* 
D-Lev logo plate
*/

$fn=100;

// config params:
NZ_D=0.4;				// nozzle dia
NZ_H=0.25;				// nozzle height
// build switches
CAPS=0;					// all caps
RINGS=1;					// rings enable
SUBTEXT=1;				// subtext enable
QQC=0;					// "quasquicentennial" subtext
BOSS=0;					// boss around holes
SB=0;						// print sanding block
JIG=0;					// print jig
LOGO_2D=0;				// print 2D logo
IRONING=0;				// print ironing layer
XY_SCALE=1.0;			// x & y scale
// OK to change
W=100;					// width
R=7.5;					// outer radius
H=10*NZ_H;				// height
D=5*NZ_H;				// depth (less than H)
T=8*NZ_D;				// edge thickness
H_D=3.25;				// hole diameter
H_BD=H_D+T;				// hole boss diameter
H_BH=H-D;				// hole boss height
H_X=42;					// hole x loc
// sanding block
SB_H=12;					// sanding block height
SB_D=H-3*NZ_H;			// sanding block depth
SB_CL=0.5;				// sanding block clearance
SB_CH=8*NZ_H;			// sanding block chamfer
// jig
J_H=NZ_H*6;				// jig height
J_X=70;					// jig x offset (center to L&R edges)
J_Y=60;					// jig y offset (center to top edge)
J_GL=NZ_D*5;			// jig guide length (thickness)
J_GH=J_H+NZ_H*12;		// jig guide height (from zero)
// derived params
L=(SUBTEXT)?(RINGS)?43:35:(RINGS)?35:30;	// length

module jig(){
	hx = XY_SCALE * H_X;
	osz = 5;
	w = 2*J_X;
	l = J_Y+osz;
	x = 0;
	y = l/2-osz;
	difference(){
		union(){
			translate([x,y,J_H/2]) cube([w,l,J_H], center=true);
			translate([x,J_Y+J_GL/2,J_GH/2]) cube([w,J_GL,J_GH], center=true);
		}
		translate([hx,0,J_H/2]) cylinder(d=H_D, h=J_H+0.01, center=true);
		translate([-hx,0,J_H/2]) cylinder(d=H_D, h=J_H+0.01, center=true);
	}
}

module outline(w, l, h, r, ch){
	hull(){	
		x = w/2-r;
		y = l/2-r;
		translate([x,y,ch]) cylinder(r=r, h=h-ch);
		translate([-x,y,ch]) cylinder(r=r, h=h-ch);
		translate([-x,-y,ch]) cylinder(r=r, h=h-ch);
		translate([x,-y,ch]) cylinder(r=r, h=h-ch);
		// chamfer
		translate([x,y,0]) cylinder(r1=r-ch, r2=r, h=ch);
		translate([-x,y,0]) cylinder(r1=r-ch, r2=r, h=ch);
		translate([-x,-y,0]) cylinder(r1=r-ch, r2=r, h=ch);
		translate([x,-y,0]) cylinder(r1=r-ch, r2=r, h=ch);
	}
}

module blank(){
	difference(){
		outline(w=W, l=L, h=H, r=R, ch=0);  // outer
		translate([0,0,H-D]) outline(w=W-2*T, l=L-2*T, h=H, r=R-T, ch=0);  // inner
	}
}

module sanding_block(){
	w = W+SB_CL;
	l = L+SB_CL;
	r = R+SB_CL/2;
	difference(){
		outline(w=w+2*T, l=l+2*T, h=SB_H, r=R+T, ch=SB_CH);  // outer
		translate([0,0,SB_H-SB_D]) outline(w=w, l=l, h=SB_D+0.01, r=r, ch=0);  // inner
	}
}	

module text_2d(){
	ty = -0.41;
	sxy = 100/6.5;
	text0 = (CAPS) ? "D-LE" : "D-Le";
	text1 = (CAPS) ? "V" : "v";
	scale([sxy,sxy,1]){
		translate([-0.6,ty,0]) text(text0, size=1, font="Neuropol", halign="center", valign="baseline");
		translate([1.8,ty,0]) text(text1, size=1, font="Neuropol", halign="center", valign="baseline");
	}
}	

module subtext_2d(){
	ty = -0.5;
	sxy = (QQC) ? 29/6.5 : 35/6.5;
	scale([sxy,sxy,1]){
		translate([0,ty,0]){
			if (!QQC) text("Digital theremin", size=1, font="Space Age", halign="center", valign="baseline");
			else text("quasquicentennial", size=1, font="Space Age", halign="center", valign="baseline");
		}
	}
}	


module ring_2d(r=1, t=0.1){
	difference(){
		offset(t/2) circle(r=r);
		offset(-t/2) circle(r=r);
	}
}

module rings_2d(){
	rings = 4;
	rstep = 2.5;
	rstart = 2.5;
	x = -9.05;
	y = 6;
	difference(){
		translate([x,y,0]){
			t = 2*NZ_D;
			for (i=[0:rings-1]){ ring_2d(r=rstart+i*rstep, t=t); }
		}
		offset(r=XY_SCALE/1.75) text_2d();
	}
		
}

module holes(boss=0){
	x = XY_SCALE*H_X;
	d = (boss)?H_BD:H_D;
	h = (boss)?H_BH:H+0.02;
	z = (boss)?0:-0.01;
	translate([x,0,z]) cylinder(d=d, h=h);
	translate([-x,0,z]) cylinder(d=d, h=h);
}
	

module plaque(){
	y0=(SUBTEXT)?(RINGS)?0:3:(RINGS)?-4.5:0;
	difference(){
		scale([XY_SCALE,XY_SCALE,1]){
			blank();
			if(BOSS) holes(boss=1);
			translate([0,y0,0]) {
				linear_extrude(H){
					text_2d();
					if (RINGS) rings_2d();
					if (SUBTEXT) translate([0,-12,0]) subtext_2d();
				}
			}
		}
		holes(boss=0);
	}
}

if(JIG) 
	jig();
else if(SB) 
	sanding_block();
else if(LOGO_2D) 
	projection(cut=true) translate([0,0,-H+0.01]) plaque();
else if(IRONING) 
	linear_extrude(H-D) projection(cut=true) plaque();
else{
	plaque();
	echo("dims:", W, L, H);
}

