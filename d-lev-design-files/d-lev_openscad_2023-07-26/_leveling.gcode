; Bed leveling Ender 3 by ingenioso3D
; Modified by elproducts CHEP FilamentFriday.com
; Modified by EDW

G90 ; absolute coordinates
G28 ; home axis

G1 Z5 F5000 ; z up
G1 X32 Y36 ; near left
G1 Z0 F250 ; z down
M0 ; pause
G1 Z5 F5000 ; z up
G1 X32 Y206 ; far left
G1 Z0 F250 ; z down
M0 ; pause
G1 Z5 F5000 ; z up
G1 X202 Y206 ; far right
G1 Z0 F250 ; z down
M0 ; pause
G1 Z5 F5000 ; z up
G1 X202 Y36 ; near right
G1 Z0 F250 ; z down
M0 ; pause
G1 Z5 F5000 ; z up
//G28 ; home axes
G1 X32 Y36 ; near left
M84 ; disable motors

