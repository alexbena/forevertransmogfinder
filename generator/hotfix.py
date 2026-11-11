# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Gitano Calvo
"""Reader for the client hotfix cache DBCache.bin (XFTH, version 9) and a minimal WoWDBDefs (.dbd) decoder
for its rows (inline layout)."""
import re
import struct

HT = [0x486E26EE, 0xDCAA16B3, 0xE1918EEF, 0x202DAFDB, 0x341C7DC7, 0x1C365303, 0x40EF2D37, 0x65FD5E49,
      0xD6057177, 0x904ECE93, 0x1C38024F, 0x98FD323B, 0xE3061AE7, 0xA39B0FA1, 0x9797F25F, 0xE4444563]


def sstrhash(s):
    """Table-name hash used in DBCache.bin entries."""
    v, x = 0x7FED7FED, 0xEEEEEEEE
    for ch in s.upper().replace('/', chr(92)).encode():
        v = (v + x) & 0xFFFFFFFF
        v ^= (HT[(ch >> 4) & 0xF] - HT[ch & 0xF]) & 0xFFFFFFFF
        x = (x * 33 + v + ch + 3) & 0xFFFFFFFF
    return v or 1


def read(path):
    with open(path, 'rb') as f:
        b = f.read()
    magic, ver, build = struct.unpack_from('<4sII', b, 0)
    off = 12 + 32  # header + sha256
    ents = []
    while off + 32 <= len(b):
        m, region, push, uniq, th, rec, size, status = struct.unpack_from('<4siiIIIIB', b, off)
        if m != b'XFTH':
            break
        data = b[off + 32: off + 32 + size]
        ents.append(dict(region=region, push=push, table_hash=th, record=rec, status=status, data=data))
        off += 32 + size
    return dict(magic=magic, version=ver, build=build, size=len(b), end=off), ents


def load_dbd(path, build):
    with open(path, encoding='utf-8') as f:
        text = f.read()
    cols_part = text.partition('\n\n')[0]
    types = {}
    for line in cols_part.splitlines()[1:]:
        m = re.match(r'(\w+)(?:<[^>]*>)?\s+(\w+)', line.strip())
        if m:
            types[m.group(2)] = m.group(1)
    for block in text.split('\n\n')[1:]:
        if build in block:
            fields = []
            for line in block.splitlines():
                line = line.strip()
                if not line or line.split(' ')[0] in ('LAYOUT', 'BUILD', 'COMMENT'):
                    continue
                m = re.match(r'(\$[^$]*\$)?(\w+)(?:<(u?)(\d+)>)?(?:\[(\d+)\])?', line)
                ann, name, uns, size, arr = m.groups()
                fields.append(dict(name=name, noninline='noninline' in (ann or ''),
                                   relation='relation' in (ann or ''), type=types.get(name, 'int'),
                                   size=int(size) if size else None, signed=(uns != 'u'),
                                   count=int(arr) if arr else 1))
            return fields
    raise KeyError(build)


_FMT = {(8, True): 'b', (8, False): 'B', (16, True): 'h', (16, False): 'H',
        (32, True): 'i', (32, False): 'I', (64, True): 'q', (64, False): 'Q'}


def decode_hotfix_row(fields, data, record_id):
    """Hotfix rows hold every inline field in DBD order; strings are NUL-terminated. The non-inline ID is the
    hotfix record ID; non-inline relations come at the end."""
    row, o = {'ID': record_id}, 0
    tail = [f for f in fields if f['noninline'] and f['relation']]
    for f in [f for f in fields if not f['noninline']] + tail:
        vals = []
        for _ in range(f['count']):
            if f['type'] in ('string', 'locstring'):
                e = data.index(b'\0', o)
                vals.append(data[o:e].decode('utf-8', 'replace'))
                o = e + 1
            elif f['type'] == 'float':
                vals.append(round(struct.unpack_from('<f', data, o)[0], 6))
                o += 4
            else:
                fmt = _FMT[(f['size'] or 32, f['signed'])]
                vals.append(struct.unpack_from('<' + fmt, data, o)[0])
                o += struct.calcsize(fmt)
        row[f['name']] = vals[0] if f['count'] == 1 else vals
    row['_leftover'] = len(data) - o
    return row
