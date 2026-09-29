# Nirvana - Come As You Are: slightly gritty clean amp, deep watery chorus (Small Clone style), a bit of room.
# Song is tuned a whole step down (D G C F A D).
NAME = "Nirvana - Come As You Are"
CHAIN = [
    ("Noise Gate", {"T": "0.300000", "R": "0.200000"}, None),
    ("Tube Compressor", {"Drv": "0.30000", "Th": "0.45000", "Rt": "0.25000", "Out": "0.52000"}, None),
    ("Skreamer", {"Dr": "0.200000", "Vol": "0.550000", "Tn": "0.500000"}, None),
    ("Twang Reverb", {"Vol": "0.720000", "Br": "0", "Bs": "0.550000", "Md": "0.600000", "Tr": "0.480000", "RvOn": "0", "ViOn": "0"}, None),
    ("Matched Cabinet Pro", {}, None),
    ("Choral", {"delay": "0.250000", "rate": "0.300000", "amount": "0.650000", "width": "0.700000", "mix": "0.550000"}, None),
    ("Studio Reverb", {"Wet": "0.150000", "Sz": "0.450000", "Tm": "0.120000", "H": "0.500000"}, None),
]
