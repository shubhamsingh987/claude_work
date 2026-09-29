# Nirvana - Smells Like Teen Spirit: Boss DS-1 style distortion into a mildly driven amp
# (Nevermind-era Mesa/Marshall-ish crunch), subtle chorus for the verse sheen, small room.
# Standard tuning. Gate kept at 0.25 and amp gain moderate so the guitar volume knob still
# cleans it up for the verse (see README feedback about the "dead zone").
NAME = "Nirvana - Smells Like Teen Spirit"
CHAIN = [
    ("Noise Gate", {"T": "0.250000", "R": "0.200000"}, None),
    ("Distortion", {"Dst": "0.620000", "vol": "0.700000", "tn": "0.550000", "Bs": "0.600000", "M": "0.450000", "T": "0.550000"}, None),
    ("Jump", {"V1": "0.550000", "V2": "0.600000", "B": "0.600000", "M": "0.450000", "T": "0.600000", "Pr": "0.550000", "Hg": "0"}, None),
    ("Matched Cabinet Pro", {}, None),
    ("Choral", {"delay": "0.250000", "rate": "0.300000", "amount": "0.450000", "width": "0.600000", "mix": "0.250000"}, None),
    ("Studio Reverb", {"Wet": "0.120000", "Sz": "0.400000", "Tm": "0.100000", "H": "0.500000"}, None),
]
