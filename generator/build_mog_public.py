#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Gitano Calvo
"""Build ForeverTransmogFinder_Data, the load-on-demand item list of Forever Transmog Finder.

    python -I build_mog_public.py --config config.json --version 0.3.1              (format 2, the default)
    python -I build_mog_public.py --config config.json --version 0.3.0 --format 1   (only for 0.3.0 and older)

Inputs (see README.md): client tables as CSV from wago.tools, optional DBCache.bin hotfixes and questcache.wdb
quest caches copied from a WoW Forever client, QuestieDB Forever (GPLv3), and dungeon_entrances.csv.

Data contract (ForeverTransmogFinderData):
  version, build, generated,
  items = {[itemID] = {"name", invType, classID, subclassID, quality (-1 = not in client data), reqLevel,
                       appearanceID, sourceID}},
  src = {[itemID] = {{kind, where, "label", x, y, extra[, faction]}, ...}}   best first
  zones = {[uiMap] = "name"},
  instances = {["i<MapID>"] = {"name", "dungeon"|"raid", minLevel, maxLevel, entranceUiMap, entranceX, entranceY}},
  encounters = {["i<MapID>"] = {"boss label", ...}}
kind: 1 boss, 2 mob drop, 3 quest reward, 4 vendor, 5 crafted, 6 container / object, 7 world drop / unknown.
where: uiMap, "i<MapID>" (dungeon or raid) or 0 (no place). extra: quest ID (3), skill rank (5), price (4).
Format 1: a Horde-only quest or vendor has " (Horde)" appended to its label; nothing else marks a faction.
At most MAX_SOURCES sources per item, Horde-only ones last.
Format 2: labels carry no faction; a source has a 7th field "A" (Alliance only) or "H" (Horde only). A source for
both factions (or of unknown faction) leaves it out (nil), and lval drops trailing nils, so its row keeps the size it
has in format 1. Read field 7 by index only (rows can hold nils). Each item keeps the best MAX_SOURCES sources usable
by each faction, in one best-first list (up to 2 * MAX_SOURCES).
"""
import argparse
import collections
import csv
import datetime
import os
import re
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import mogdata as md  # noqa: E402
from mogdata import log, lstr, lval, to_int  # noqa: E402

COPYRIGHT = 'Copyright (C) 2026 Gitano Calvo'
AUTHOR = COPYRIGHT.split(' ', 3)[3]
TITLE = 'Forever Transmog Finder'
MAIN_ADDON = 'ForeverTransmogFinder'
DATA_ADDON = 'ForeverTransmogFinder_Data'

K_BOSS, K_DROP, K_QUEST, K_VENDOR, K_CRAFT, K_OBJECT, K_WORLD = 1, 2, 3, 4, 5, 6, 7
KIND_NAME = {1: 'boss', 2: 'mob drop', 3: 'quest reward', 4: 'vendor', 5: 'crafted', 6: 'container/object',
             7: 'world drop/unknown'}
KIND_ORDER = {K_BOSS: 0, K_QUEST: 1, K_VENDOR: 2, K_CRAFT: 3, K_DROP: 4, K_OBJECT: 5, K_WORLD: 6}
FACTION_CODE = {'Alliance': 'A', 'Horde': 'H'}
MAX_SOURCES = 8
WORLD_DROP_NPCS = 10      # dropped by more creatures than this: also listed as a world drop
RANDOM_CHEST_ITEMS = 25   # an object holding more transmog items than this is a random-loot chest
MAX_RANDOM_CHESTS = 1
ITEMS_PER_FILE = 6000

# Enum.InventoryType values shown on the character. Not: 0, 2 neck, 11 finger, 12 trinket, 18 bag, 24 ammo,
# 27 quiver, 28 relic.
MOG_SLOTS = {1, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23, 25, 26}
SLOT_NAME = {1: 'Head', 3: 'Shoulder', 4: 'Shirt', 5: 'Chest', 6: 'Waist', 7: 'Legs', 8: 'Feet', 9: 'Wrist',
             10: 'Hands', 13: 'One-Hand', 14: 'Shield', 15: 'Ranged', 16: 'Back', 17: 'Two-Hand', 19: 'Tabard',
             20: 'Robe', 21: 'Main Hand', 22: 'Off Hand', 23: 'Held In Off-hand', 25: 'Thrown', 26: 'Ranged'}
# ItemModifiedAppearance.TransmogSourceTypeEnum: 6 can't collect, 9 not valid for transmog.
SKIP_SOURCE_TYPES = {6, 9}
FALLBACK = {1: (K_BOSS, 'Boss drop'), 2: (K_QUEST, 'Quest reward'), 3: (K_VENDOR, 'Vendor'),
            4: (K_WORLD, 'World drop'), 7: (K_WORLD, 'Achievement'), 8: (K_CRAFT, 'Profession')}
BAD_NAME = re.compile(r"^(test|monster -|zz|deprecated|\[ph\]|qa |gm |npc equip|unused|debug|dummy|placeholder|twain )"
                      r"|\b(test|testing|deprecated|nyi|dnd|dnt|unused|placeholder)\b|\[ph\]|^old(?=[A-Z])",
                      re.I)
BAD_NAME_CS = re.compile(r"^OLD")
BAD_QUEST = re.compile(r"^(<|\[|zz)|\b(deprecated|unused|test|nyi|dnd)\b", re.I)
BAD_MAP = re.compile(r"test|<unused>|emerald dream", re.I)
CRAFT_EFFECT = 24                  # SPELL_EFFECT_CREATE_ITEM
QUESTIE_ZONE_ALIAS = {1585: 230}   # QuestieDB zone ID without an AreaTable row -> Blackrock Depths map
ENTRANCE_COLS = ['map_id', 'name', 'ui_map', 'x', 'y', 'source']


def norm(s):
    return re.sub(r'[^a-z0-9]+', ' ', str(s or '').lower()).strip()


def bad_name(n):
    return not n or bool(BAD_NAME.search(n)) or bool(BAD_NAME_CS.match(n))


def money(c):
    c = to_int(c)
    if c <= 0:
        return None
    g, s, cu = c // 10000, (c // 100) % 100, c % 100
    return ' '.join(p for p in ('%dg' % g if g else '', '%ds' % s if s else '', '%dc' % cu if cu else '') if p)


class Places:
    """Where QuestieDB puts an NPC or object: an instance ("i<MapID>") or a zone uiMap with its densest spot."""

    def __init__(self, C, Q, zones, area2ui):
        self.C, self.Q, self.zones, self.area2ui = C, Q, zones, area2ui
        self.inst_of_area = {}
        for aid, r in C['area'].items():
            m = C['map'].get(to_int(r['ContinentID']), {})
            if m.get('InstanceType') in ('1', '2') and not BAD_MAP.search(m.get('MapName_lang', '')):
                self.inst_of_area[aid] = to_int(r['ContinentID'])
        for mid, m in C['map'].items():   # instance areas whose AreaTable row sits on a continent
            a = to_int(m.get('AreaTableID'))
            if m.get('InstanceType') in ('1', '2') and a and a not in area2ui and not BAD_MAP.search(m['MapName_lang']):
                self.inst_of_area.setdefault(a, mid)
        for a, mid in QUESTIE_ZONE_ALIAS.items():
            self.inst_of_area.setdefault(a, mid)
        self.enc_maps = collections.defaultdict(set)
        for r in C['encounters']:
            mid = to_int(r['MapID'])
            m = C['map'].get(mid, {})
            if m.get('InstanceType') in ('1', '2') and not BAD_MAP.search(m.get('MapName_lang', '')):
                self.enc_maps[norm(r['Name_lang'])].add(mid)
        self._cache = {}

    def parent_ui(self, aid):
        steps = 0
        while aid and steps < 6:
            if aid in self.area2ui:
                return self.area2ui[aid]
            aid = to_int(self.C['area'].get(aid, {}).get('ParentAreaID'))
            steps += 1
        return None

    def place(self, spawns, zone_id, prefer_ui=None):
        """(where, x, y, weight) or None. where = 'i<MapID>' or a uiMap; x / y None when unknown."""
        inst = collections.Counter()
        pts = collections.defaultdict(list)
        if isinstance(spawns, dict):
            for aid, lst in spawns.items():
                if not isinstance(aid, int):
                    continue
                good = [p for p in md.svlua.to_list(lst) if isinstance(p, list) and len(p) >= 2
                        and all(isinstance(c, (int, float)) for c in p[:2])]
                if aid in self.inst_of_area:
                    inst[self.inst_of_area[aid]] += max(1, len(good))
                    continue
                ui = self.parent_ui(aid)
                if ui in self.zones:
                    pts[ui].extend((ui, float(p[0]), float(p[1])) for p in good if 0 < p[0] < 100 and 0 < p[1] < 100)
                    if not good:
                        pts.setdefault(ui, [])
        n_world = sum(len(v) for v in pts.values())
        if inst and sum(inst.values()) >= n_world:
            m, n = inst.most_common(1)[0]
            return ('i%d' % m, None, None, n)
        if pts:
            ui = prefer_ui if prefer_ui in pts and pts[prefer_ui] else max(pts, key=lambda u: (len(pts[u]), -u))
            if pts[ui]:
                cl = md.clusters(self.zones, pts[ui], 1)
                if cl:
                    _, ui, x, y = cl[0]
                    return (ui, round(x, 1), round(y, 1), n_world)
            return (ui, None, None, 0)
        z = to_int(zone_id)
        if z:
            if z in self.inst_of_area:
                return ('i%d' % self.inst_of_area[z], None, None, 0)
            ui = self.parent_ui(z)
            if ui in self.zones:
                return (ui, None, None, 0)
        return None

    def npc(self, nid, prefer_ui=None):
        k = ('n', nid, prefer_ui)
        if k not in self._cache:
            rec = self.Q['npc'].get(nid) or {}
            pl = self.place(rec.get(7), rec.get(9), prefer_ui)
            if pl is None and self.enc_maps.get(norm(rec.get(1))):   # no spawn data: a boss of a known instance
                pl = ('i%d' % min(self.enc_maps[norm(rec.get(1))]), None, None, 0)
            self._cache[k] = pl
        return self._cache[k]

    def obj(self, oid):
        k = ('o', oid)
        if k not in self._cache:
            rec = self.Q['object'].get(oid) or {}
            self._cache[k] = self.place(rec.get(4), rec.get(5))
        return self._cache[k]


def src(kind, where, label, x=None, y=None, extra=None, prov='client', weight=0, faction='both', fid=None):
    return dict(kind=kind, where=where, label=label, x=x, y=y, extra=extra, prov=prov, weight=weight,
                faction=faction, id=fid)


def read_entrances(path):
    """map ID -> (uiMap, x, y), or None for a row whose entrance is blank (unknown)."""
    out = {}
    if not path or not os.path.exists(path):
        return out
    with open(path, encoding='utf-8-sig', newline='') as f:
        for r in csv.DictReader(f):
            mid = to_int(r.get('map_id'))
            if not mid:
                continue
            ui = to_int(r.get('ui_map'))
            x, y = (r.get('x') or '').strip(), (r.get('y') or '').strip()
            out[mid] = (ui, float(x), float(y)) if ui and x and y else None
    return out


def corpse_entrance(zones, m):
    """The instance's Map corpse point (where a ghost of this instance is sent) on its zone map, or None."""
    if to_int(m.get('CorpseMapID'), -1) < 0 or not (float(m.get('Corpse_0') or 0) or float(m.get('Corpse_1') or 0)):
        return None
    name = m['MapName_lang']
    return md.to_map(zones, to_int(m['CorpseMapID']), float(m['Corpse_0']), float(m['Corpse_1']),
                     md.DUNGEON_ZONE.get(name.lower()) or md.DUNGEON_ZONE.get(norm(name)))


def build(cfg, opt):
    t0 = time.time()
    fmt = opt.format
    C = md.load_client(cfg)
    log('quest cache')
    QC = md.load_questcache(cfg)
    Q = md.load_questie(cfg, C)
    zones, area2ui = md.load_zones(cfg, Q)
    P = Places(C, Q, zones, area2ui)

    def horde_suffix(label, fac):
        return label + (' (Horde)' if fmt == 1 and fac == 'Horde' else '')

    # ---- appearances (client)
    log('appearances')
    ia = {to_int(r['ID']): r for r in md.read_csv(cfg, 'ItemAppearance')}
    ima = {}
    for r in md.read_csv(cfg, 'ItemModifiedAppearance'):
        iid = to_int(r['ItemID'])
        cur = ima.get(iid)
        if cur is None or (to_int(r['ItemAppearanceModifierID']), to_int(r['OrderIndex'])) < \
                (to_int(cur['ItemAppearanceModifierID']), to_int(cur['OrderIndex'])):
            ima[iid] = r
    log('  ItemModifiedAppearance: %d items, ItemAppearance: %d' % (len(ima), len(ia)))

    drop_stats = collections.Counter()
    items = {}
    for iid, r in ima.items():
        app, stype = to_int(r['ItemAppearanceID']), to_int(r['TransmogSourceTypeEnum'])
        it = C['item'].get(iid)
        sp = C['itemsparse'].get(iid)
        qi = Q['item'].get(iid) or {}
        if not app or app not in ia:
            drop_stats['no appearance'] += 1
            continue
        if stype in SKIP_SOURCE_TYPES:
            drop_stats['not valid for transmog / not collectable'] += 1
            continue
        if not it:
            drop_stats['no Item row'] += 1
            continue
        inv, cls, sub = to_int(it.get('InventoryType')), to_int(it.get('ClassID'), -1), to_int(it.get('SubclassID'), -1)
        if inv not in MOG_SLOTS or cls not in (2, 4):
            drop_stats['not a transmog slot'] += 1
            continue
        name = (sp or {}).get('Display_lang') or qi.get(1) or ''
        if not name:
            drop_stats['no name'] += 1
            continue
        if bad_name(name):
            drop_stats['test / deprecated name'] += 1
            continue
        items[iid] = dict(id=iid, name=name, inv=inv, cls=cls, sub=sub,
                          quality=to_int(sp.get('OverallQualityID')) if sp else -1,
                          req=to_int(sp.get('RequiredLevel')) if sp else to_int(qi.get(10)),
                          app=app, srcid=to_int(r['ID']), stype=stype, in_sparse=bool(sp),
                          price=to_int(sp.get('BuyPrice')) if sp else 0, srcs=[])
    log('  candidate items: %d (%s)' % (len(items), dict(drop_stats)))

    # ---- crafted (client)
    skill_of_spell = {}
    for r in C['skilllineability'].values():
        sp_, sk = to_int(r.get('Spell')), to_int(r.get('SkillLine'))
        if sp_ and sk in md.PROFESSIONS:
            skill_of_spell.setdefault(sp_, (sk, to_int(r.get('TrivialSkillLineRankLow'))))
    n_craft = 0
    for r in C['spelleffect'].values():
        if to_int(r.get('Effect')) != CRAFT_EFFECT:
            continue
        iid, sp_ = to_int(r.get('EffectItemType')), to_int(r.get('SpellID'))
        if iid in items and sp_ in skill_of_spell:
            sk, rank = skill_of_spell[sp_]
            items[iid]['srcs'].append(src(K_CRAFT, 0, md.PROFESSIONS[sk], extra=rank or None, fid=sp_))
            n_craft += 1
    log('  crafted sources: %d' % n_craft)

    # ---- quest rewards (questcache + QuestieDB)
    quest_rewards = collections.defaultdict(dict)   # item -> quest -> provenance
    for qid, r in QC.items():
        for x, _ in list(r.get('reward_items', [])) + list(r.get('reward_choice_items', [])):
            if x in items:
                quest_rewards[x][qid] = 'client'
    for iid in items:
        for qid in md.svlua.to_list((Q['item'].get(iid) or {}).get(6)):
            if isinstance(qid, int) and qid:
                quest_rewards[iid].setdefault(qid, 'questie')

    def quest_place(qid):
        q = Q['quest'].get(qid) or {}
        zone = to_int(q.get(17))
        prefer = P.parent_ui(zone) if zone > 0 else None
        starts = md.svlua.to_list(q.get(2))
        starts = starts + [None] * (3 - len(starts))
        for n in md.svlua.to_list(starts[0]):
            if isinstance(n, int):
                pl = P.npc(n, prefer)
                if pl and pl[1] is not None:
                    return pl
        for o in md.svlua.to_list(starts[1]):
            if isinstance(o, int):
                pl = P.obj(o)
                if pl and pl[1] is not None:
                    return pl
        for n in md.svlua.to_list(starts[0]):
            if isinstance(n, int) and P.npc(n, prefer):
                return P.npc(n, prefer)
        if zone > 0:
            if zone in P.inst_of_area:
                return ('i%d' % P.inst_of_area[zone], None, None, 0)
            if prefer in zones:
                return (prefer, None, None, 0)
        return None

    n_q = collections.Counter()
    for iid, qs in quest_rewards.items():
        for qid, prov in qs.items():
            q = Q['quest'].get(qid) or {}
            title = (QC.get(qid) or {}).get('title') or q.get(1) or ''
            if not title or BAD_QUEST.search(title):
                continue
            pl = quest_place(qid)
            fac = md.faction_of(q.get(6))
            if pl:
                prov = prov if prov == 'questie' else 'client+questie'
            where, x, y = (pl[0], pl[1], pl[2]) if pl else (0, None, None)
            items[iid]['srcs'].append(src(K_QUEST, where, horde_suffix(title, fac), x, y, qid, prov, 1, fac, qid))
            n_q[prov] += 1
    log('  quest reward sources: %s' % dict(n_q))

    # ---- QuestieDB: drops, objects, containers, vendors
    enc_names = collections.defaultdict(set)
    for r in C['encounters']:
        enc_names[to_int(r['MapID'])].add(norm(r['Name_lang']))

    def npc_info(nid):
        rec = Q['npc'].get(nid) or {}
        return rec.get(1) or '', to_int(rec.get(6)), str(rec.get(13) or ''), to_int(rec.get(4)), to_int(rec.get(5))

    obj_items = collections.Counter()
    for iid in items:
        for oid in set(o for o in md.svlua.to_list((Q['item'].get(iid) or {}).get(3)) if isinstance(o, int)):
            obj_items[oid] += 1
    inst_levels = collections.defaultdict(list)
    n_src = collections.Counter()
    for iid, it in items.items():
        qi = Q['item'].get(iid) or {}
        drops = []
        npcs = [n for n in md.svlua.to_list(qi.get(2)) if isinstance(n, int)]
        for nid in npcs:
            name, rank, friendly, lo, hi = npc_info(nid)
            pl = P.npc(nid)
            if not name or not pl:
                continue
            where, x, y, wgt = pl
            if isinstance(where, str):
                if lo:
                    inst_levels[where].append((lo, hi or lo))
                boss = rank == 3 or norm(name) in enc_names.get(int(where[1:]), ())
                kind = K_BOSS if boss else K_DROP
            else:
                kind = K_DROP
            label = name if kind == K_BOSS else name + (' (rare)' if rank in (2, 4) else
                                                        (' (world boss)' if rank == 3 else ''))
            drops.append(src(kind, where, label, x, y, None, 'questie', wgt, 'both', nid))
        if len(npcs) > WORLD_DROP_NPCS:
            drops.append(src(K_WORLD, 0, 'World drop (%d creatures)' % len(npcs), prov='questie', weight=len(npcs)))
        it['srcs'] += drops
        for oid in md.svlua.to_list(qi.get(3)):
            if not isinstance(oid, int):
                continue
            oname = (Q['object'].get(oid) or {}).get(1) or ''
            if not oname or bad_name(oname):
                continue
            if obj_items[oid] > RANDOM_CHEST_ITEMS:
                r = src(K_OBJECT, 0, oname + ' (random loot)', prov='questie', weight=-obj_items[oid], fid=oid)
                r['random'] = True
                it['srcs'].append(r)
                continue
            pl = P.obj(oid)
            where, x, y, wgt = pl if pl else (0, None, None, 0)
            it['srcs'].append(src(K_OBJECT, where, oname, x, y, None, 'questie', wgt, 'both', oid))
        for cid in md.svlua.to_list(qi.get(4)):
            if not isinstance(cid, int):
                continue
            cname = (C['itemsparse'].get(cid) or {}).get('Display_lang') or (Q['item'].get(cid) or {}).get(1)
            if cname and not bad_name(cname):
                it['srcs'].append(src(K_OBJECT, 0, cname, prov='questie', fid=cid))
        for vid in md.svlua.to_list(qi.get(14)):
            if not isinstance(vid, int):
                continue
            name, rank, friendly, lo, hi = npc_info(vid)
            pl = P.npc(vid)
            if not name:
                continue
            fac = 'Horde' if friendly == 'H' else ('Alliance' if friendly == 'A' else 'both')
            where, x, y, wgt = pl if pl else (0, None, None, 0)
            it['srcs'].append(src(K_VENDOR, where, horde_suffix(name, fac), x, y,
                                  money(it['price']), 'questie', wgt, fac, vid))
    for it in items.values():
        for s in it['srcs']:
            n_src[(s['kind'], s['prov'])] += 1

    # ---- client-only fallbacks: the client names the kind of source, nothing names the place
    n_fb = collections.Counter()
    for it in items.values():
        if it['srcs'] or it['stype'] not in FALLBACK or not it['in_sparse']:
            continue
        kind, label = FALLBACK[it['stype']]
        it['srcs'].append(src(kind, 0, label, extra=money(it['price']) if kind == K_VENDOR else None))
        n_fb[label] += 1
    log('  client-only fallbacks: %s' % dict(n_fb))

    # ---- rank, dedupe, cap
    def key(s):
        k = (KIND_ORDER[s['kind']],) + ((s['faction'] == 'Horde',) if fmt == 1 else ()) + \
            (s['where'] == 0, s['x'] is None, s['prov'] == 'questie', -s['weight'], str(s['where']), s['label'])
        return k if fmt == 1 else k + (s['faction'],)

    no_source = collections.Counter()
    for iid in list(items):
        it = items[iid]
        seen, out, n_random = set(), [], 0
        for s in sorted(it['srcs'], key=key):
            k = (s['kind'], s['where'], s['label']) + (() if fmt == 1 else (s['faction'],))
            if k in seen or (s.get('random') and n_random >= MAX_RANDOM_CHESTS):
                continue
            seen.add(k)
            n_random += 1 if s.get('random') else 0
            out.append(s)
        if not out:
            no_source['client source type %d' % it['stype']] += 1
            del items[iid]
            continue
        it['all_sources'] = len(out)
        if fmt == 1:
            it['srcs'] = out[:MAX_SOURCES]
        else:   # the best MAX_SOURCES usable by each faction, in one best-first list
            keep = set()
            for f in ('Alliance', 'Horde'):
                keep.update([i for i, s in enumerate(out) if s['faction'] in ('both', f)][:MAX_SOURCES])
            it['srcs'] = [s for i, s in enumerate(out) if i in keep]
    log('  items kept: %d; dropped for no source: %d' % (len(items), sum(no_source.values())))

    # ---- places
    used_inst = sorted({s['where'] for it in items.values() for s in it['srcs'] if isinstance(s['where'], str)},
                       key=lambda w: int(w[1:]))
    lfg = collections.defaultdict(list)
    for d in md.dungeon_index(C):
        if d['map_id'] is not None and d['min_level']:
            lfg[d['map_id']].append(d['min_level'])
    ent_csv = {} if opt.write_entrances else read_entrances(cfg['entrances'])
    ent_rows, n_ent = [], collections.Counter()
    instances = {}
    for w in used_inst:
        mid = int(w[1:])
        m = C['map'][mid]
        name = m['MapName_lang']
        typ = 'raid' if m['InstanceType'] == '2' else 'dungeon'
        if typ == 'raid':
            lo = hi = 60
        elif lfg.get(mid):
            lo = min(lfg[mid])
            hi = min(60, max(lfg[mid]) + 10)
        elif inst_levels.get(w):
            lo, hi = min(a for a, b in inst_levels[w]), max(b for a, b in inst_levels[w])
        else:
            lo = hi = 0
        if mid in ent_csv:
            ent = ent_csv[mid]
            n_ent['entrances.csv' if ent else 'entrances.csv (blank)'] += 1
        else:
            ent = corpse_entrance(zones, m)
            n_ent['Map corpse point' if ent else 'unknown'] += 1
            ent_rows.append([mid, name] + ([ent[0], repr(round(ent[1], 1)), repr(round(ent[2], 1)),
                                            'client Map corpse point'] if ent else
                                           ['', '', '', 'none in client data (no Map corpse point)']))
        instances[w] = (name, typ, lo, hi, ent[0] if ent else 0,
                        round(ent[1], 1) if ent else None, round(ent[2], 1) if ent else None)
    log('  instances: %d; entrances: %s' % (len(instances), dict(n_ent)))
    if opt.write_entrances:
        with open(cfg['entrances'], 'w', encoding='utf-8', newline='') as f:
            wr = csv.writer(f, lineterminator='\n')
            wr.writerow(ENTRANCE_COLS)
            wr.writerows(ent_rows)
        log('  wrote %s (%d rows)' % (cfg['entrances'], len(ent_rows)))
    else:
        for row in ent_rows:
            log('  note: i%d (%s) is not in %s; used: %s' % (row[0], row[1], os.path.basename(cfg['entrances'] or '-'),
                                                             row[5]))
    missing_ent = sorted(w for w, v in instances.items() if not v[4])
    log('  instances without an entrance: %s' % (', '.join('%s %s' % (w, instances[w][0]) for w in missing_ent) or '-'))

    # Boss order per instance (DungeonEncounter.OrderIndex), limited to labels that the sources use as a boss.
    boss_labels = collections.defaultdict(dict)
    for it in items.values():
        for s in it['srcs']:
            if s['kind'] == K_BOSS and isinstance(s['where'], str):
                boss_labels[s['where']].setdefault(norm(s['label']), s['label'])
    encounters = {}
    for w in instances:
        mid = int(w[1:])
        rows = sorted((to_int(r['OrderIndex']), to_int(r['ID']), r['Name_lang']) for r in C['encounters']
                      if to_int(r['MapID']) == mid)
        order, seen = [], set()
        for _, _, name in rows:
            n = norm(name)
            if n in seen or n not in boss_labels.get(w, {}):
                continue
            seen.add(n)
            order.append(boss_labels[w][n])
        if order:
            encounters[w] = order
    used_ui = {s['where'] for it in items.values() for s in it['srcs'] if isinstance(s['where'], int) and s['where']}
    used_ui |= {v[4] for v in instances.values() if v[4]}
    zone_names = {ui: zones[ui]['name'] for ui in sorted(used_ui) if ui in zones}

    # ---- write
    os.makedirs(opt.out, exist_ok=True)
    sizes = write_lua_files(cfg, opt, items, zone_names, instances, encounters)
    write_package(cfg, opt.out, any(s['prov'] != 'client' for it in items.values() for s in it['srcs']))
    if opt.csv:
        write_items_csv(opt.csv, items, zone_names, instances)
    report(items, zone_names, instances, drop_stats, no_source, n_src, sizes, time.time() - t0, encounters, len(QC))


HEADER = ('-- ' + TITLE + ' data (C) 2026 ' + AUTHOR + '. SPDX-License-Identifier: GPL-3.0-or-later\n'
          '-- Data contract v%d, generated %s from WoW Forever client data (build %s) by build_mog_public.py.\n'
          '-- Do not edit by hand. Drop, quest and vendor sources: see NOTICE.txt.\n'
          'local D = ForeverTransmogFinderData or {}\n'
          'ForeverTransmogFinderData = D\n')


def write_file(path, body, cfg, opt):
    text = HEADER % (opt.format, opt.date, cfg['build']) + body
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    return len(text.encode('utf-8'))


def src_tuple(s, fmt):
    row = [s['kind'], s['where'], s['label'], s['x'], s['y'], s['extra']]
    if fmt == 2:
        row.append(FACTION_CODE.get(s['faction']))   # None (both / unknown): left out by lval
    return row


def write_lua_files(cfg, opt, items, zone_names, instances, encounters):
    sizes = {}
    ids = sorted(items)
    chunks = [ids[i:i + ITEMS_PER_FILE] for i in range(0, len(ids), ITEMS_PER_FILE)]
    files = []
    for n, chunk in enumerate(chunks, 1):
        lines = ['local t = D.items or {}', 'D.items = t',
                 '-- [itemID] = {"name", invType, classID, subclassID, quality (-1 = not in client data), reqLevel,'
                 ' appearanceID, sourceID}']
        for iid in chunk:
            it = items[iid]
            lines.append('t[%d]=%s' % (iid, lval([it['name'], it['inv'], it['cls'], it['sub'], it['quality'],
                                                   it['req'], it['app'], it['srcid']])))
        fn = 'Items%d.lua' % n
        sizes[fn] = write_file(os.path.join(opt.out, fn), '\n'.join(lines) + '\n', cfg, opt)
        files.append(fn)
    if opt.format == 1:
        src_doc = ['-- [itemID] = {{kind, where, "label", x, y, extra}, ...} best first. kind: 1 boss, 2 mob drop,'
                   ' 3 quest reward,']
    else:
        src_doc = ['-- [itemID] = {{kind, where, "label", x, y, extra, faction}, ...} best first. faction: "A" Alliance'
                   ' only, "H" Horde',
                   '-- only, left out (nil) for both or unknown. kind: 1 boss, 2 mob drop, 3 quest reward,']
    src_doc += ['-- 4 vendor, 5 crafted, 6 container / object, 7 world drop / unknown. where: uiMap, "i<MapID>"'
                ' (dungeon / raid)',
                '-- or 0 (no place). extra: quest ID (3), skill rank (5), price (4); drop chances are not known (nil).']
    for n, chunk in enumerate(chunks, 1):
        lines = ['local s = D.src or {}', 'D.src = s'] + src_doc
        for iid in chunk:
            lines.append('s[%d]=%s' % (iid, lval([src_tuple(s, opt.format) for s in items[iid]['srcs']])))
        fn = 'Sources%d.lua' % n
        sizes[fn] = write_file(os.path.join(opt.out, fn), '\n'.join(lines) + '\n', cfg, opt)
        files.append(fn)
    lines = ['D.version = %d' % opt.format, 'D.build = %s' % lstr(cfg['build']), 'D.generated = %s' % lstr(opt.date),
             '-- [uiMap] = "zone name" (enUS; the UI prefers C_Map.GetMapInfo(uiMap).name)', 'D.zones = {']
    lines += ['[%d]=%s,' % (ui, lstr(nm)) for ui, nm in sorted(zone_names.items())]
    lines += ['}', '-- ["i<MapID>"] = {"name", "dungeon"|"raid", minLevel, maxLevel, entranceUiMap (0 = unknown),'
              ' entranceX, entranceY}', 'D.instances = {']
    lines += ['[%s]=%s,' % (lstr(w), lval(list(v))) for w, v in sorted(instances.items(), key=lambda kv: int(kv[0][1:]))]
    lines.append('}')
    lines += ['-- ["i<MapID>"] = {"boss", ...}: the boss labels used in D.src, in the order you meet them (client',
              '-- DungeonEncounter.OrderIndex). Optional; bosses not listed come after the listed ones.', 'D.encounters = {']
    lines += ['[%s]=%s,' % (lstr(w), lval(list(v))) for w, v in sorted(encounters.items(), key=lambda kv: int(kv[0][1:]))]
    lines.append('}')
    sizes['Places.lua'] = write_file(os.path.join(opt.out, 'Places.lua'), '\n'.join(lines) + '\n', cfg, opt)
    files.insert(0, 'Places.lua')
    toc = ['## Interface: 16001',
           '## Title: ' + TITLE + ' Data',
           '## Notes: The item list for ' + TITLE + ' (loaded on demand).',
           '## Author: ' + AUTHOR,
           '## Version: %s' % opt.version,
           '## Group: ' + MAIN_ADDON,
           '## Category: Collections',
           '## IconTexture: Interface\\AddOns\\' + MAIN_ADDON + '\\Media\\icon-64',
           '## Dependencies: ' + MAIN_ADDON,
           '## LoadOnDemand: 1',
           '## X-License: GPL-3.0-or-later',
           ''] + files
    p = os.path.join(opt.out, DATA_ADDON + '.toc')
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(toc) + '\n')
    sizes[DATA_ADDON + '.toc'] = os.path.getsize(p)
    for old in os.listdir(opt.out):   # chunks left from an earlier, bigger build
        if re.match(r'^(Items|Sources)\d+\.lua$', old) and old not in files:
            os.remove(os.path.join(opt.out, old))
    return sizes


def write_package(cfg, out_dir, has_questie):
    notice = os.path.join(out_dir, 'NOTICE.txt')
    if has_questie:
        shutil.copyfile(cfg['notice_file'], notice)
        with open(notice, encoding='utf-8') as f:
            if 'TODO(release' in f.read():
                log('  note: NOTICE.txt still holds TODO(release...) markers')
    elif os.path.exists(notice):
        os.remove(notice)
    shutil.copyfile(cfg['license_file'], os.path.join(out_dir, 'LICENSE.txt'))


def where_name(w, zone_names, instances):
    if isinstance(w, str):
        return instances.get(w, ('?',))[0]
    return zone_names.get(w, '') if w else ''


def write_items_csv(path, items, zone_names, instances):
    cols = ['item_id', 'name', 'inv_type', 'slot', 'class_id', 'subclass_id', 'quality', 'req_level',
            'appearance_id', 'source_id', 'client_source_type', 'sources_found', 'best_kind', 'best_kind_name',
            'best_where', 'best_where_name', 'best_label', 'best_x', 'best_y', 'best_extra', 'best_from',
            'best_faction', 'forever_new']
    with open(path, 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        w.writerow(cols)
        for iid in sorted(items):
            it = items[iid]
            s = it['srcs'][0]
            w.writerow([iid, it['name'], it['inv'], SLOT_NAME.get(it['inv'], ''), it['cls'], it['sub'], it['quality'],
                        it['req'], it['app'], it['srcid'], it['stype'], it['all_sources'], s['kind'],
                        KIND_NAME[s['kind']], s['where'], where_name(s['where'], zone_names, instances), s['label'],
                        '' if s['x'] is None else s['x'], '' if s['y'] is None else s['y'],
                        '' if s['extra'] is None else s['extra'],
                        {'client': 'client', 'questie': 'QuestieDB'}.get(s['prov'], 'client+QuestieDB'),
                        FACTION_CODE.get(s['faction'], ''), 'yes' if iid >= 200000 else ''])
    log('  wrote %s' % path)


def report(items, zone_names, instances, drop_stats, no_source, n_src, sizes, secs, encounters, n_quests):
    log('\n==== %s data ====' % TITLE)
    log('items: %d, distinct appearances: %d, quests in the quest cache: %d' % (
        len(items), len({it['app'] for it in items.values()}), n_quests))
    log('left out before sources: %s' % dict(drop_stats))
    log('left out, no source found: %d %s' % (sum(no_source.values()), dict(no_source)))
    log('sources found (before the cap of %d per item), by kind and origin:' % MAX_SOURCES)
    for (k, prov), n in sorted(n_src.items()):
        log('  %-20s %-15s %6d' % (KIND_NAME[k], prov, n))
    kept = collections.Counter(s['kind'] for it in items.values() for s in it['srcs'])
    log('kept sources by kind: ' + ', '.join('%s %d' % (KIND_NAME[k], n) for k, n in sorted(kept.items())))
    fac = collections.Counter(FACTION_CODE.get(s['faction'], '') for it in items.values() for s in it['srcs'])
    fac_kind = collections.Counter((FACTION_CODE.get(s['faction'], ''), s['kind'])
                                   for it in items.values() for s in it['srcs'] if s['faction'] != 'both')
    log('kept sources by faction: A %d, H %d, both/unknown %d (%s)' % (
        fac['A'], fac['H'], fac[''], ', '.join('%s %s %d' % (f, KIND_NAME[k], n) for (f, k), n in sorted(fac_kind.items()))))
    log('items whose sources are all one faction: A %d, H %d' % tuple(
        sum(1 for it in items.values() if all(FACTION_CODE.get(s['faction'], '') == c for s in it['srcs']))
        for c in ('A', 'H')))
    log('instances: %d; zones: %d; encounter lists: %d' % (len(instances), len(zone_names), len(encounters)))
    log('files:')
    for fn, n in sizes.items():
        log('  %-32s %9d bytes' % (fn, n))
    log('  Lua total %d bytes; built in %.1f s' % (sum(n for fn, n in sizes.items() if fn.endswith('.lua')), secs))


def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except AttributeError:
        pass
    ap = argparse.ArgumentParser(description='Build the %s item list (%s).' % (TITLE, DATA_ADDON))
    ap.add_argument('--config', default=os.path.join(HERE, 'config.json'), help='config file (default: config.json here)')
    ap.add_argument('--format', type=int, choices=(1, 2), default=2,
                    help='data contract version (default 2; 1 only for Forever Transmog Finder 0.3.0 and older)')
    ap.add_argument('--version', help='add-on version for the data TOC (default: "version" in the config)')
    ap.add_argument('--out', help='output folder (default: "out_dir" in the config)')
    ap.add_argument('--date', help='date written into the files, YYYY-MM-DD (default: today)')
    ap.add_argument('--csv', help='also write one CSV row per item (best source) to this file')
    ap.add_argument('--write-entrances', action='store_true',
                    help='rewrite the entrances CSV from the client Map table instead of reading it')
    a = ap.parse_args()
    cfg = md.load_config(a.config)
    a.version = a.version or cfg['version']
    if not a.version or not re.fullmatch(r'[0-9A-Za-z][0-9A-Za-z._+-]*', str(a.version)):
        raise SystemExit('give the add-on version with --version (or "version" in the config)')
    a.out = os.path.normpath(os.path.abspath(a.out)) if a.out else cfg['out_dir']
    if not a.out:
        raise SystemExit('give the output folder with --out (or "out_dir" in the config)')
    if md.has_wtf_part(a.out):
        raise SystemExit('refusing to write under a WTF folder: %s' % a.out)
    a.date = a.date or datetime.date.today().isoformat()
    if not re.fullmatch(r'\d{4}-\d\d-\d\d', a.date):
        raise SystemExit('--date must be YYYY-MM-DD')
    cfg['entrances'] = cfg['entrances'] or os.path.join(HERE, 'dungeon_entrances.csv')
    cfg['license_file'] = cfg['license_file'] or os.path.join(HERE, '..', 'LICENSE.txt')
    cfg['notice_file'] = cfg['notice_file'] or os.path.join(HERE, '..', 'NOTICE.txt')
    for k in ('license_file', 'notice_file'):
        if not os.path.isfile(cfg[k]):
            raise SystemExit('%s not found: %s' % (k, cfg[k]))
    missing = md.missing_inputs(cfg)
    if missing:
        raise SystemExit('missing input files (see README.md, Inputs):\n' +
                         '\n'.join('  %s  <-  %s' % (p, url) for p, url in missing))
    log('%s data, format %d, version %s, build %s -> %s' % (TITLE, a.format, a.version, cfg['build'], a.out))
    build(cfg, a)


if __name__ == '__main__':
    main()
