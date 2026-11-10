"""Import the authoritative section-5 tables; explicit input, no runtime dependency."""
import json
import re
import sys
from pathlib import Path


def build(source):
    families = []
    pool = side = None
    for line in source.splitlines():
        if line.startswith('### 5.') and 'corruption ' in line:
            pool = 'weapon' if 'Weapon:' in line else 'amulet' if 'Amulet:' in line else 'equipment'
            side = 'prefix' if 'prefixes' in line else 'suffix'
        if not re.match(r'\| `c[wae]_', line):
            continue
        title, tags, rarity, effect, bands, phase = [x.strip() for x in line.strip('|').split('|')]
        fid = re.search(r'`([^`]+)`', title)[1]
        name = re.search(r'\*\*([^*]+)\*\*', title)[1]
        rarity_name, weight = re.match(r'(\w+) \((\d+)\)', rarity).groups()
        stat, kind = re.findall(r'`([^`]+)`', effect)
        phase = int(phase[1:])
        fixed = bands.startswith('**Fixed:')
        row = dict(id=fid, name=name, pool=pool, side=side, rarity_class=rarity_name.lower(),
                   family_weight=int(weight), eligible_any_tags=re.findall(r'`([^`]+)`', tags)[0].split(' / '),
                   group=fid, min_item_level=(30 if rarity_name == 'Signature' else 40) if fixed else 1,
                   phase=phase, effects=[], fixed_tier=fixed)
        groups = {'cw_shepherds':'active_minion_limit', 'ca_soul_shepherd':'active_minion_limit',
                  'ce_deathless':'active_minion_limit', 'cw_of_fracturing':'extra_pierce',
                  'ce_grasping_shadows':'extra_pierce', 'cw_of_second_echo':'extra_chain',
                  'cw_splintered_fate':'additional_projectile', 'ce_of_relentless':'additional_projectile'}
        row['group'] = groups.get(fid, fid)
        if phase == 4:
            row['requires_feature'] = fid  # enable independently only with a tested handler
        for component in stat.split('+'):
            if phase == 4:
                row['effects'].append(dict(op=component, type=kind, value_source='fixed' if fixed else 'tier_roll'))
            else:
                row['effects'].append(dict(stat=component, type=kind, value_source='fixed' if fixed else 'tier_roll'))
        if fixed:
            row['fixed_value'] = int(re.search(r'\d+', bands)[0])
        else:
            row['tiers'] = []
            for tier, level, band in zip([3, 2, 1], [1, 28, 40], bands.split(' / ')):
                values = list(map(int, re.findall(r'\d+', band)))
                row['tiers'].append(dict(tier=tier, min_item_level=level, min=values[0], max=values[-1]))
        families.append(row)
    assert len(families) == 82
    return families


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    families = build(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
    (root / 'data/corruption_affixes.json').write_text(json.dumps(families, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Imported {len(families)} corruption families')
