/* 
human stick figure
*/

$fn=100;

// params:
H=1700;					// over-all height (@ top)
//
HEAD_D0=200;			// head top dia
HEAD_D1=150;			// head bottom dia
HEAD_H=250;				// head height (top to bottom)
//
HAND_D=100;				// hand dia
SHLDR_D=100;			// shoulder dia
ELBOW_D=80;				// elbow dia
WRIST_D=60;				// wrist dia
STICK_D=75;				// stick dia
//
SHLDR_H=1370;			// shoulder height (@ top)
SHLDR_W=440;			// shoulder width (outer)
//
ARM_UL=250;				// upper arm length (shoulder center to elbow center)
ARM_FL=300;				// forearm length (elbow center to hand center)
//
HAND_W=450;				// hand width (center to center)
LHAND_H=1100;			// L hand height (floor to center)
RHAND_H=1140;			// R hand height (floor to center)

// derived params:
head_z0 = H-HEAD_D0/2;
head_z1 = H-HEAD_H+HEAD_D1/2;
shldr_z = SHLDR_H-SHLDR_D/2;
shldr_dx = (SHLDR_W-SHLDR_D)/2;
elbow_z = shldr_z-ARM_UL;
hand_dx = HAND_W/2;

module segment(x0,y0,z0,d0,x1,y1,z1,d1){
	hull(){
		translate([x0,y0,z0]) sphere(d=d0);
		translate([x1,y1,z1]) sphere(d=d1);
	}
}

module stick_figure(){
	segment(0,0,head_z0,HEAD_D0,0,0,head_z1,HEAD_D1);  // head
	segment(0,0,shldr_z,SHLDR_D,0,0,head_z1,SHLDR_D);  // neck
	segment(-shldr_dx,0,shldr_z,SHLDR_D,shldr_dx,0,shldr_z,SHLDR_D);  // shoulders
	segment(-shldr_dx,0,shldr_z,SHLDR_D,-shldr_dx,0,elbow_z,ELBOW_D);  // L upper arm
	segment(shldr_dx,0,shldr_z,SHLDR_D,shldr_dx,0,elbow_z,ELBOW_D);  // R upper arm
	segment(-shldr_dx,0,elbow_z,ELBOW_D,-hand_dx,ARM_FL,LHAND_H,WRIST_D);  // L forearm
	segment(shldr_dx,0,elbow_z,ELBOW_D,hand_dx,ARM_FL,RHAND_H,WRIST_D);  // R forearm
	translate([-hand_dx,ARM_FL,LHAND_H]) sphere(d=HAND_D);  // L hand
	translate([hand_dx,ARM_FL,RHAND_H]) sphere(d=HAND_D);  // R hand
}

stick_figure();
