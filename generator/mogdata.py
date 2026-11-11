# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Gitano Calvo
"""Input loaders for build_mog_public.py: the config file, client tables (wago.tools CSV plus DBCache.bin
hotfixes), the questcache.wdb quest cache, QuestieDB Forever, zone geometry, and Lua literal writers."""
import collections
import csv
import hashlib
import json
import math
import os
import re

import hotfix
import svlua
import wdb

A_BITS = 77 | (1 << 32)
H_BITS = 178 | (1 << 33)
RACE_IDS = dict(NONE=0, HUMAN=1, ORC=2, DWARF=4, NIGHT_ELF=8, UNDEAD=16, TAUREN=32, GNOME=64, TROLL=128,
                SKYBORNE_ALLIANCE=1 << 32, SKYBORNE_HORDE=1 << 33, ALL_ALLIANCE=A_BITS, ALL_HORDE=H_BITS)
CLASS_IDS = dict(NONE=0, WARRIOR=1, PALADIN=2, HUNTER=4, ROGUE=8, PRIEST=16, SHAMAN=64, MAGE=128,
                 WARLOCK=256, DRUID=1024)
PROFESSIONS = {164: 'Blacksmithing', 165: 'Leatherworking', 171: 'Alchemy', 182: 'Herbalism', 185: 'Cooking',
               186: 'Mining', 197: 'Tailoring', 202: 'Engineering', 333: 'Enchanting', 356: 'Fishing',
               129: 'First Aid', 393: 'Skinning', 755: 'Jewelcrafting', 773: 'Inscription', 40: 'Poisons',
               633: 'Lockpicking'}
CITY_UIMAPS = {1453, 1454, 1455, 1456, 1457, 1458}
# Zone of each Classic dungeon entrance; picks between overlapping zone maps for a Map corpse point.
DUNGEON_ZONE = {'wailing caverns': 'The Barrens', 'deadmines': 'Westfall', 'shadowfang keep': 'Silverpine Forest',
                'blackfathom deeps': 'Ashenvale', 'stormwind stockades': 'Stormwind City',
                'gnomeregan': 'Dun Morogh', 'razorfen kraul': 'The Barrens', 'scarlet monastery': 'Tirisfal Glades',
                'razorfen downs': 'The Barrens', 'uldaman': 'Badlands', "zul'farak": 'Tanaris',
                'maraudon': 'Desolace', 'sunken temple': 'Swamp of Sorrows', 'dire maul - east': 'Feralas',
                'dire maul - west': 'Feralas', 'dire maul - north': 'Feralas', 'stratholme': 'Eastern Plaguelands',
                'scholomance': 'Western Plaguelands'}

HOTFIX_TABLES = ('ItemSparse', 'Item', 'SpellEffect', 'SkillLineAbility')
CSV_TABLES = ('AreaTable', 'QuestSort', 'LFGDungeons', 'ContentTuning', 'Map', 'DungeonEncounter', 'UiMap',
              'UiMapAssignment', 'ItemModifiedAppearance', 'ItemAppearance')
WAGO_TABLES = HOTFIX_TABLES + CSV_TABLES
QUESTIE_FILES = ('foreverItemDB.lua', 'foreverNpcDB.lua', 'foreverQuestDB.lua', 'foreverObjectDB.lua',
                 'conversion.json', 'foreverBaseNpc.lua', 'foreverBaseQuest.lua', 'foreverNpcTraces.lua',
                 'foreverQuestTraces.lua', 'foreverNPCFixes.lua', 'foreverQuestFixes.lua')
QUESTIE_REQUIRED = ('foreverItemDB.lua', 'foreverNpcDB.lua', 'foreverQuestDB.lua', 'conversion.json')
WAGO_URL = 'https://wago.tools/db2/%s/csv?build=%s'
DBD_URL = 'https://raw.githubusercontent.com/wowdev/WoWDBDefs/master/definitions/%s.dbd'

CLUSTER_YD = 150.0
CLUSTER_MAX_POINTS = 600


def log(*a):
    print(*a, flush=True)


def to_int(v, default=0):
    try:
        return int(v)
    except (TypeError, ValueError):
        try:
            return int(float(v))
        except (TypeError, ValueError):
            return default


def norm_sym(name):
    return re.sub(r"[^A-Za-z0-9]+", '_', name.upper()).strip('_')


def faction_of(mask):
    """Race mask -> 'Alliance', 'Horde' or 'both' (0 and mixed masks are both)."""
    mask = to_int(mask)
    if not mask:
        return 'both'
    a, h = bool(mask & A_BITS), bool(mask & H_BITS)
    return 'both' if a and h else ('Alliance' if a else ('Horde' if h else 'both'))


def lstr(s):
    s = str(s).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '')
    return '"' + s + '"'


def lval(v):
    """Python value -> Lua literal. Trailing nils of a list are dropped."""
    if v is None:
        return 'nil'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        s = '%.1f' % v
        return s[:-2] if s.endswith('.0') else s
    if isinstance(v, str):
        return lstr(v)
    if isinstance(v, (list, tuple)):
        items = list(v)
        while items and items[-1] is None:
            items.pop()
        return '{' + ','.join(lval(x) for x in items) + '}'
    raise TypeError(type(v))


def git_blob_sha1(path):
    with open(path, 'rb') as f:
        data = f.read()
    return hashlib.sha1(b'blob %d\0' % len(data) + data).hexdigest()


# ------------------------------------------------------------------------------------------------- config

def has_wtf_part(p):
    return any(x.lower() == 'wtf' for x in os.path.normpath(os.path.abspath(p)).split(os.sep))


def load_config(path):
    """JSON config -> dict of absolute paths. Relative paths are relative to the config file's folder."""
    if not os.path.isfile(path):
        raise SystemExit('config file not found: %s (copy config.example.json to config.json and edit it)' % path)
    with open(path, encoding='utf-8-sig') as f:
        raw = json.load(f)
    base = os.path.dirname(os.path.abspath(path))

    def p(v):
        if not v:
            return None
        v = os.path.expanduser(str(v))
        return os.path.normpath(v if os.path.isabs(v) else os.path.join(base, v))

    qc = raw.get('questcache') or []
    if isinstance(qc, str):
        qc = [qc]
    cfg = dict(
        build=str(raw.get('build') or ''),
        wago_dir=p(raw.get('wago_dir')),
        dbd_dir=p(raw.get('dbd_dir')),
        dbcache=p(raw.get('dbcache')),
        questcache=[p(x) for x in qc if x],
        questie_dir=p(raw.get('questie_dir')),
        entrances=p(raw.get('entrances')),
        out_dir=p(raw.get('out_dir')),
        license_file=p(raw.get('license_file')),
        notice_file=p(raw.get('notice_file')),
        version=raw.get('version'),
    )
    if not re.fullmatch(r'\d+\.\d+\.\d+\.\d+', cfg['build']):
        raise SystemExit('config: "build" must be the full client build, e.g. 1.60.1.70862')
    for key in ('wago_dir', 'questie_dir'):
        if not cfg[key]:
            raise SystemExit('config: "%s" is required' % key)
    if cfg['dbcache'] and not cfg['dbd_dir']:
        raise SystemExit('config: "dbcache" needs "dbd_dir" (the WoWDBDefs layouts to decode its rows)')
    paths = [cfg[k] for k in ('wago_dir', 'dbd_dir', 'dbcache', 'questie_dir', 'entrances', 'out_dir',
                              'license_file', 'notice_file') if cfg[k]] + cfg['questcache']
    bad = [x for x in paths if has_wtf_part(x)]
    if bad:
        raise SystemExit('config: no input or output may lie under a WTF folder: %s' % bad[0])
    return cfg


def missing_inputs(cfg):
    """[(missing file, where to download it)] for the client tables and the .dbd layouts."""
    out = [(os.path.join(cfg['wago_dir'], t + '.csv'), WAGO_URL % (t, cfg['build'])) for t in WAGO_TABLES]
    if cfg['dbcache']:
        out += [(os.path.join(cfg['dbd_dir'], t + '.dbd'), DBD_URL % t) for t in HOTFIX_TABLES]
    return [(p, url) for p, url in out if not os.path.exists(p)]


# ------------------------------------------------------------------------------------------------- client

def read_csv(cfg, table):
    p = os.path.join(cfg['wago_dir'], table + '.csv')
    if not os.path.exists(p):
        raise SystemExit('missing %s (download it from %s)' % (p, WAGO_URL % (table, cfg['build'])))
    with open(p, encoding='utf-8') as f:
        return list(csv.DictReader(f))


class Client:
    """Client tables from CSV; rows of HOTFIX_TABLES are updated from DBCache.bin when one is configured."""

    def __init__(self, cfg):
        self.cfg = cfg
        self.hot = collections.defaultdict(list)
        self.hotfix_build = None
        if cfg['dbcache']:
            hdr, ents = hotfix.read(cfg['dbcache'])
            hmap = {hotfix.sstrhash(n): n for n in HOTFIX_TABLES}
            for e in ents:
                t = hmap.get(e['table_hash'])
                if t:
                    self.hot[t].append(e)
            self.hotfix_build = hdr['build']
            log('  DBCache.bin: build %d, %d entries, %d for the item tables'
                % (hdr['build'], len(ents), sum(len(v) for v in self.hot.values())))
            if str(hdr['build']) != cfg['build'].split('.')[-1]:
                log('  warning: DBCache.bin is from build %d, the tables are for %s' % (hdr['build'], cfg['build']))
        else:
            log('  no DBCache.bin configured: hotfixes are not applied')

    def csv(self, table):
        return read_csv(self.cfg, table)

    def table(self, table, key='ID'):
        """CSV rows keyed by ID, then hotfix rows (status 1 upsert, status 2 delete)."""
        rows = {to_int(r[key]): r for r in self.csv(table)}
        n_add = n_upd = n_del = 0
        p = os.path.join(self.cfg['dbd_dir'] or '', table + '.dbd')
        if self.hot.get(table):
            if not os.path.exists(p):
                raise SystemExit('missing %s (needed to decode the %s hotfixes; download it from %s)'
                                 % (p, table, DBD_URL % table))
            fields = hotfix.load_dbd(p, self.cfg['build'])
            for e in self.hot[table]:
                if e['status'] == 1:
                    try:
                        h = hotfix.decode_hotfix_row(fields, e['data'], e['record'])
                    except Exception:
                        continue
                    if h.get('_leftover'):
                        continue
                    flat = {}
                    for k, v in h.items():
                        if isinstance(v, list):
                            for i, x in enumerate(v):
                                flat['%s_%d' % (k, i)] = x
                        else:
                            flat[k] = v
                    rid = to_int(flat.get(key, e['record']))
                    if key == 'ID':
                        rid = e['record']
                        flat['ID'] = rid
                    if rid in rows:
                        n_upd += 1
                        rows[rid].update(flat)
                    else:
                        n_add += 1
                        rows[rid] = flat
                elif e['status'] == 2 and e['record'] in rows:
                    n_del += 1
                    rows.pop(e['record'])
        log('  %-18s %6d rows (hotfix: +%d new, %d updated, %d removed)' % (table, len(rows), n_add, n_upd, n_del))
        return rows


def load_client(cfg):
    log('client tables (build %s)' % cfg['build'])
    c = Client(cfg)
    S = {}
    S['itemsparse'] = c.table('ItemSparse')
    S['item'] = c.table('Item')
    S['spelleffect'] = c.table('SpellEffect')
    S['skilllineability'] = c.table('SkillLineAbility')
    S['area'] = {to_int(r['ID']): r for r in c.csv('AreaTable')}
    S['questsort'] = {to_int(r['ID']): r['SortName_lang'] for r in c.csv('QuestSort')}
    S['lfg'] = c.csv('LFGDungeons')
    S['ct'] = {to_int(r['ID']): r for r in c.csv('ContentTuning')}
    S['map'] = {to_int(r['ID']): r for r in c.csv('Map')}
    S['encounters'] = c.csv('DungeonEncounter')
    S['hotfix_build'] = c.hotfix_build
    return S


def load_questcache(cfg):
    """Union of the configured questcache.wdb files of this build; a later file wins for the same quest."""
    build_no = to_int(cfg['build'].split('.')[-1])
    merged, used = {}, 0
    for p in cfg['questcache']:
        if not os.path.exists(p):
            raise SystemExit('questcache file not found: %s' % p)
        hdr, rows, errors = wdb.parse_questcache(p)
        if hdr['build'] != build_no:
            log('  %s: build %d, not %d: skipped' % (os.path.basename(p), hdr['build'], build_no))
            continue
        used += 1
        for r in rows:
            merged[r['id']] = r
        log('  questcache file %d: %d records (%d parse errors)' % (used, hdr['records'], len(errors)))
    log('  questcache: %d quests from %d file(s)' % (len(merged), used))
    return merged


# ------------------------------------------------------------------------------------------------- QuestieDB

def questie_keys(text, var):
    m = re.search(re.escape(var) + r'\s*=\s*\{(.*?)\n\}', text, re.S)
    return {k: int(v) for k, v in re.findall(r"\['(\w+)'\]\s*=\s*(\d+)", m.group(1))}


def merge_add(cur, add, positional=False):
    """QuestieDB *_add semantics: slot tables merge slot by slot (positional); otherwise lists are unioned and
    dicts of lists (spawns) merged."""
    if cur is None:
        return add
    if add is None:
        return cur
    if isinstance(add, dict) and isinstance(cur, dict):
        out = dict(cur)
        for k, v in add.items():
            out[k] = merge_add(out.get(k), v)
        return out
    if isinstance(add, list) and isinstance(cur, list):
        if positional:
            n = max(len(cur), len(add))
            a2 = add + [None] * (n - len(add))
            c2 = cur + [None] * (n - len(cur))
            return [merge_add(c2[i], a2[i]) for i in range(n)]
        out = list(cur)
        for x in add:
            if x not in out:
                out.append(x)
        return out
    return add


def load_questie(cfg, client):
    log('QuestieDB Forever')
    qd = cfg['questie_dir']
    missing = [f for f in QUESTIE_REQUIRED if not os.path.exists(os.path.join(qd, f))]
    if missing:
        raise SystemExit('QuestieDB files missing in %s: %s' % (qd, ', '.join(missing)))
    for f in QUESTIE_FILES + ('provenance.json',):
        fp = os.path.join(qd, f)
        if os.path.exists(fp):
            log('  %-24s %9d bytes  git blob %s' % (f, os.path.getsize(fp), git_blob_sha1(fp)))
        else:
            log('  %-24s missing (optional)' % f)

    def rd(f):
        with open(os.path.join(qd, f), encoding='utf-8') as fh:
            return fh.read()

    zone_sym = {}
    for aid, r in client['area'].items():
        zone_sym.setdefault(norm_sym(r['AreaName_lang']), aid)
        zone_sym.setdefault(norm_sym(r['ZoneName']), aid)
    sort_sym = {norm_sym(n): i for i, n in client['questsort'].items()}
    out = {}
    for kind, dbfile, var, kvar in (('npc', 'foreverNpcDB.lua', 'QuestieDB.npcData', 'QuestieDB.npcKeys'),
                                    ('quest', 'foreverQuestDB.lua', 'QuestieDB.questData', 'QuestieDB.questKeys'),
                                    ('item', 'foreverItemDB.lua', 'QuestieDB.itemData', 'QuestieDB.itemKeys')):
        text = rd(dbfile)
        keys = questie_keys(text, kvar)
        recs = {}
        for rid, rec in svlua.parse_long_string_table(text, var).items():
            recs[rid] = {i + 1: v for i, v in enumerate(svlua.to_list(rec)) if v is not None}
        stats = dict(base=len(recs))
        prefix = kind + 'Keys.'

        def resolver(path, keys=keys, prefix=prefix):
            if path.startswith(prefix):
                k = path[len(prefix):]
                if k.endswith('_add') and k[:-4] in keys:
                    return ('add', keys[k[:-4]])
                return keys.get(k, svlua.Unparsed(path))
            head, _, tail = path.partition('.')
            if head == 'zoneIDs':
                return zone_sym.get(tail, svlua.Unparsed(path))
            if head == 'raceIDs':
                return RACE_IDS.get(tail, svlua.Unparsed(path))
            if head == 'classIDs':
                return CLASS_IDS.get(tail, svlua.Unparsed(path))
            if head == 'sortKeys':
                return sort_sym.get(tail, svlua.Unparsed(path))
            return svlua.Unparsed(path)

        layers = {'npc': ('foreverBaseNpc.lua', 'foreverNpcTraces.lua', 'foreverNPCFixes.lua'),
                  'quest': ('foreverBaseQuest.lua', 'foreverQuestTraces.lua', 'foreverQuestFixes.lua'),
                  'item': ()}[kind]
        for fname in layers:
            if not os.path.exists(os.path.join(qd, fname)):
                continue
            tbl = svlua.parse_return_table(rd(fname), resolver, after=':Load()')
            n_new = n_mod = 0
            for rid, fields in (tbl.items() if isinstance(tbl, dict) else []):
                if not isinstance(rid, int) or not isinstance(fields, dict):
                    continue
                rec = recs.get(rid)
                if rec is None:
                    rec = recs[rid] = {}
                    n_new += 1
                else:
                    n_mod += 1
                for k, v in fields.items():
                    if isinstance(v, svlua.Unparsed):
                        continue
                    if isinstance(k, tuple) and k[0] == 'add':
                        pos = kind == 'quest' and k[1] in (2, 3, 10)
                        rec[k[1]] = merge_add(rec.get(k[1]), v, positional=pos)
                    elif isinstance(k, int):
                        rec[k] = v
            stats[fname] = (n_new, n_mod)
        out[kind] = recs
        log('  %-5s %s' % (kind, stats))
    conv = json.loads(rd('conversion.json'))
    out['uimap_to_area'] = {t['ui_map_id']: t['area_id'] for t in conv['geometry']['transforms']}
    out['object'] = load_questie_objects(cfg)
    return out


def load_questie_objects(cfg):
    """QuestieDB Forever objectData: {objectID: {1 name, 2 questStarts, 3 questEnds, 4 spawns, 5 zoneID}}."""
    p = os.path.join(cfg['questie_dir'], 'foreverObjectDB.lua')
    if not os.path.exists(p):
        log('  objects: foreverObjectDB.lua missing: no object spots')
        return {}
    with open(p, encoding='utf-8') as f:
        text = f.read()
    out = {}
    for rid, rec in svlua.parse_long_string_table(text, 'QuestieDB.objectData').items():
        out[rid] = {i + 1: v for i, v in enumerate(svlua.to_list(rec)) if v is not None}
    log('  objects %d' % len(out))
    return out


# ------------------------------------------------------------------------------------------------- zones

def load_zones(cfg, Q):
    """uiMap world bounds (client UiMap + UiMapAssignment) and area ID -> uiMap."""
    um = {to_int(r['ID']): r for r in read_csv(cfg, 'UiMap')}
    zones, area2ui = {}, {}
    for a in read_csv(cfg, 'UiMapAssignment'):
        ui = to_int(a['UiMapID'])
        m = um.get(ui)
        if not m or m['Type'] not in ('3', '6') or a['OrderIndex'] != '0' or a['WMOGroupID'] != '0':
            continue
        if float(a['UiMin_0']) != 0 or float(a['UiMax_0']) != 1:
            continue
        r0, r1, r3, r4 = (float(a['Region_%d' % i]) for i in (0, 1, 3, 4))
        zones[ui] = dict(cont=to_int(a['MapID']), l=r4, r=r1, t=r3, b=r0, name=m['Name_lang'])
        if to_int(a['AreaID']):
            area2ui.setdefault(to_int(a['AreaID']), ui)
    for ui, aid in Q['uimap_to_area'].items():
        if ui in zones:
            area2ui[aid] = ui
    log('zones: %d uiMaps with world bounds, %d area IDs mapped' % (len(zones), len(area2ui)))
    return zones, area2ui


def to_map(zones, cont, wx, wy, prefer=None):
    """World X/Y on a continent -> (uiMap, x, y). Zone rectangles overlap at their edges: the zone named
    `prefer` wins when the point lies on it, else the zone where the point lies most centrally (cities last)."""
    best = None
    for ui, z in zones.items():
        if z['cont'] != cont or z['r'] == z['l'] or z['b'] == z['t']:
            continue
        x = (wy - z['l']) / (z['r'] - z['l']) * 100.0
        y = (wx - z['t']) / (z['b'] - z['t']) * 100.0
        if 0 <= x <= 100 and 0 <= y <= 100:
            score = min(x, 100 - x, y, 100 - y) - (50 if ui in CITY_UIMAPS else 0)
            if prefer and z['name'] == prefer:
                score += 1000
            if best is None or score > best[0]:
                best = (score, ui, x, y)
    return best and best[1:]


def clusters(zones, pts, k):
    """Up to k densest areas (points within CLUSTER_YD) per map: [(n, uiMap, x, y)], biggest first."""
    by = collections.defaultdict(list)
    for p in set(pts):
        by[p[0]].append(p)
    out = []
    for ui, lst in by.items():
        lst.sort()
        if len(lst) > CLUSTER_MAX_POINTS:
            step = int(math.ceil(len(lst) / float(CLUSTER_MAX_POINTS)))
            lst = lst[::step]
        z = zones[ui]
        sx, sy = abs(z['r'] - z['l']) / 100.0, abs(z['b'] - z['t']) / 100.0
        r2 = CLUSTER_YD * CLUSTER_YD
        near = [[j for j, q in enumerate(lst) if ((p[1] - q[1]) * sx) ** 2 + ((p[2] - q[2]) * sy) ** 2 <= r2]
                for p in lst]
        left = set(range(len(lst)))
        for _ in range(k):
            if not left:
                break
            i = max(sorted(left), key=lambda i: sum(1 for j in near[i] if j in left))
            mem = [j for j in near[i] if j in left]
            out.append((len(mem), ui, sum(lst[j][1] for j in mem) / len(mem), sum(lst[j][2] for j in mem) / len(mem)))
            left -= set(mem)
    out.sort(key=lambda c: (-c[0], c[1], c[2], c[3]))
    return out


def dungeon_index(C):
    """LFG dungeons (type 0) with their instance map and minimum level (ContentTuning)."""
    name_to_map = {}
    for mid, m in C['map'].items():
        if m['InstanceType'] == '1':
            name_to_map.setdefault(m['MapName_lang'].lower(), mid)
    aliases = {'stormwind stockades': 'stormwind stockade', "zul'farak": "zul'farrak"}
    out = []
    for r in C['lfg']:
        if r['TypeID'] != '0':
            continue
        nm = r['Name_lang']
        ct = C['ct'].get(to_int(r['ContentTuningID']), {})
        mid = name_to_map.get(aliases.get(nm.lower(), nm.lower()))
        if mid is None:
            mid = next((m for n, m in name_to_map.items() if nm.lower() in n or n in nm.lower()), None)
        out.append(dict(name=nm, map_id=mid, min_level=to_int(ct.get('MinLevelSquish'))))
    return out
