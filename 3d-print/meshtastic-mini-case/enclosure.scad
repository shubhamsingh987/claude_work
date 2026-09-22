// Mini Meshtastic walkie-talkie enclosure  (rev 3 - compact, no screen)
//
//   Held portrait: bottom end (x=0)  = USB-C panel jack, screwed from OUTSIDE
//                  top end (x=IL)    = SMA antenna hole only (ESP32 USB notch optional)
//                  front (lid)       = speaker grille (middle), mic (bottom)
//                  left side         = toggle switch, right side = PTT cap
//   Stack (back to front): LiPo 52x34x10 -> ESP32 52x28 (strap-held) -> lid layer.
//
// Parts (export with part=...):
//   base    lid    strap    slider (print 2)    cap (PTT button, print 1)
//
// Fasteners: M3 heat-set inserts (hole 4.2 x 6) in 4 corner posts + 2 strap posts.
//   Case: M3x12 from the lid top, counterbored.   Strap: M3x8.
//   Toggle: 2x M3x10 + nuts (nut traps in the wall pad).   USB-C jack: 2x M2 self-tap.
//
// ASSUMED (edit + re-export): ESP32 has no header pins on its underside; USB-C jack
// flange 10.6 high x 1.2 thick, ear holes 16 mm apart, M2 - measure and edit UC_*.

// ---------------- parameters ----------------
IL = 76;  IW = 44;                 // interior length (tall) / width
WALL = 2.2;  CR = 5;
F = 2.4;
BATT_L = 52; BATT_W = 34; BATT_T = 10; BATT_X0 = 15;
ESP_L = 52;  ESP_W = 28;  ESP_GAP = 0.5;  PCB_T = 1.6;
ZB_BOT = F + BATT_T + ESP_GAP;
ZB = ZB_BOT + PCB_T;
SPLIT = ZB + 5;
LID_INNER = 6; CEIL = 2.4;
LH = LID_INNER + CEIL;
LIP_H = 2; LIP_T = 1.1;

INS_D = 4.2; INS_DEPTH = 6;
M3_CLR = 3.4; CB_D = 5.9; CB_H = 2.2;
CORNER = 3.1; POST_D = 6.6;

// strap (runs across the width, between two posts beside the battery)
STRAP_X = 45; STRAP_W = 8; STRAP_T = 3.5; STRAP_HOLE_DY = 19.5; STRAP_RELIEF = 2.5;

// toggle (y=0 wall) / PTT (y=IW wall)
TOG_X = 27; TOG_Z = 16; TOG_W = 10.8; TOG_H = 6.1; TOG_SPACING = 14;
TOG_PAD = 5.6; TOG_BODY_DEPTH = 5.2;
PTT_X = 30; PTT_B = 6.3; PTT_DEPTH = 3.8; PTT_SKIN = 1.2; PTT_PAD = 4.8;
CAP_FL_W = 9; CAP_FL_H = 9; CAP_FL_T = 1.6; CAP_STEM_W = 5.4; CAP_STEM_OUT = 1.0; CAP_TOP_GAP = 1.2;
PTT_Z = SPLIT - CAP_TOP_GAP - CAP_FL_H/2;

// USB-C panel jack, bottom end wall, screwed on from outside
UC_DEPTH = 14.3; UC_FL_W = 20.1; UC_FL_H = 10.6; UC_FL_T = 1.2;
UC_HOLE_SP = 16; UC_HOLE_D = 1.8; UC_MOUTH_W = 9.6; UC_MOUTH_H = 3.6; UC_BODY_W = 13.5;
JZ = 8.5;                                   // jack centre height

// speaker (28mm; pocket + grille sized for up to ~30mm) + two slide locks
SPK_CX = IL/2; SPK_POCKET = 30.4; SPK_RING_H = 5; SPK_GRILLE_R = 12.8;
SL_W = 11; SL_L = 8; SL_T = 1.6; RAIL_GAP = 9; RAIL_T = 2.4; SLOT_DEPTH = 1.2;

// mic (12.5mm round), amp (18x18), antenna (SMA on the top end wall)
MIC_X = 10; MIC_Y = IW/2; MIC_D = 12.9; MIC_PORT_D = 3.2;
ESP_USB_CUTOUT = false;   // true = notch in the top end wall for the ESP32's own USB port
ANT_D = 6.5; ANT_Z = 3.6;
ANT_LEN = 40; ANT2_PLUG = 6.2; ANT2_Y = IW-11; ANT2_Z = 13;   // fake antenna mount, top end, right side
RIDGE_H = 0.8;                // raised bumper on the lid face
GRIP_D = 0.7; GRIP_W = 1.4; GRIP_P = 3.6;   // side grip grooves

$fn = 40;
CY = IW/2;
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
// wall pad with a 45-degree underside (prints without support). u = depth from wall, along x = w
module wedge(w, t, z0) {
    rotate([90,0,90]) linear_extrude(w)
        polygon([[-0.5,SPLIT],[t,SPLIT],[t,z0],[-0.5,z0-t-0.5]]);
}
// ---- fake screen (recessed panel with raised "UI" islands) + Meshtastic touches ----
SCR_SX = 65.5; SCR_SY = IW/2; SCR_W = 28; SCR_H = 13.5;   // screen is landscape when held upright
module rrect(w, h, r) offset(r=r) square([w-2*r, h-2*r], center=true);
module screen_frame() translate([SCR_SX, SCR_SY]) rotate(-90) children();  // local u = screen-right, v = screen-up
// mountains + sun + birds scene (raised islands standing in the recessed panel)
module stroke(a, b, d=0.6) hull() { translate(a) circle(d=d, $fn=10); translate(b) circle(d=d, $fn=10); }
module bird(x, y, k=1) translate([x,y]) scale(k) {
    stroke([-1.8,0.3],[-0.9,0.9]); stroke([-0.9,0.9],[0,0.2]); stroke([0,0.2],[0.9,0.9]); stroke([0.9,0.9],[1.8,0.3]);
}
module mtn_back()  polygon([[-15,-8],[-15,-1.5],[-11,1.5],[-8.5,-0.5],[-5,3.6],[-1,-1],[2,2],[5,-1.8],[8,0.4],[11,-1.2],[15,-3],[15,-8]]);
module mtn_front() polygon([[-15,-8],[-15,-4.5],[-10,-1.6],[-6,-4.2],[-2,-2.2],[2,-5],[6,-3],[10,-5.2],[15,-4],[15,-8]]);
module screen_ui() {
    intersection() {
        rrect(SCR_W-1.2, SCR_H-1.2, 0.8);
        union() {
            difference() { mtn_back(); offset(delta=0.5) mtn_front(); }
            mtn_front();
            translate([9.5,3.6]) circle(d=3.4, $fn=24);                 // sun
            bird(-8,4.6,1); bird(-3.2,5.3,0.7); bird(2.4,3.9,0.85);       // birds
        }
    }
}
module lid_art() {
    // screen recess (0.6 deep) with UI left standing, bezel ring, speaker ring
    translate([0,0,LH-0.6]) linear_extrude(1) screen_frame() difference() { rrect(SCR_W, SCR_H, 1); screen_ui(); }
    translate([0,0,LH-0.4]) linear_extrude(1) screen_frame() difference() { rrect(SCR_W+3.2, SCR_H+3.2, 2.2); rrect(SCR_W+1.6, SCR_H+1.6, 1.4); }
    translate([SPK_CX, CY, LH-0.4]) linear_extrude(1) difference() { circle(r=SPK_GRILLE_R+1.6); circle(r=SPK_GRILLE_R+0.8); }
    // wordmarks on the side strips
    translate([SPK_CX, 2.4, LH-0.4]) linear_extrude(1) text("MESHTASTIC", size=3, halign="center", font="Liberation Sans:style=Bold");
    translate([SPK_CX, IW-5.2, LH-0.4]) linear_extrude(1) text("GANGSTA TALK", size=3, halign="center", font="Liberation Sans:style=Bold");
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
            // ESP32 shelf under the top end + side guides
            translate([IL-7.8, CY-16, F-0.01]) cube([8.1, 32, ZB_BOT-F+0.01]);
            for (y=[ey0-1.4, ey0+ESP_W+0.2])
                translate([IL-7.2, y, ZB_BOT-0.01]) cube([6.2, 1.2, 3.6]);
            // battery stop + side ribs
            translate([BATT_X0-1.3, CY-BATT_W/2-0.3, F-0.01]) cube([1.2, BATT_W+0.6, 4]);
            for (x=[30, 56], y=[CY-BATT_W/2-1.5, CY+BATT_W/2+0.3])
                translate([x, y, F-0.01]) cube([4, 1.2, 4]);
            // strap posts: solid to the floor beside the battery + a thin bridge above it
            for (s=[-1,1]) {
                y0 = s<0 ? -0.5 : CY+BATT_W/2+0.2;
                y1 = s<0 ? CY-BATT_W/2-0.2 : IW+0.5;
                translate([STRAP_X-STRAP_W/2, y0, F-0.01]) cube([STRAP_W, y1-y0, ZB-F+0.01]);
                b0 = s<0 ? CY-BATT_W/2-0.2-3 : CY+BATT_W/2+0.2;   // bridge over the battery edge
                translate([STRAP_X-STRAP_W/2, b0+(s<0?0:-0.01), ZB_BOT]) cube([STRAP_W, 3.01, ZB-ZB_BOT+0.01]);
            }
            corners() cylinder(h=SPLIT, d=POST_D);
            translate([0,0,SPLIT-0.01]) linear_extrude(LIP_H) difference() { outline(WALL-LIP_T); outline(WALL); }
            // toggle pad (y=0 wall) and PTT pad (y=IW wall), wedge-supported
            translate([TOG_X-11.5, 0, 0]) wedge(23, TOG_PAD, TOG_Z-3.6);
            translate([PTT_X-8, IW, 0]) mirror([0,1,0]) wedge(16, PTT_PAD, PTT_Z-5.3);
            // USB-C jack pad (bottom wall, inside)
            translate([-0.5, CY-11.5, F-0.01]) cube([6.5, 23, JZ+6-F]);
        }
        // grip grooves on the long sides (clear of the toggle / PTT) and the top end
        for (x=[46:GRIP_P:IL-8]) {
            translate([x, -WALL-0.01, 3]) cube([GRIP_W, GRIP_D+0.01, SPLIT-6]);
            translate([x, IW+WALL-GRIP_D, 3]) cube([GRIP_W, GRIP_D+0.01, SPLIT-6]);
        }
        for (y=[8:GRIP_P:IW-8]) translate([IL+WALL-GRIP_D, y, 3]) cube([GRIP_D+0.01, GRIP_W, SPLIT-6]);
        // heat-set insert holes
        corners() translate([0,0,SPLIT-INS_DEPTH]) cylinder(h=INS_DEPTH+LIP_H+1, d=INS_D);
        for (y=[CY-STRAP_HOLE_DY, CY+STRAP_HOLE_DY])
            translate([STRAP_X, y, ZB-INS_DEPTH]) cylinder(h=INS_DEPTH+1, d=INS_D);
        // ESP32 USB (top end, open at the top so the lid closes it)
        if (ESP_USB_CUTOUT) translate([IL-1, CY-5.5, ZB-0.6]) cube([WALL+2, 11, SPLIT+3-(ZB-0.6)]);
        // fake antenna socket (top end wall, right side)
        translate([IL-1, ANT2_Y, ANT2_Z]) rotate([0,90,0]) cylinder(h=WALL+3, d=ANT2_PLUG+0.3);
        // toggle: body cutout, 2x M3 holes 14mm apart, nut traps deeper than the body
        translate([TOG_X-TOG_W/2, -WALL-1, TOG_Z-TOG_H/2]) cube([TOG_W, WALL+1+(TOG_BODY_DEPTH-WALL)+0.2, TOG_H]);
        for (dx=[-TOG_SPACING/2, TOG_SPACING/2]) {
            translate([TOG_X+dx, -WALL-1, TOG_Z]) rotate([-90,0,0]) cylinder(h=TOG_PAD+WALL+2, d=M3_CLR);
            translate([TOG_X+dx, TOG_BODY_DEPTH-WALL+0.2, TOG_Z]) rotate([-90,0,0]) cylinder(h=TOG_PAD, d=6.7, $fn=6);
        }
        // PTT: switch seat, cap flange pocket + stem channel (open at the top)
        sf = IW + WALL - PTT_SKIN;
        translate([PTT_X-PTT_B/2, IW-PTT_PAD-0.5, PTT_Z-PTT_B/2]) cube([PTT_B, sf-(CAP_FL_T+0.2)-(IW-PTT_PAD-0.5)+0.01, PTT_B]);
        translate([PTT_X-(CAP_FL_W+0.4)/2, sf-CAP_FL_T-0.2, PTT_Z-CAP_FL_H/2-0.2]) cube([CAP_FL_W+0.4, CAP_FL_T+0.2, SPLIT+3-(PTT_Z-CAP_FL_H/2-0.2)]);
        translate([PTT_X-(CAP_STEM_W+0.4)/2, sf-0.01, PTT_Z-CAP_FL_H/2+0.4]) cube([CAP_STEM_W+0.4, PTT_SKIN+1, SPLIT+3-(PTT_Z-CAP_FL_H/2+0.4)]);
        // USB-C jack (bottom end): outer flange recess, mouth, body pocket, 2 ear screw holes from outside
        translate([-WALL-1, CY-UC_FL_W/2-0.3, JZ-UC_FL_H/2-0.3]) cube([1+UC_FL_T+0.05, UC_FL_W+0.6, UC_FL_H+0.6]);
        translate([-WALL-1, CY-UC_MOUTH_W/2, JZ-UC_MOUTH_H/2]) cube([WALL+1+7, UC_MOUTH_W, UC_MOUTH_H]);
        translate([-0.01, CY-UC_BODY_W/2, JZ-4.5]) cube([UC_DEPTH-UC_FL_T-0.8, UC_BODY_W, 9]);
        for (dy=[-UC_HOLE_SP/2, UC_HOLE_SP/2])
            translate([-WALL+UC_FL_T-0.1, CY+dy, JZ]) rotate([0,90,0]) cylinder(h=WALL+6, d=UC_HOLE_D);
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
            // rugged bumper: raised perimeter ridge + bolt-head bosses at the corners
            translate([0,0,LH-0.01]) linear_extrude(RIDGE_H+0.01) difference() { outline(1.5); outline(2.5); }
            intersection() {
                corners() translate([0,0,LH-0.01]) cylinder(h=RIDGE_H+0.01, d=9.4, $fn=8);
                translate([0,0,LH-0.01]) linear_extrude(RIDGE_H+0.01) outline(1.5);
            }
            // speaker ring (open at the two slider gaps) + slide-lock rails
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
            // PTT cap hold-down: drops into the open slot and presses the cap top
            translate([PTT_X-(CAP_FL_W)/2+0.4, IW-0.6, -(CAP_TOP_GAP-0.1)]) cube([CAP_FL_W-0.8, 1.4, zc+CAP_TOP_GAP-0.1+0.01]);
        }
        corners() { translate([0,0,-1]) cylinder(h=LH+2, d=M3_CLR);
                    translate([0,0,LH-CB_H]) cylinder(h=CB_H+1, d=CB_D); }
        // slider slots in the rails
        for (s=[-1,1], sx=[-1,1])
            translate([SPK_CX + sx*(RAIL_GAP/2+SLOT_DEPTH/2-0.01) - SLOT_DEPTH/2, s<0 ? -1 : CY+SPK_POCKET/2-0.5, zc-3.3])
                cube([SLOT_DEPTH+0.01, s<0 ? CY-SPK_POCKET/2+1.5 : IW-CY-SPK_POCKET/2+1.5, 1.8]);
        translate([MIC_X, MIC_Y, zc-1]) cylinder(h=CEIL+2, d=MIC_PORT_D);
        translate([SPK_CX, CY, zc-1]) linear_extrude(CEIL+2) hex_grille(SPK_GRILLE_R);
        // SMA antenna hole through the top end wall
        translate([IL-3, CY, ANT_Z]) rotate([0,90,0]) cylinder(h=WALL+5, d=ANT_D);
        lid_art();
    }
}

// ---------------- strap plank (modeled bottom-down) ----------------
module strap() {
    len = 2*(STRAP_HOLE_DY+2.3);
    difference() {
        translate([-STRAP_W/2, -len/2, 0]) cube([STRAP_W, len, STRAP_T]);
        for (dy=[-STRAP_HOLE_DY, STRAP_HOLE_DY]) translate([0, dy, -1]) cylinder(h=STRAP_T+2, d=M3_CLR);
        // relief over the board centre so passives aren't crushed
        translate([-STRAP_W/2-1, -(ESP_W/2-3), -1]) cube([STRAP_W+2, ESP_W-6, STRAP_RELIEF+1]);
    }
}

// ---------------- fake antenna (rubber-duck style, print lying down, glue spigot into the side hole) ----------------
module antenna() {
    R = 5.5;
    difference() {
        translate([0,0,R]) rotate([0,90,0]) union() {
            translate([0,0,-4.2]) cylinder(h=4.4, d=ANT2_PLUG);          // spigot (points -x)
            cylinder(h=4, d=11);                                       // collar
            translate([0,0,3.9]) cylinder(h=ANT_LEN-4, d1=9.4, d2=6.8);  // tapered body
            translate([0,0,ANT_LEN-0.1]) sphere(d=6.8);
            for (i=[0:4]) translate([0,0,6+i*5.2]) cylinder(h=1.4, d1=10.2-i*0.5, d2=10.2-i*0.5-0.2);  // grip rings
        }
        translate([-10,-10,-5]) cube([ANT_LEN+30, 20, 5.6]);          // flat bottom for the bed
    }
}

// ---------------- PTT cap (T shape) ----------------
module ptt_cap() {
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
part = "all";
if (part == "base")   base();
if (part == "lid")    translate([0, IW, LH]) rotate([180,0,0]) lid();     // printed flipped
if (part == "strap")  strap();
if (part == "slider") slider();
if (part == "antenna") antenna();
if (part == "cap")    rotate([90,0,0]) ptt_cap();
if (part == "all") {
    base();
    translate([0, CASE_W + 8, 0]) translate([0, IW, LH]) rotate([180,0,0]) lid();
    translate([10, -CASE_W-10, 0]) rotate([0,0,90]) strap();
    for (i=[0,1]) translate([30+i*14, -CASE_W-10, 0]) slider();
    translate([70, -CASE_W-10, 0]) rotate([90,0,0]) ptt_cap();
    translate([100, -CASE_W-20, 0]) antenna();
}
