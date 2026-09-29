# rig_preset — Guitar Rig 6 song presets, generated

Makes Guitar Rig 6 Pro rack presets (`.ngrr`) for songs, from a short recipe file. Everything
here was worked out by trial and error against the user's own GR6 install (Sep 2026). Read the
"Hard-won rules" section before changing anything.

```
rig_preset/
├── build.py                            # recipe -> .ngrr
├── nicontainer.py                      # low-level editor for NI's binary container format
├── templates/gr6-native-template.ngrr  # a preset GR6 itself wrote (the only template that imports reliably)
├── songs/*.py                          # one recipe per song (NAME + CHAIN)
└── presets/*.ngrr                      # built output, ready to import
```

## Making a preset for a new song (next Claude session: start here)

1. **Write a recipe** in `songs/<song>.py`. Copy an existing one:
   ```python
   NAME = "Artist - Song"          # what shows in GR6's browser
   CHAIN = [                       # signal order, first = closest to the guitar
       ("Noise Gate", {"T": "0.300000"}, None),
       ("Van 51", {"L1": "0.700000", "M3": "0.650000"}, None),
       ("Matched Cabinet Pro", {}, None),
       ("Studio Reverb", {"Wet": "0.150000"}, None),
   ]
   ```
   Each entry is `(component name, {param id: value}, factory file to copy it from or None)`.
   `None` = first factory preset that contains that component. Param values are the raw 0–1
   knob positions (switches are `"0"`/`"1"`, selectors are integers). Every component is forced
   on (`Pwr=1`).
2. **Look up component names and param ids** — see "Finding components" below.
3. **Build:** `python build.py songs/<song>.py` (or `"songs/*.py"` for all). It writes to
   `presets/` and `%USERPROFILE%\OneDrive\Desktop\GR6 import\`.
4. **User imports it in GR6** (browser → Import → pick the file from `Desktop\GR6 import`).
   Copying into the user preset folder is not enough — see rules.
5. User filters to your presets with **Artists → Claude** in GR6's browser.
6. Commit the recipe + built preset.

## Finding components

GR6's factory presets are the parts bin:
`C:\Program Files\Common Files\Native Instruments\Guitar Rig 6\Rack Presets\` (949 files).

```python
import re, glob
F = "C:/Program Files/Common Files/Native Instruments/Guitar Rig 6/Rack Presets/"
names = set()
for f in glob.glob(F + "**/*.ngrr", recursive=True):
    t = open(f, "rb").read().decode("latin1")
    names |= set(re.findall(r'<component id="\d+" name="([^"]+)"', t[t.find("<non-fix-components>"):]))
print(sorted(names))
```

Then print one block's parameters to get ids, display names and typical values:
`re.findall(r'<parameter id="([^"]+)" name="([^"]+)" value="([^"]+)"', block)`.

Components used so far, with the ids that matter:

| Component | Role | Useful params |
|---|---|---|
| Noise Gate | gate | `T` threshold, `R` release |
| Tube Compressor | comp | `Drv` saturation, `Th` threshold, `Rt` ratio, `Out` |
| Skreamer | Tube Screamer | `Dr` drive, `Vol`, `Tn` tone, `Bs` bass |
| Van 51 | 5150-style high gain | `L13` lead channel, `L1` lead gain, `B2`/`M3`/`T4` EQ, `P7` presence, `R6` resonance |
| Twang Reverb | Fender clean | `Vol`, `Br` bright, `Bs`/`Md`/`Tr` EQ, `RvOn`, `ViOn` |
| Jump | Marshall-ish | (see Sweet Child in git history) |
| EQ Graphic | EQ | `b1`…`b8` bands |
| Matched Cabinet Pro | cab | `MV` volume |
| Choral | chorus | `rate`, `amount`, `delay`, `width`, `mix` |
| Phaser Nine | phaser | `p`, `x`, `r`, `e` |
| Delay Man | analog delay | `d` time, `m` mix, `f` feedback, `i` intensity, `cv` |
| Studio Reverb | reverb | `Wet`, `Sz` size, `Tm` predelay, `H` bright |

The factory set also has AC Box, Plex, Lead 800, Hot Plex, Tweedman, Big Fuzz, Fuzz, Tape Echo,
Spring Reverb, Ensemble, Flanger, Tremolo, Rotator, Wahwah and ~100 more.

## Hard-won rules (don't relearn these)

- **GR6 only shows presets that are in its database** (`%LOCALAPPDATA%\Native Instruments\Guitar Rig 6\Database\gr6db`).
  Dropping a file into `Documents\Native Instruments\User Content\Guitar Rig 6\Rack Presets\`
  does nothing; the user must **Import**. GR6 then writes its own copy into that folder
  (with " 1" appended if the name exists).
- **Don't also write the file into GR6's user folder yourself** — a pre-placed copy with the same
  name seemed to block an import. Only write to `Desktop\GR6 import\`.
- **Template must be a file GR6 wrote itself** (`guitarrig6-database-info` chunk, has an
  "Import" tag). Files built from GR7-format or hand-made containers imported only sometimes
  (the Tool presets consistently failed); rebuilt from a GR6-written file, they all imported.
  If the template is lost, import any working preset into GR6 and use the copy GR6 saves.
- **If an import silently does nothing, restart GR6** before debugging the file. Check whether it
  registered with `open(gr6db,'rb').read().count(b"<preset name>")`.
- **The user is on GR6 Pro; GR7 is uninstalled** (it was non-Pro anyway). Take components from
  GR6's factory presets, never GR7's.
- **Every preset is tagged** `<author>Claude</author>` + attribute `RP://Artists<TAB>Claude`
  (+ matching `preset-ordering` entries) by `artist_edits()`, so the user can filter to only
  Claude-made presets. Keep it on.
- **Automation numbers** for effect parameters start at 16 and step by `num-parameters + 1`; the
  template's fixed entries start at 256, so a chain must stay under ~240 params total
  (`build.py` asserts). 7–8 effects is fine.

## File format notes (nicontainer.py)

`.ngrr` is NI's nested "hsin/DSIN" container. Every frame starts with a little-endian u64 size
counted from the frame start:

```
[u64 size][u32 1]['hsin'][u64][16B id]          item (id is random per file)
[u64 size]['DSIN'] ...                           data frame
[u64 size][' LMX'][u32 1][u32 nbytes] <xml>      embedded XML string
```

The preset name also appears as UTF-16 preceded by a u32 char count. Two XML chunks matter:
`guitarrig6-database-info` (name, author, tags) and `gr-instrument-chunk` (the rack:
`<non-fix-components>` plus `host-automationdb` entries pointing at each component's uuid).
`nicontainer.edit()` applies byte edits and fixes every enclosing frame size and XML length;
it round-trips GR's own files byte-exactly.

## Presets made so far

All in `songs/`: Come As You Are and Something In The Way (Nirvana), Sadda Haq (Rockstar),
Pneuma and Fear Inoculum (Tool), For Whom The Bell Tolls (Metallica), Sweet Child O' Mine (GN'R).
The user confirmed most of these imported in GR6, but from earlier versions of this tool (same
chains and values; a few now draw their component blocks from different factory files).
Something In The Way was first built with this version. Not kept as a recipe: Tame Impala
"Loser", which used GR7-only effects (Red Fuzz, Tape Wobble, Replika GR); redo it with GR6
equivalents (Big Fuzz, Choral/Ensemble, Tape Echo) if wanted.

User feedback so far: the volume knob on the guitar has a "dead zone" with these presets, most
likely the high-gain amp + compressor flattening the level (top of the knob) or the Noise Gate
(bottom). Keep gate thresholds modest (`T` ≤ 0.3) and gain moderate for clean-up-able presets.
The user plays through a Blackstar ID:Core over USB (GR6 on WASAPI Exclusive), so loudness is
set on the amp's MASTER knob, not in Windows.
