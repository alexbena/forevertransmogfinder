# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Gitano Calvo
"""Reader for the WoW Forever quest cache questcache.wdb (magic WQST, record version 12, client 1.60.1).

File layout (little-endian): a 24-byte header (char magic[4] reversed, uint32 build, char locale[4] reversed,
uint32 recordSize, uint32 recordVersion, uint32 cacheVersion), then records (uint32 id, uint32 length,
byte data[length]) up to a terminator of two zero uint32. A record is the server's quest query response
after its leading fields; on Forever it carries two extra int32 after QuestType compared with retail 12.1.
"""
import struct


class Reader:
    def __init__(self, data):
        self.b = data
        self.o = 0
        self.bitpos = 8
        self.cur = 0

    def _take(self, fmt):
        self.reset_bits()
        v = struct.unpack_from('<' + fmt, self.b, self.o)
        self.o += struct.calcsize('<' + fmt)
        return v[0] if len(v) == 1 else v

    def i8(self):
        return self._take('b')

    def u8(self):
        return self._take('B')

    def i32(self):
        return self._take('i')

    def u32(self):
        return self._take('I')

    def i64(self):
        return self._take('q')

    def f32(self):
        return round(self._take('f'), 6)

    def fixed_string(self, n):
        self.reset_bits()
        s = self.b[self.o:self.o + n]
        self.o += n
        return s.decode('utf-8', 'replace')

    def reset_bits(self):
        self.bitpos = 8

    def bit(self):
        if self.bitpos == 8:
            self.cur = self.b[self.o]
            self.o += 1
            self.bitpos = 0
        v = (self.cur >> (7 - self.bitpos)) & 1
        self.bitpos += 1
        return v

    def bits(self, n):
        v = 0
        for _ in range(n):
            v = (v << 1) | self.bit()
        return v

    def remaining(self):
        return len(self.b) - self.o


def read_wdb(path):
    with open(path, 'rb') as f:
        b = f.read()
    magic, build, loc, rsize, rver, cver = struct.unpack_from('<4sI4sIII', b, 0)
    hdr = dict(magic=magic[::-1].decode(), build=build, locale=loc[::-1].decode(),
               record_size=rsize, record_version=rver, cache_version=cver, file_size=len(b))
    recs, off = [], 24
    while off + 8 <= len(b):
        rid, ln = struct.unpack_from('<II', b, off)
        if rid == 0 and ln == 0:
            break
        recs.append((rid, b[off + 8:off + 8 + ln]))
        off += 8 + ln
    hdr['records'] = len(recs)
    return hdr, recs


def parse_quest(rid, data):
    r = Reader(data)
    q = dict(id=r.i32())
    q['quest_type'] = r.i32()
    q['quest_level'] = r.i32()        # Forever extra field
    q['quest_package_id'] = r.i32()
    q['min_level'] = r.i32()          # Forever extra field
    q['content_tuning_id'] = r.i32()
    q['quest_sort_id'] = r.i32()
    q['quest_info_id'] = r.i32()
    q['suggested_group_num'] = r.i32()
    q['reward_next_quest'] = r.i32()
    q['reward_xp_difficulty'] = r.i32()
    q['reward_xp_multiplier'] = r.f32()
    q['reward_money'] = r.i32()
    q['reward_money_difficulty'] = r.i32()
    q['reward_money_multiplier'] = r.f32()
    q['reward_bonus_money'] = r.i32()
    n_disp_spell = r.u32()
    q['reward_spell'] = r.i32()
    q['reward_honor'] = r.i32()
    q['reward_kill_honor'] = r.f32()
    q['reward_favor'] = r.i32()
    q['reward_artifact_xp_difficulty'] = r.i32()
    q['reward_artifact_xp_multiplier'] = r.f32()
    q['reward_artifact_category_id'] = r.i32()
    q['start_item'] = r.i32()
    q['flags'] = r.u32()
    q['flags_ex'] = r.u32()
    q['flags_ex2'] = r.u32()
    q['flags_ex3'] = r.u32()
    q['reward_items'] = []
    q['item_drops'] = []
    for _ in range(4):
        item, amount, drop, drop_qty = r.i32(), r.i32(), r.i32(), r.i32()
        if item:
            q['reward_items'].append([item, amount])
        if drop:
            q['item_drops'].append([drop, drop_qty])
    q['reward_choice_items'] = []
    for _ in range(6):
        item, qty, disp = r.i32(), r.i32(), r.i32()
        if item:
            q['reward_choice_items'].append([item, qty])
    q['poi_continent'] = r.i32()
    q['poi_x'] = r.f32()
    q['poi_y'] = r.f32()
    q['poi_priority'] = r.i32()
    q['reward_title'] = r.i32()
    q['reward_arena_points'] = r.i32()
    q['reward_skill_line_id'] = r.i32()
    q['reward_num_skill_ups'] = r.i32()
    q['portrait_giver'] = r.i32()
    q['portrait_giver_mount'] = r.i32()
    q['portrait_giver_model_scene_id'] = r.i32()
    q['portrait_turn_in'] = r.i32()
    q['reward_factions'] = []
    for _ in range(5):
        fid, val, ovr, cap = r.i32(), r.i32(), r.i32(), r.i32()
        if fid:
            q['reward_factions'].append(dict(faction=fid, value=val, override=ovr, cap_in=cap))
    q['reward_faction_flags'] = r.i32()
    q['reward_currencies'] = []
    for _ in range(4):
        cid, cnt = r.i32(), r.i32()
        if cid:
            q['reward_currencies'].append([cid, cnt])
    q['sound_accept'] = r.i32()
    q['sound_turn_in'] = r.i32()
    q['area_group_id'] = r.i32()
    q['time_allowed'] = r.i64()
    n_obj = r.u32()
    q['allowable_races'] = r.u32() | (r.u32() << 32)
    n_tp = r.u32()
    n_ndtp = r.u32()
    q['expansion'] = r.i32()
    q['managed_world_state_id'] = r.i32()
    q['quest_session_bonus'] = r.i32()
    q['quest_giver_creature_id'] = r.i32()
    n_cond_desc = r.u32()
    n_cond_log = r.u32()
    n_house_room = r.u32()
    n_house_decor = r.u32()
    q['reward_display_spells'] = [dict(spell=r.i32(), player_condition=r.i32(), type=r.i32())
                                  for _ in range(n_disp_spell)]
    objs = []
    for _ in range(n_obj):
        o = dict(id=r.i32(), type=r.u32())
        o['storage_index'] = r.i8()
        o['object_id'] = r.i32()
        o['amount'] = r.i32()
        o['conditional_amount'] = r.i32()
        o['flags'] = r.u32()
        o['flags2'] = r.u32()
        o['progress_bar_weight'] = r.f32()
        n_vfx = r.i32()
        o['parent_objective_id'] = r.i32()
        o['visual_effects'] = [r.i32() for _ in range(n_vfx)]
        dlen = r.bits(8)
        o['visible'] = r.bit()
        o['description'] = r.fixed_string(dlen)
        objs.append(o)
    q['objectives'] = objs
    q['treasure_pickers'] = [r.i32() for _ in range(n_tp)]
    q['nondisplay_treasure_pickers'] = [r.i32() for _ in range(n_ndtp)]
    conds = []
    for kind, n in (('description', n_cond_desc), ('completion_log', n_cond_log)):
        for _ in range(n):
            pc, giver = r.i32(), r.i32()
            tl = r.bits(12)
            conds.append(dict(kind=kind, player_condition=pc, giver=giver, text=r.fixed_string(tl)))
    q['conditional_texts'] = conds
    q['reward_house_rooms'] = [r.i32() for _ in range(n_house_room)]
    q['reward_house_decor'] = [r.i32() for _ in range(n_house_decor)]
    r.reset_bits()
    lens = [r.bits(9), r.bits(12), r.bits(12), r.bits(9), r.bits(10), r.bits(8), r.bits(10), r.bits(8), r.bits(11)]
    q['ready_for_translation'] = r.bit()
    q['reset_by_scheduler'] = r.bit()
    keys = ['title', 'log_description', 'description', 'area_description',
            'portrait_giver_text', 'portrait_giver_name', 'portrait_turn_in_text',
            'portrait_turn_in_name', 'completion_log']
    for k, n in zip(keys, lens):
        q[k] = r.fixed_string(n)
    q['_leftover'] = r.remaining()
    if q['id'] != rid:
        q['_id_mismatch'] = rid
    return q


def parse_questcache(path):
    """(header, [quest records], [errors]). Raises ValueError for a file that is not a quest cache."""
    hdr, recs = read_wdb(path)
    if hdr['magic'] != 'WQST':
        raise ValueError('%s is not a quest cache (magic %s)' % (path, hdr['magic']))
    out, errors = [], []
    for rid, data in recs:
        try:
            out.append(parse_quest(rid, data))
        except Exception as e:
            errors.append(dict(id=rid, error=repr(e)))
    hdr['parsed'] = len(out)
    hdr['parse_errors'] = len(errors)
    return hdr, out, errors
