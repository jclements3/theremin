/* 
Plug for coil winder

Nominal ID
- 1" schedule 40 PVC pipe : ID=26
- 1-1/2" (PP or PVC) drain pipe : ID=35

*/

$fn=100;

// config params:
NZ_D=0.4;			// nozzle dia
NZ_H=0.25;			// nozzle height
HALF=0;				// 1=half, 0=whole
//
H=10;					// height
OD1=40;				// outer diameter (large)
OD2=30;				// outer diameter (small)
ID=(HALF)?8:8.25;	// inner diameter
USZ=0.1;				// face undersize
//
KW=6;					// key width
KH=6;					// key height
KD=3;					// key depth
KOSZ=0.15;			// key hole osz
KX=(OD1+OD2)/2;	// key x


//rotate([0,0,180]) rotate_extrude(angle=a) translate([-r,0,0]) polygon(points=[[0,-h],[h,0],[0,h]]);
module key(hole=true){
	osz=(hole)?KOSZ:0;
	ymid=((OD1+OD2)/2+ID)/4;
	yloc=(hole)?ymid:-ymid;
	x=KW/2;
	y=KH/2;
	h=KD+osz;
	translate([0,ymid,0]) rotate([90,0,90]) translate([0,0,-h]) linear_extrude(2*h) offset(delta=osz) polygon(points=[[-x,0],[0,y],[x,0],[0,-y],]);
}

module plug(){
	difference(){
		cylinder(d1=OD1, d2=OD2, h=H, center=true);
		cylinder(d=ID, h=H+0.02, center=true);
	}
}

module all(){
	if (HALF) {
		key(false);
		difference(){
			plug();
			translate([OD1/2-USZ,0,0]) cube([OD1,OD1,H+0.02], center=true);
			rotate([0,0,180]) key(true);
		}
	}
	else { 
		plug(); 
	}
}

all();


