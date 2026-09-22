// Meshtastic-style handheld enclosure  (rev 2 - real part dimensions)
//
//   ESP32 devkit 52x28, MAX98357A 18x18, 28mm round speaker (grille sized up),
//   INMP441-style mic 12.5mm round, LiPo 52x34x10, battery indicator 31.5x20,
//   6x6x3.8 tactile PTT, 10.5x5.8x5.2 toggle (bolted from outside, M3 @14mm),
//   panel-mount USB-C jack (flange 20.1 wide, 14.3 deep) clamped at the split line, SMA antenna hole.
//
// Parts (export with part=...):
//   base    - floor, battery bay, ESP32 shelf, strap posts, PTT seat, toggle pad
//   lid     - screen, speaker + 2 slide locks, mic, amp pocket, antenna hole
//   strap   - hold-down plank for the ESP32 (2x M3 into heat-set inserts)
//   slider  - speaker lock (print 2)
//   cap     - PTT button cap (slides down into the wall slot, lid locks it)
//
// Fasteners: M3 heat-set inserts (hole 4.2mm x 6mm deep) in the 4 corner posts
// and 2 strap posts. Case screws: M3x12 pan head from the top, counterbored.
// Strap screws: M3x8. Toggle: 2x M3x10 + nuts (nut traps are in the wall pad).
//
// ASSUMED (edit + re-export): ESP32 has NO header pins on its underside (it
// sits 0.5mm above the battery). If you soldered headers on the bottom, raise
// ESP_GAP by the pin height. USB-C jack: flange height/thickness + ear holes are GUESSED - measure.

// ---------------- parameters ----------------
IL = 101; IW = 48;                 // interior length / width
WALL = 2.2;  CR = 4;
F = 2.4;                           // floor
BATT_L = 52; BATT_W = 34; BATT_T = 10; BATT_X0 = 8;
ESP_L = 52;  ESP_W = 28;  ESP_X0 = 1;  ESP_GAP = 0.5;  PCB_T = 1.6;
ZB_BOT = F + BATT_T + ESP_GAP;     // underside of ESP32 PCB
ZB = ZB_BOT + PCB_T;               // top of ESP32 PCB
SPLIT = ZB + 3.7;                  // base height
LID_INNER = 7.5; CEIL = 2.4;
LH = LID_INNER + CEIL;
LIP_H = 2; LIP_T = 1.1;

INS_D = 4.2; INS_DEPTH = 6;        // M3 heat-set insert hole
M3_CLR = 3.4; CB_D = 6.4; CB_H = 2.6;

CORNER = 3.5; POST_D = 7.5;

// strap
STRAP_X = 24; STRAP_W = 8; STRAP_T = 3.5; STRAP_HOLE_DY = 20.8; STRAP_RELIEF = 2.5;
STRAP_BLK_Y = 17.6;                // strap post inner face, from center

// toggle (y=0 wall) / PTT (y=IW wall)
TOG_X = 75; TOG_Z = 11; TOG_W = 10.8; TOG_H = 6.1; TOG_SPACING = 14;
TOG_PAD = 5.6; TOG_BODY_DEPTH = 5.2;
// PTT: printed T-cap slides DOWN into a slot from the open top of the wall; the lid
// then closes over it. A lid block presses on the cap so it can't lift out.
PTT_X = 75; PTT_B = 6.3; PTT_DEPTH = 3.8; PTT_SKIN = 1.2; PTT_PAD = 4.8;
CAP_FL_W = 9; CAP_FL_H = 9; CAP_FL_T = 1.6; CAP_STEM_W = 5.4; CAP_STEM_OUT = 1.0; CAP_TOP_GAP = 1.2;
PTT_Z = SPLIT - CAP_TOP_GAP - CAP_FL_H/2;   // switch / cap centre height

// battery indicator (back / floor)
IND_W = 31.5; IND_H = 20; IND_X0 = 62; IND_WIN_L = 27.5; IND_WIN_W = 16.5; IND_REC = 1.2;

// USB-C panel jack (measured: 14.3 mm total depth, 20.1 mm flange width). Its mouth sits on the split line.
UC_DEPTH = 14.3; UC_FL_W = 20.1; UC_FL_H = 10.6; UC_FL_T = 1.2; UC_BODY_W = 13; UC_BACK = 3;
UC_MOUTH_W = 9.6; UC_MOUTH_H = 3.6;

// OLED
OLED_W = 27.3; OLED_X0 = 3.5; OLED_HX = 23.5; OLED_HY = 23.8; OLED_POST_H = 2.0;
OLED_WIN_W = 13; OLED_WIN_H = 24; OLED_WIN_DX = 4.5;   // PORTRAIT (window tall, pins toward the near end)

// speaker (28mm; pocket + grille sized for up to ~30mm)
SPK_CX = 49; SPK_POCKET = 30.4; SPK_RING_H = 5; SPK_FLANGE = 1.5; SPK_GRILLE_R = 12.8;
SL_W = 11; SL_L = 8; SL_T = 1.6; RAIL_GAP = 9; RAIL_T = 2.4; SLOT_DEPTH = 1.2;

// mic (12.5mm round), amp (18x18), antenna
MIC_X = 70; MIC_Y = 36; MIC_D = 12.9; MIC_PORT_D = 3.2;
AMP_X = 76; AMP_Y = 17.5; AMP_B = 18.4;
ANT_X = 19; ANT_Y = 43; ANT_D = 6.5;

$fn = 40;
CY = IW/2;
OLED_CX = OLED_X0 + OLED_W/2;
CASE_L = IL + 2*WALL;  CASE_W = IW + 2*WALL;

// ---------------- helpers ----------------
module rr(l, w, r) { hull() for (x=[r, l-r], y=[r, w-r]) translate([x, y]) circle(r=r); }
module outline(i=0) translate([-WALL+i, -WALL+i]) rr(CASE_L-2*i, CASE_W-2*i, max(CR-i, 0.6));
module body(h, cham_bottom=0, cham_top=0) {
    hull() {
        translate([0,0,cham_bottom]) linear_extrude(h-cham_bottom-cham_top) outline(0);
        if (cham_bottom>0) linear_extrude(0.01) outline(cham_bottom);
        if (cham_top>0) translate([0,0,h-0.01]) linear_extrude(0.01) outline(cham_top);
    }
}
module corners() { for (x=[CORNER, IL-CORNER], y=[CORNER, IW-CORNER]) translate([x,y]) children(); }
module hex_grille(r_max, d=2.6, pitch=3.8) {
    for (j=[-8:8]) for (i=[-8:8]) {
        x = i*pitch + (abs(j)%2)*pitch/2;  y = j*pitch*0.866;
        if (sqrt(x*x+y*y) < r_max) translate([x,y]) circle(d=d, $fn=6);
    }
}
// Meshtastic-ish node graph engraved on the lid top (over the amp bay)
NODES = [[68,11],[75,22],[82,12],[70,24],[80,24.5]];
EDGES = [[0,1],[1,2],[0,3],[1,3],[1,4],[2,4]];
module mesh_art() {
    for (n=NODES) translate(n) circle(d=2.4, $fn=20);
    for (e=EDGES) hull() { translate(NODES[e[0]]) circle(d=0.8,$fn=12); translate(NODES[e[1]]) circle(d=0.8,$fn=12); }
}

// ---------------- base ----------------
module base() {
    ey0 = CY - ESP_W/2;
    difference() {
        union() {
            difference() {
                body(SPLIT, cham_bottom=1);
                translate([0,0,F]) linear_extrude(SPLIT) outline(WALL);
            }
            // ESP32 shelf under the overhanging end (battery starts further in) + side guides
            translate([0, CY-16.4, F-0.01]) cube([7.6, 32.8, ZB_BOT-F+0.01]);
            for (y=[ey0-1.4, ey0+ESP_W+0.2])
                translate([ESP_X0, y, ZB_BOT-0.01]) cube([6.6, 1.2, 3.6]);
            // battery stop + side ribs
            translate([BATT_X0+BATT_L+0.3, CY-BATT_W/2-0.3, F-0.01]) cube([1.2, BATT_W+0.6, 4]);
            for (x=[12, 48], y=[CY-BATT_W/2-1.5, CY+BATT_W/2+0.3])
                translate([x, y, F-0.01]) cube([4, 1.2, 4]);
            // strap posts (solid beside the battery) with heat-set insert holes
            for (s=[0,1])
                translate([STRAP_X-STRAP_W/2, s==0 ? -0.5 : CY+STRAP_BLK_Y, F-0.01])
                    cube([STRAP_W, s==0 ? CY-STRAP_BLK_Y+0.5 : IW-CY-STRAP_BLK_Y+0.5, ZB-F+0.01]);
            // corner posts
            corners() cylinder(h=SPLIT, d=POST_D);
            // alignment tongue
            translate([0,0,SPLIT-0.01]) linear_extrude(LIP_H) difference() { outline(WALL-LIP_T); outline(WALL); }
            // USB-C bay: solid block round the jack + back-stop wall (takes the plug force)
            translate([IL-UC_DEPTH-0.3-UC_BACK, CY-UC_FL_W/2-0.3-2.4, F-0.01])
                cube([UC_DEPTH+0.3+UC_BACK+0.5, UC_FL_W+0.6+4.8, SPLIT-F+0.01]);
            // toggle pad (y=0 wall), solid to the floor
            translate([TOG_X-11.5, -0.5, F-0.01]) cube([23, TOG_PAD+0.5, TOG_Z+6-F]);
            // PTT pad (y=IW wall)
            translate([PTT_X-8, IW-PTT_PAD, F-0.01]) cube([16, PTT_PAD+0.5, SPLIT-F+0.01]);
        }
        // heat-set insert holes: corners + strap posts
        corners() translate([0,0,SPLIT-INS_DEPTH]) cylinder(h=INS_DEPTH+LIP_H+1, d=INS_D);
        for (y=[CY-STRAP_HOLE_DY, CY+STRAP_HOLE_DY])
            translate([STRAP_X, y, ZB-INS_DEPTH]) cylinder(h=INS_DEPTH+1, d=INS_D);
        // ESP32 USB (near end, open at the top so the lid closes it)
        translate([-WALL-1, CY-5.5, ZB-0.6]) cube([WALL+2, 11, SPLIT+3-(ZB-0.6)]);
        // toggle: body cutout, 2x M3 through holes 14mm apart, nut traps deeper than the body
        translate([TOG_X-TOG_W/2, -WALL-1, TOG_Z-TOG_H/2]) cube([TOG_W, WALL+1+ (TOG_BODY_DEPTH-WALL) + 0.2, TOG_H]);
        for (dx=[-TOG_SPACING/2, TOG_SPACING/2]) {
            translate([TOG_X+dx, -WALL-1, TOG_Z]) rotate([-90,0,0]) cylinder(h=TOG_PAD+WALL+2, d=M3_CLR);
            translate([TOG_X+dx, TOG_BODY_DEPTH-WALL+0.2, TOG_Z]) rotate([-90,0,0]) cylinder(h=TOG_PAD, d=6.7, $fn=6);
        }
        // PTT: switch seat (open to the inside), cap flange pocket + stem channel (both open at the top)
        sf = IW + WALL - PTT_SKIN;                 // y of the cap-pocket outer face
        translate([PTT_X-PTT_B/2, IW-PTT_PAD-0.5, PTT_Z-PTT_B/2]) cube([PTT_B, sf-(CAP_FL_T+0.2)-(IW-PTT_PAD-0.5)+0.01, PTT_B]);
        translate([PTT_X-(CAP_FL_W+0.4)/2, sf-CAP_FL_T-0.2, PTT_Z-CAP_FL_H/2-0.2]) cube([CAP_FL_W+0.4, CAP_FL_T+0.2, SPLIT+3-(PTT_Z-CAP_FL_H/2-0.2)]);
        translate([PTT_X-(CAP_STEM_W+0.4)/2, sf-0.01, PTT_Z-CAP_FL_H/2+0.4]) cube([CAP_STEM_W+0.4, PTT_SKIN+1, SPLIT+3-(PTT_Z-CAP_FL_H/2+0.4)]);
        // battery indicator: back window + seat recess
        translate([IND_X0, CY-IND_W/2-0.2, F-IND_REC]) cube([IND_H+0.4, IND_W+0.4, IND_REC+0.1]);
        translate([IND_X0+IND_H/2+0.2-IND_WIN_W/2, CY-IND_WIN_L/2, -1]) cube([IND_WIN_W, IND_WIN_L, F+2]);
        // USB-C: flange recess, body pocket (open top), deeper rear pocket + wire tunnel through the back-stop, mouth notch
        translate([IL-UC_FL_T-0.2, CY-UC_FL_W/2-0.3, SPLIT-UC_FL_H/2-0.2]) cube([UC_FL_T+0.3, UC_FL_W+0.6, UC_FL_H/2+0.2+LIP_H+3]);
        translate([IL-UC_DEPTH-0.3, CY-UC_BODY_W/2, SPLIT-2.3]) cube([UC_DEPTH+0.3, UC_BODY_W, 2.3+LIP_H+3]);
        translate([IL-UC_DEPTH-0.3, CY-4.5, SPLIT-7]) cube([5, 9, 5]);
        translate([IL-UC_DEPTH-0.3-UC_BACK-1, CY-4, SPLIT-7]) cube([UC_BACK+2, 8, 3]);
        translate([IL-1, CY-UC_MOUTH_W/2, SPLIT-UC_MOUTH_H/2]) cube([WALL+2, UC_MOUTH_W, UC_MOUTH_H/2+LIP_H+3]);

    }
}

// ---------------- lid (modeled ceiling up, z=0 at split plane) ----------------
module lid() {
    zc = LH - CEIL;
    difference() {
        union() {
            difference() {
                body(LH, cham_top=1.2);
                translate([0,0,-1]) linear_extrude(zc+1) outline(WALL);
                translate([0,0,-1]) linear_extrude(LIP_H+1.3) outline(WALL-LIP_T-0.15);
            }
            corners() cylinder(h=zc+0.01, d=POST_D);
            // OLED screw posts
            for (sx=[-1,1], sy=[-1,1])
                translate([OLED_CX+sx*OLED_HX/2, CY+sy*OLED_HY/2, zc-OLED_POST_H]) cylinder(h=OLED_POST_H+0.01, d=4.6);
            // speaker: ring (open at the two slider gaps) + slide-lock rails
            translate([SPK_CX, CY, zc-SPK_RING_H]) difference() {
                cylinder(h=SPK_RING_H+0.01, d=SPK_POCKET+2.4);
                translate([0,0,-1]) cylinder(h=SPK_RING_H+2, d=SPK_POCKET);
                translate([-RAIL_GAP/2, -30, -1]) cube([RAIL_GAP, 60, SPK_RING_H+2]);
            }
            for (s=[-1,1], sx=[-1,1])
                translate([SPK_CX + sx*(RAIL_GAP/2+RAIL_T/2), s<0 ? 0 : CY+SPK_POCKET/2-0.2, zc-4.6])
                    translate([-RAIL_T/2, 0, 0]) cube([RAIL_T, s<0 ? CY-SPK_POCKET/2+0.2 : IW-CY-SPK_POCKET/2+0.2, 4.61]);
            // mic ring
            translate([MIC_X, MIC_Y, zc-3.5]) difference() {
                cylinder(h=3.51, d=MIC_D+1.6);
                translate([0,0,-1]) cylinder(h=6, d=MIC_D);
            }
            // amp pocket frame with pin-side gaps
            translate([AMP_X, AMP_Y, zc-3]) difference() {
                translate([-(AMP_B+1.6)/2, -(AMP_B+1.6)/2, 0]) cube([AMP_B+1.6, AMP_B+1.6, 3.01]);
                translate([-AMP_B/2, -AMP_B/2, -1]) cube([AMP_B, AMP_B, 5]);
                translate([-4, -12, -1]) cube([8, 24, 2.6]);
                translate([-12, -4, -1]) cube([24, 8, 2.6]);
            }
            // PTT cap hold-down: drops into the open slot and presses the cap top
            translate([PTT_X-(CAP_FL_W)/2+0.4, IW-0.6, -(CAP_TOP_GAP-0.1)]) cube([CAP_FL_W-0.8, 1.4, zc+CAP_TOP_GAP-0.1+0.01]);
            // USB-C: rib holding the flange against the wall + posts pressing the jack body
            translate([IL-UC_FL_T-0.2-1.6, CY-UC_FL_W/2+1, 1.9]) cube([1.4, UC_FL_W-2, zc-1.9+0.01]);
            for (x=[IL-10, IL-6], s=[-1,1]) translate([x-1, CY+s*5.2-1, 1.75]) cube([2, 2, zc-1.75+0.01]);
        }
        // case screws through corners, counterbored
        corners() { translate([0,0,-1]) cylinder(h=LH+2, d=M3_CLR);
                    translate([0,0,LH-CB_H]) cylinder(h=CB_H+1, d=CB_D); }
        // OLED window + post pilots
        translate([OLED_CX+OLED_WIN_DX, CY, zc-1]) linear_extrude(CEIL+2)
            offset(r=1) square([OLED_WIN_W-2, OLED_WIN_H-2], center=true);
        for (sx=[-1,1], sy=[-1,1])
            translate([OLED_CX+sx*OLED_HX/2, CY+sy*OLED_HY/2, zc-OLED_POST_H-1]) cylinder(h=OLED_POST_H+1.5, d=1.7);
        // slider slots in the rails (cut after union)
        for (s=[-1,1], sx=[-1,1])
            translate([SPK_CX + sx*(RAIL_GAP/2+SLOT_DEPTH/2-0.01) - SLOT_DEPTH/2 + (sx>0?0:0), s<0 ? -1 : CY+SPK_POCKET/2-0.5, zc-3.3])
                cube([SLOT_DEPTH+0.01, s<0 ? CY-SPK_POCKET/2+1.5 : IW-CY-SPK_POCKET/2+1.5, 1.8]);
        // mic port, speaker grille, antenna
        translate([MIC_X, MIC_Y, zc-1]) cylinder(h=CEIL+2, d=MIC_PORT_D);
        translate([SPK_CX, CY, zc-1]) linear_extrude(CEIL+2) hex_grille(SPK_GRILLE_R);
        translate([ANT_X, ANT_Y, zc-1]) cylinder(h=CEIL+2, d=ANT_D);
        // USB-C mouth notch in the lid wall (upper half; base has the lower half)
        translate([IL-1, CY-UC_MOUTH_W/2, -1]) cube([WALL+2, UC_MOUTH_W, UC_MOUTH_H/2+1]);
        // engraved mesh graph
        translate([0,0,LH-0.5]) linear_extrude(1) mesh_art();
    }
}

// ---------------- strap plank (modeled bottom-down) ----------------
module strap() {
    len = 2*(STRAP_HOLE_DY+3.6);
    difference() {
        translate([-STRAP_W/2, -len/2, 0]) cube([STRAP_W, len, STRAP_T]);
        for (dy=[-STRAP_HOLE_DY, STRAP_HOLE_DY]) {
            translate([0, dy, -1]) cylinder(h=STRAP_T+2, d=M3_CLR);
            translate([0, dy, STRAP_T-2]) cylinder(h=3, d=CB_D);
        }
        // relief over the board centre so passives / module edge aren't crushed
        translate([-STRAP_W/2-1, -(STRAP_BLK_Y-6), -1]) cube([STRAP_W+2, 2*(STRAP_BLK_Y-6), STRAP_RELIEF+1]);
    }
}

// ---------------- PTT cap (T shape, print lying on its back) ----------------
module ptt_cap() {
    // x = width, y = thickness toward outside, z = height. Print with the flange face down.
    cube([CAP_FL_W, CAP_FL_T, CAP_FL_H]);
    translate([(CAP_FL_W-CAP_STEM_W)/2, CAP_FL_T, 0])
        cube([CAP_STEM_W, PTT_SKIN+CAP_STEM_OUT, CAP_FL_H-0.2]);
}

// ---------------- speaker slide lock (print 2) ----------------
module slider() {
    cube([SL_W, SL_L, SL_T]);
    translate([SL_W/2-2, 0.6, -1.2]) cube([4, 2.4, 1.3]);   // finger grip underneath
}

// ---------------- output ----------------
part = "all";  // "base" | "lid" | "strap" | "slider" | "all"
if (part == "base")   base();
if (part == "lid")    translate([0, IW, LH]) rotate([180,0,0]) lid();     // printed flipped
if (part == "strap")  strap();
if (part == "slider") slider();
if (part == "cap")    rotate([90,0,0]) ptt_cap();   // flange flat on the bed, stem up
if (part == "all") {
    base();
    translate([0, CASE_W + 8, 0]) translate([0, IW, LH]) rotate([180,0,0]) lid();
    translate([10, -CASE_W-10, 0]) rotate([0,0,90]) strap();
    for (i=[0,1]) translate([30+i*14, -CASE_W-10, 0]) slider();
    translate([70, -CASE_W-10, 0]) rotate([90,0,0]) ptt_cap();
}
