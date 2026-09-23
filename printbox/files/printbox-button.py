#!/usr/bin/env python3
# Reset button: a push button between GPIO3 (header pin 5) and GND (pin 6). Hold 10 s to factory reset.
import subprocess
from signal import pause

from gpiozero import Button


def reset():
    subprocess.run(["/usr/local/sbin/printbox-factory-reset.sh"])


button = Button(3, hold_time=10)
button.when_held = reset
pause()
