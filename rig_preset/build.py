"""Build Guitar Rig 6 presets (.ngrr) from a song recipe.

    python build.py songs/come_as_you_are.py        # one song
    python build.py songs/*.py                      # all songs

A recipe is a small Python file defining NAME (preset name) and CHAIN: a list of
(component_name, {param_id: value}, prefer_file_or_None). Each component's XML block is
copied from GR6's own factory presets, its params overridden, then spliced into a
GR6-native template. Output goes to presets/ and to Desktop\\GR6 import\\ for GR6's Import.
See README.md for the why behind every step.
"""
import base64
import glob
import os
import re
import sys

from nicontainer import artist_edits, edit, rename_edits

HERE = os.path.dirname(os.path.abspath(__file__))
FACTORY = "C:/Program Files/Common Files/Native Instruments/Guitar Rig 6/Rack Presets/"
TEMPLATE = os.path.join(HERE, "templates", "gr6-native-template.ngrr")
TEMPLATE_NAME = "Tool - Pneuma 1"  # <name> inside the template file
OUT_DIRS = [os.path.join(HERE, "presets"), os.path.expanduser("~/OneDrive/Desktop/GR6 import")]


def grab(name, prefer=None):
    """First factory block for component `name` (skipping ones that reference user templates)."""
    files = [FACTORY + prefer] if prefer else sorted(glob.glob(FACTORY + "**/*.ngrr", recursive=True))
    for f in files:
        d = open(f, "rb").read().decode("utf-8", "replace")
        i = d.find("<non-fix-components>")
        if i < 0:
            continue
        for m in re.finditer(r'\n      <component id="\d+" name="' + re.escape(name) + r'" uuid=.*?\n      </component>', d[i:], re.S):
            if 'component-template-bank="User"' not in m.group():
                return m.group(), f
    raise KeyError(name)


def build(name, chain, artist="Claude"):
    T = open(TEMPLATE, "rb").read()
    xs = T.find(b"<gr-instrument-chunk")
    s = T.decode("utf-8", "replace")
    uuids, blocks = [], []
    for cname, params, prefer in chain:
        x, src = grab(cname, prefer)
        u = base64.b64encode(os.urandom(16)).decode()
        uuids.append((u, int(re.search(r'num-parameters="(\d+)"', x).group(1))))
        x = re.sub(r'uuid="[^"]+"', 'uuid="%s"' % u, x, count=1)
        for pid, val in {"Pwr": "1", **params}.items():  # factory blocks are sometimes switched off
            x, n = re.subn(r'(<parameter id="%s" name="[^"]+" value=")[^"]+"' % re.escape(pid), r'\g<1>%s"' % val, x)
            assert n == 1, (cname, pid, src)
        blocks.append(x)
        print(f"    {cname:20} <- {os.path.basename(src)}")
    nf_old = s[s.find("<non-fix-components>"):s.find("</non-fix-components>") + len("</non-fix-components>")]
    nf_new = "<non-fix-components>" + "".join(blocks) + "\n    </non-fix-components>"
    # host automation: drop the template's effect entries, number the new ones from 16
    ha = re.search(r'<host-automationdb num-parameters="\d+">.*?</host-automationdb>', s, re.S).group()
    old_fx = set(re.findall(r'\n      <component id="\d+" name="[^"]+" uuid="([^"]+)"', nf_old))
    keep = [l for l in re.findall(r'      <automatable-parameter[^\n]*/>', ha) if not any(u in l for u in old_fx)]
    n, new = 16, []
    for u, np_ in uuids:
        new.append(f'      <automatable-parameter automation-number="{n}" uuid="{u}"/>')
        n += np_ + 1
    assert n < 256, "too many parameters: fixed automation slots start at 256"
    ha_new = f'<host-automationdb num-parameters="{len(new) + len(keep)}">\n' + "\n".join(new + keep) + "\n    </host-automationdb>"
    e, u16 = rename_edits(T, TEMPLATE_NAME, name)
    if artist:
        e += artist_edits(T, artist)
    for o, nw in [(nf_old, nf_new), (ha, ha_new)]:
        q = T.find(o.encode(), xs)
        assert q > 0
        e.append((q, o.encode(), nw.encode()))
    out = bytearray(edit(T, e, u16))
    p = out.find(b"hsin")  # fresh item ids, like a real saved preset
    while p >= 0:
        out[p + 12:p + 28] = os.urandom(16)
        p = out.find(b"hsin", p + 1)
    return bytes(out)


def load_recipe(path):
    ns = {}
    exec(open(path, encoding="utf-8").read(), ns)
    return ns["NAME"], ns["CHAIN"]


if __name__ == "__main__":
    paths = [p for a in sys.argv[1:] for p in glob.glob(a)] or sys.exit(__doc__)
    for path in paths:
        name, chain = load_recipe(path)
        print(name)
        data = build(name, chain)
        for d in OUT_DIRS:
            os.makedirs(d, exist_ok=True)
            open(os.path.join(d, name + ".ngrr"), "wb").write(data)
        print(f"    -> {len(data)} bytes")
