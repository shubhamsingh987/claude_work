# Rockstar (A.R. Rahman) - Sadda Haq: tight, punchy high-gain rock rhythm, mid-forward, a touch of slap delay.
NAME = "Rockstar - Sadda Haq"
CHAIN = [
    ("Noise Gate", {"T": "0.250000", "R": "0.200000"}, None),
    ("Skreamer", {"Dr": "0.150000", "Vol": "0.750000", "Tn": "0.550000", "Bs": "0.350000"}, None),
    ("Van 51", {"L13": "1", "L1": "0.720000", "B2": "0.500000", "M3": "0.650000", "T4": "0.620000",
                "P7": "0.580000", "R6": "0.550000", "P5": "0.400000", "H14": "0"}, None),
    ("EQ Graphic", {"b1": "0.450000", "b3": "0.520000", "b4": "0.580000", "b7": "0.540000", "b8": "0.460000"}, None),
    ("Matched Cabinet Pro", {}, None),
    ("Delay Man", {"d": "0.180000", "m": "0.120000", "f": "0.200000", "i": "0.100000", "cv": "1"}, None),
    ("Studio Reverb", {"Wet": "0.120000", "Sz": "0.450000", "Tm": "0.100000", "H": "0.550000"}, None),
]
