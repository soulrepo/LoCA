"""List octowow's custom and changed spells by diffing Spell.dbc across the client's MPQs.

Usage: python3 extract_spells.py <WoW Data folder> <output folder>

Writes custom_spells.csv (every spell that is new or changed compared to the
1.12.1 client in patch.MPQ) and loc_spells.csv (the subset that causes loss of
control, with the LoCA alert category it maps to).
"""
import csv, os, struct, sys
import mpq

# 1.12 Spell.dbc field indices (173 fields)
F_ID, F_MECHANIC, F_DURATION = 0, 5, 30
F_EFFECT, F_EFFECT_MECHANIC, F_EFFECT_AURA = 61, 79, 91
F_ICON, F_NAME, F_RANK, F_DESC = 117, 120, 129, 138

# Mirrors MECHANIC_MAP in Modules/Debuffs.lua
MECHANIC_LOC = {
    1: ("Charmed", 4), 2: ("Disoriented", 4), 3: ("Disarmed", 2), 5: ("Feared", 4),
    7: ("Rooted", 1), 8: ("Pacified", 3), 9: ("Silenced", 2), 10: ("Asleep", 4),
    12: ("Stunned", 3), 13: ("Frozen", 4), 14: ("Incapacitated", 4), 17: ("Polymorphed", 4),
    18: ("Banished", 4), 20: ("Shackled", 4), 23: ("Feared", 4), 24: ("Horrified", 4),
    30: ("Sapped", 4),
}
# SPELL_AURA_* ids that take control away, for spells with no mechanic set
AURA_LOC = {
    5: ("Disoriented", 4), 6: ("Charmed", 4), 7: ("Feared", 4), 12: ("Stunned", 3),
    26: ("Rooted", 1), 27: ("Silenced", 2), 60: ("Pacified", 3), 67: ("Disarmed", 2),
}
APPLY_AURA_EFFECTS = (6, 27, 35, 65)  # apply aura, persistent area aura, area aura (party), area aura


def read_dbc(data):
    magic, nrec, nfield, recsize, strsize = struct.unpack_from('<4s4I', data, 0)
    assert magic == b'WDBC', magic
    body = 20
    strings = data[body + nrec * recsize:]

    def string(off):
        end = strings.index(b'\0', off)
        return strings[off:end].decode('utf-8', 'replace')

    rows = {}
    for i in range(nrec):
        rec = struct.unpack_from('<%dI' % nfield, data, body + i * recsize)
        rows[rec[0]] = rec
    return rows, string


def load(archive_path, name):
    data = mpq.MPQ(archive_path).read('DBFilesClient\\' + name)
    if data is None:
        raise SystemExit('%s not found in %s' % (name, archive_path))
    return read_dbc(data)


def latest(data_dir, name, archives):
    for archive in reversed(archives):
        m = mpq.MPQ(os.path.join(data_dir, archive))
        if m.find('DBFilesClient\\' + name) is not None:
            return archive
    raise SystemExit(name + ' not found')


LOCALE_FIELDS = set()
for _base in (F_NAME, F_RANK, F_DESC, 147):
    LOCALE_FIELDS.update(range(_base + 1, _base + 9))  # non-enUS strings and the locale flags


def spell_view(rec, string):
    """Spell fields with the enUS strings resolved and translations left out, so
    records from different files compare on what the spell actually does."""
    view = [value for i, value in enumerate(rec) if i not in LOCALE_FIELDS]
    for base in (F_NAME, F_RANK, F_DESC, 147):
        view[base - sum(1 for i in LOCALE_FIELDS if i < base)] = string(rec[base])
    return view


def main():
    data_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    # client load order: base archives, patch.MPQ, then patch-?.mpq alphabetically (digits before letters)
    patches = sorted(f for f in os.listdir(data_dir) if f.lower().startswith('patch-') and f.lower().endswith('.mpq'))
    archives = ['dbc.MPQ', 'patch.MPQ'] + patches

    final_archive = latest(data_dir, 'Spell.dbc', archives)
    vanilla, vstr = load(os.path.join(data_dir, 'patch.MPQ'), 'Spell.dbc')
    final, fstr = load(os.path.join(data_dir, final_archive), 'Spell.dbc')
    icons, istr = load(os.path.join(data_dir, latest(data_dir, 'SpellIcon.dbc', archives)), 'SpellIcon.dbc')
    durations, _ = load(os.path.join(data_dir, latest(data_dir, 'SpellDuration.dbc', archives)), 'SpellDuration.dbc')
    mechanics, mstr = load(os.path.join(data_dir, latest(data_dir, 'SpellMechanic.dbc', archives)), 'SpellMechanic.dbc')

    # which patch introduced each spell's current version
    introduced = {}
    previous = vanilla
    prevstr = vstr
    for archive in patches:
        m = mpq.MPQ(os.path.join(data_dir, archive))
        if m.find('DBFilesClient\\Spell.dbc') is None:
            continue
        rows, rstr = read_dbc(m.read('DBFilesClient\\Spell.dbc'))
        for sid, rec in rows.items():
            old = previous.get(sid)
            if old is None or spell_view(old, prevstr) != spell_view(rec, rstr):
                introduced[sid] = archive
        previous, prevstr = rows, rstr

    def mechanic_name(mid):
        rec = mechanics.get(mid)
        return mstr(rec[1]) if rec else str(mid)

    def loc_for(rec):
        # only spells that put an aura on someone can show up as a debuff
        aura_effects = [k for k in range(3) if rec[F_EFFECT + k] in APPLY_AURA_EFFECTS]
        if not aura_effects:
            return None, ''
        ids = [rec[F_MECHANIC]] + [rec[F_EFFECT_MECHANIC + k] for k in aura_effects]
        best = None
        for mid in ids:
            hit = MECHANIC_LOC.get(mid)
            if hit and (best is None or hit[1] > best[1]):
                best = hit
        if best:
            return best, 'mechanic'
        for k in aura_effects:
            hit = AURA_LOC.get(rec[F_EFFECT_AURA + k])
            if hit and (best is None or hit[1] > best[1]):
                best = hit
        return (best, 'aura') if best else (None, '')

    header = ['spell_id', 'name', 'rank', 'status', 'patch', 'mechanic', 'effect_mechanics', 'auras',
              'duration_ms', 'icon', 'loc_category', 'loc_type', 'loc_source', 'description']
    rows_all, rows_loc = [], []
    for sid in sorted(final):
        rec = final[sid]
        if sid in vanilla:
            if spell_view(vanilla[sid], vstr) == spell_view(rec, fstr):
                continue
            status = 'changed'
        else:
            status = 'new'
        (loc, source) = loc_for(rec)
        icon = icons.get(rec[F_ICON])
        dur = durations.get(rec[F_DURATION])
        auras = [str(rec[F_EFFECT_AURA + k]) for k in range(3) if rec[F_EFFECT + k] in APPLY_AURA_EFFECTS and rec[F_EFFECT_AURA + k]]
        row = [sid, fstr(rec[F_NAME]), fstr(rec[F_RANK]), status, introduced.get(sid, ''),
               mechanic_name(rec[F_MECHANIC]) if rec[F_MECHANIC] else '',
               ' '.join(mechanic_name(rec[F_EFFECT_MECHANIC + k]) for k in range(3) if rec[F_EFFECT_MECHANIC + k]),
               ' '.join(auras),
               struct.unpack('<i', struct.pack('<I', dur[1]))[0] if dur else '',
               istr(icon[1]).split('\\')[-1] if icon else '',
               loc[0] if loc else '', loc[1] if loc else '', source,
               fstr(rec[F_DESC]).replace('\r', ' ').replace('\n', ' ')]
        rows_all.append(row)
        if loc:
            rows_loc.append(row)

    for fname, rows in (('custom_spells.csv', rows_all), ('loc_spells.csv', rows_loc)):
        with open(os.path.join(out_dir, fname), 'w', newline='', encoding='utf-8') as f:
            w = csv.writer(f)
            w.writerow(header)
            w.writerows(rows)

    print('final Spell.dbc from', final_archive)
    print('vanilla spells:', len(vanilla), 'final spells:', len(final))
    print('new:', sum(1 for r in rows_all if r[3] == 'new'), 'changed:', sum(1 for r in rows_all if r[3] == 'changed'))
    print('loss of control (new or changed):', len(rows_loc))
    by_patch = {}
    for r in rows_all:
        by_patch[r[4]] = by_patch.get(r[4], 0) + 1
    print('by patch:', by_patch)


if __name__ == '__main__':
    main()
