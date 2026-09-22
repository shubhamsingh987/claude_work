// ESP32 + LiPo + mic + speaker mesh enclosure
//
// Two-part screw-together box. Base holds the LiPo pouch cell loose in the
// bottom of the cavity, with a pair of internal rails above it that the
// ESP32 dev board's edges rest/slide onto. Lid carries a perforated mesh
// grille over an internal speaker pocket (sound fires up through the mesh)
// plus a single mic hole. Four corner posts + self-tap screws join the two
// halves.
//
// ASSUMPTIONS TO VERIFY (no physical parts on hand to measure against):
//   - BOARD_L/BOARD_W/BOARD_T (55 x 28 x 8mm): generic 38-pin wide "ESP32
//     DevKit v1" clone. Narrow 30-pin clones are ~25.4mm wide instead —
//     measure yours and edit.
//   - USB_EDGE_OFFSET / USB_CUTOUT_W: USB-C/micro-USB port assumed centered
//     across the board's short edge. Verify against your board.
//   - BATTERY_L/W/T (35 x 30 x 5.5mm incl. clearance): sized for a common
//     "503035" LiPo pouch cell (~500mAh). Swap in your cell's real size —
//     naming convention is thickness/width/length in mm x10, e.g. 503035 =
//     5.0mm x 30mm x 35mm.
//   - SPEAKER_D/SPEAKER_T (20 x 6mm): small round speaker. 23mm/28mm are
//     also common sizes — change SPEAKER_D if yours differs.
//   - MIC_D (6mm hole): sized for a bare electret capsule held against the
//     inside of the lid. If using an I2S breakout (INMP441 etc.) instead,
//     replace the mic hole with a rectangular cutout sized to that board.
//   - Nothing here checks board mounting-hole positions (devkit clones
//     vary), so the board is held by edge rails + friction, not screws.

// ---- Component dimensions (EDIT THESE to match your parts) ----
BOARD_L = 55;   BOARD_W = 28;   BOARD_T = 8;
USB_EDGE_OFFSET = 14;   // usb port center from board centerline, along width
USB_CUTOUT_W = 10;

BATTERY_L = 35; BATTERY_W = 30; BATTERY_T = 5.5;

SPEAKER_D = 20; SPEAKER_T = 6;
MIC_D = 6;

// ---- Shell parameters ----
WALL = 2;
CLR  = 0.8;                 // fit clearance around internal parts
CORNER_R = 3;

RAIL_W = 3; RAIL_H = 1.5;   // card-edge support rails for the PCB

CASE_L = max(BOARD_L, BATTERY_L) + 2*CLR + 2*WALL;   // 59
CASE_W = max(BOARD_W, BATTERY_W) + 2*CLR + 2*WALL;   // 35.6
BASE_H = WALL + BATTERY_T + CLR + RAIL_H + BOARD_T + CLR;
LID_H  = WALL + CLR + SPEAKER_T;   // pocket clearance + speaker + solid top ceiling

LIP_H = 2; LIP_T = 1.2;     // stepped friction lip, lid seats over this

POST_OD = 5; SCREW_PILOT_D = 2.0; SCREW_CLR_D = 2.6; POST_INSET = 5;

$fn = 32;

module rounded_rect(l, w, r) {
    hull() for (x=[r, l-r], y=[r, w-r]) translate([x, y]) circle(r=r);
}

module mesh_grille(l, w, hole_d=2.4, pitch=4.2) {
    // staggered circular perforation pattern, inset from the panel edge
    for (yi = [hole_d : pitch*0.87 : w-hole_d])
        for (xi = [hole_d : pitch : l-hole_d]) {
            row = round(yi / (pitch*0.87));
            x = xi + (row % 2 == 0 ? 0 : pitch/2);
            if (x > hole_d/2 && x < l - hole_d/2)
                translate([x, yi]) circle(d=hole_d);
        }
}

module post_positions() {
    for (x = [POST_INSET, CASE_L-POST_INSET])
        for (y = [POST_INSET, CASE_W-POST_INSET])
            translate([x, y]) children();
}

module base_shell() {
    difference() {
        union() {
            linear_extrude(BASE_H) rounded_rect(CASE_L, CASE_W, CORNER_R);
            translate([0, 0, BASE_H])
                linear_extrude(LIP_H)
                difference() {
                    rounded_rect(CASE_L, CASE_W, CORNER_R);
                    translate([LIP_T, LIP_T])
                        rounded_rect(CASE_L-2*LIP_T, CASE_W-2*LIP_T, max(CORNER_R-LIP_T, 0.5));
                }
        }

        // hollow interior
        translate([WALL, WALL, WALL])
            linear_extrude(BASE_H)
                rounded_rect(CASE_L-2*WALL, CASE_W-2*WALL, max(CORNER_R-WALL, 0.5));

        // USB cutout in one short end wall, at board-rail height
        translate([-1, CASE_W/2 - USB_CUTOUT_W/2, WALL + BATTERY_T + CLR + RAIL_H])
            cube([WALL+2, USB_CUTOUT_W, BOARD_T + 1]);

        // screw pilot holes down through the posts
        post_positions()
            translate([0, 0, WALL])
                cylinder(h=BASE_H, d=SCREW_PILOT_D);
    }

    // corner posts (solid, pilot hole already cut above)
    post_positions()
        cylinder(h=BASE_H, d=POST_OD);

    // PCB edge rails along the two long interior walls
    for (y = [WALL+CLR-RAIL_W, CASE_W-WALL-CLR])
        translate([WALL+CLR, y, WALL+BATTERY_T+CLR])
            cube([CASE_L-2*(WALL+CLR), RAIL_W, RAIL_H]);
}

module lid_shell() {
    difference() {
        linear_extrude(LID_H) rounded_rect(CASE_L, CASE_W, CORNER_R);

        // recess that fits down over the base's friction lip
        translate([WALL+LIP_T, WALL+LIP_T, -1])
            linear_extrude(LIP_H+1)
                rounded_rect(CASE_L-2*(WALL+LIP_T), CASE_W-2*(WALL+LIP_T), max(CORNER_R-WALL-LIP_T, 0.5));

        // speaker pocket, open at the bottom (interior) face, stopping just
        // short of the top so a solid WALL-thick ceiling remains to carry
        // the mesh grille perforation
        translate([CASE_L/2, CASE_W/2 + 4, -1])
            cylinder(h=(LID_H-WALL)+1, d=SPEAKER_D+2*CLR);
        // mesh grille perforation through that ceiling, into the pocket
        translate([CASE_L/2 - SPEAKER_D/2, CASE_W/2 + 4 - SPEAKER_D/2, LID_H-WALL])
            linear_extrude(WALL+1)
                mesh_grille(SPEAKER_D, SPEAKER_D);

        // mic hole, offset to one side away from the speaker
        translate([POST_INSET + 4, CASE_W/2 - 10, -1])
            cylinder(h=LID_H+2, d=MIC_D);

        // screw clearance holes matching the base posts
        post_positions()
            translate([0, 0, -1])
                cylinder(h=LID_H+2, d=SCREW_CLR_D);
    }
}

// ---- Output selection ----
part = "all"; // "base" | "lid" | "all"

if (part == "base")
    base_shell();

if (part == "lid")
    lid_shell();

if (part == "all") {
    base_shell();
    translate([CASE_L + 10, 0, 0])
        lid_shell();
}
