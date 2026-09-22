// Pi 5 + Waveshare UPS HAT (D) + Waveshare 3.5" RPi LCD (A) stack enclosure
//
// Design: open-frame stack, not a fully closed box. A solid base tray holds
// the 21700 battery in an open-top channel and gives the UPS HAT its 4
// mounting bosses. Pi5 and the LCD then stack above on printed spacer tubes,
// all captured by 4 long M2.5 screws running from the base up through every
// board's mounting holes. Sides are left open on purpose: exact port cutout
// positions for these boards weren't available, so rather than guess and
// risk misaligned holes, every edge stays accessible on every tier.
//
// ASSUMPTIONS TO VERIFY BEFORE FULL ASSEMBLY (dry-fit the base + one spacer
// first):
//   - UPS_TO_PI_GAP (8.5mm): pogo-pin engagement height, not confirmed from
//     a datasheet drawing. GPIO_HEADER_GAP (8.5mm) is the real, documented
//     standard female-header height, so that one's solid.
//   - Battery channel is sized from the 21700 cell (21mm dia x 70mm) with
//     ~1mm radial clearance. Waveshare's own battery holder geometry wasn't
//     available, so this assumes the bare cell sits directly in the channel.

// ---- Standard Raspberry Pi / HAT board spec (confirmed) ----
BOARD_L   = 85;
BOARD_W   = 56;
HOLE_DX   = 58;    // hole spacing along length
HOLE_DY   = 49;    // hole spacing along width
HOLE_OFF  = 3.5;   // hole offset from board edge

// ---- Stack gaps ----
UPS_TO_PI_GAP   = 8.5;  // ASSUMPTION - verify against real pogo-pin height
GPIO_HEADER_GAP = 8.5;  // confirmed standard GPIO female header height

// ---- Hardware ----
SCREW_CLEARANCE_D = 2.8;  // M2.5 shaft clearance
PILOT_D            = 2.0; // self-tap pilot hole diameter in base
PILOT_DEPTH         = 8;
POST_OD             = 6;

// ---- Base tray ----
MARGIN     = 2.5;                  // plate margin around board footprint
PLATE_L    = BOARD_L + 2*MARGIN;   // 90
PLATE_W    = BOARD_W + 2*MARGIN;   // 61
PLATE_T    = 15;
CORNER_R   = 4;

BATTERY_D      = 21;
BATTERY_CLR    = 1;                     // radial clearance
CHANNEL_R      = BATTERY_D/2 + BATTERY_CLR;  // 11.5
CHANNEL_LEN    = 76;                    // battery is 70mm; open end for insertion

module rounded_plate(l, w, t, r) {
    hull() {
        for (x = [r, l-r], y = [r, w-r])
            translate([x, y, 0]) cylinder(h=t, r=r, $fn=32);
    }
}

function hole_positions() = [
    for (x = [MARGIN+HOLE_OFF, MARGIN+HOLE_OFF+HOLE_DX])
    for (y = [MARGIN+HOLE_OFF, MARGIN+HOLE_OFF+HOLE_DY])
    [x, y]
];

module base_tray() {
    difference() {
        rounded_plate(PLATE_L, PLATE_W, PLATE_T, CORNER_R);

        // battery channel, open at the +X edge for insertion/removal
        translate([PLATE_L - CHANNEL_LEN, PLATE_W/2, PLATE_T])
            rotate([0, 90, 0])
            cylinder(h=CHANNEL_LEN + 1, r=CHANNEL_R, $fn=48);

        // pilot holes for the 4 long screws
        for (p = hole_positions())
            translate([p[0], p[1], PLATE_T - PILOT_DEPTH])
                cylinder(h=PILOT_DEPTH + 1, d=PILOT_D, $fn=16);
    }
}

module spacer_tube(height) {
    difference() {
        cylinder(h=height, d=POST_OD, $fn=32);
        translate([0, 0, -1])
            cylinder(h=height + 2, d=SCREW_CLEARANCE_D, $fn=16);
    }
}

// ---- Layout for viewing / printing ----
part = "base"; // "base" | "spacer_ups_pi" | "spacer_pi_lcd" | "all"

if (part == "base" || part == "all")
    base_tray();

if (part == "spacer_ups_pi" || part == "all")
    translate([PLATE_L + 15, 0, 0])
        spacer_tube(UPS_TO_PI_GAP);

if (part == "spacer_pi_lcd" || part == "all")
    translate([PLATE_L + 30, 0, 0])
        spacer_tube(GPIO_HEADER_GAP);
