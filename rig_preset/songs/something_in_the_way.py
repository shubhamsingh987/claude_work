# Nirvana - Something In The Way: very quiet, dark, soft clean (original is a detuned acoustic 12-string,
# played barely touching the strings). Low gate so soft picking isn't cut, gentle comp, dark Fender clean,
# a light chorus to fake the 12-string shimmer, some room. Tuned a whole step down (D G C F A D).
NAME = "Nirvana - Something In The Way"
CHAIN = [
    ("Noise Gate", {"T": "0.100000", "R": "0.350000"}, None),
    ("Tube Compressor", {"Drv": "0.150000", "Th": "0.400000", "Rt": "0.300000", "Out": "0.550000"}, None),
    ("Twang Reverb", {"Vol": "0.550000", "Br": "0", "Bs": "0.600000", "Md": "0.500000", "Tr": "0.300000", "RvOn": "0", "ViOn": "0"}, None),
    ("Matched Cabinet Pro", {}, None),
    ("Choral", {"delay": "0.200000", "rate": "0.200000", "amount": "0.400000", "width": "0.800000", "mix": "0.350000"}, None),
    ("Studio Reverb", {"Wet": "0.250000", "Sz": "0.600000", "Tm": "0.150000", "H": "0.350000"}, None),
]
