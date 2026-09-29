"""Minimal editor for NI 'hsin/DSIN' container files (Guitar Rig .ngrr).

Every frame starts with a u64 LE size counted from the frame start:
  [u64 size][u32 1]['hsin'] ...   item
  [u64 size]['DSIN'] ...          data frame
  [u64 size][' LMX'][u32 1][u32 nbytes] <text>   embedded XML string
Name strings are UTF-16 with a u32 char count right before them.
"""
import struct


def frames(d):
    out = []
    for p in range(0, len(d) - 16):
        tag = d[p + 8:p + 12]
        hs = d[p + 12:p + 16] == b"hsin" and d[p + 8:p + 12] == b"\x01\x00\x00\x00"
        if tag in (b"DSIN", b" LMX") or hs:
            size = struct.unpack_from("<Q", d, p)[0]
            if 16 <= size <= len(d) - p:
                out.append((p, size, tag == b" LMX"))
    return out


def edit(d, edits, utf16_counts=()):
    """edits: list of (pos, old_bytes, new_bytes) on the ORIGINAL buffer.
    utf16_counts: list of (count_pos, text_pos, old_str, new_str)."""
    fr = frames(d)
    out = bytearray(d)
    edits = list(edits) + [(t, o.encode("utf-16le"), n.encode("utf-16le")) for c, t, o, n in utf16_counts]
    for p, size, is_lmx in fr:
        delta = sum(len(n) - len(o) for q, o, n in edits if p < q and q + len(o) <= p + size)
        struct.pack_into("<Q", out, p, size + delta)
        if is_lmx:
            n0 = struct.unpack_from("<I", d, p + 16)[0]
            s = p + 20
            dl = sum(len(n) - len(o) for q, o, n in edits if s <= q and q + len(o) <= s + n0)
            struct.pack_into("<I", out, p + 16, n0 + dl)
    # file-level size at 0 is itself an hsin frame, handled above
    for cpos, tpos, old, new in utf16_counts:
        struct.pack_into("<I", out, cpos, len(new))
    for q, o, n in sorted(edits, reverse=True):
        assert bytes(out[q:q + len(o)]) == o, (q, o[:20])
        out[q:q + len(o)] = n
    return bytes(out)


def rename_edits(d, old, new):
    """dbinfo <name> edit + utf16 name edit for renaming a preset."""
    p = d.find(b"<name>" + old.encode() + b"</name>") + 6
    u = old.encode("utf-16le")
    t = d.find(struct.pack("<I", len(old)) + u) + 4
    assert p > 5 and t > 3
    return [(p, old.encode(), new.encode())], [(t - 4, t, old, new)]


def artist_edits(d, artist="Claude"):
    """Insert-only edits tagging a GR6 preset with Artists/<artist> (+ <author>)."""
    e = []
    s = d.find(b"-database-info>")
    def ins(anchor, text, after=False):
        q = d.find(anchor, s)
        assert q > 0, anchor
        if after:
            q += len(anchor)
        e.append((q, b"", text.encode()))
    if b"RP://Artists\t" + artist.encode() in d:
        return e
    if b"<author>" not in d[s:s + 400]:
        ins(b"</name>", "\n      <author>%s</author>" % artist, after=True)
    ins(b"    </attributes>", "      <attribute>\n        <value>Artists</value>\n        <user-set>RP://Artists</user-set>\n      </attribute>\n"
        "      <attribute>\n        <value>%s</value>\n        <user-set>RP://Artists\t%s</user-set>\n      </attribute>\n" % (artist, artist))
    ins(b"  </preset-ordering-collection>", '    <preset-ordering order-number="0" tag-path="RP://Artists"/>\n'
        '    <preset-ordering order-number="0" tag-path="RP://Artists&#x9;%s"/>\n' % artist)
    return e
