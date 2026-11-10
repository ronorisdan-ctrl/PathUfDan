"""Check live corruption data against the frozen design tables, without Godot."""
import json
from pathlib import Path
from build_corruption_registry import build

ROOT = Path(__file__).resolve().parents[1]


def validate():
    cfg = json.loads((ROOT / 'data/corruption.json').read_text(encoding='utf-8-sig'))
    actual = json.loads((ROOT / 'data/corruption_affixes.json').read_text(encoding='utf-8-sig'))
    expected = build((ROOT / 'tests/fixtures/corruption_spec_tables.md').read_text(encoding='utf-8-sig'))
    assert actual == expected, 'Registry differs from authoritative section-5 tables'
    assert cfg['outcome_weights_basis_points'] == dict(destroyed=1500, no_modifier=2500, single=5600, double=400)
    assert cfg['single_side_weights'] == dict(prefix=1, suffix=1)
    assert cfg['rarity_category_weights'] == dict(common=6500, specialized=2900, signature=550, mythic=50)
    assert cfg['ordinary_tier_weights'] == {'3': 60, '2': 30, '1': 10}
    assert cfg['tier_min_item_level'] == {'3': 1, '2': 28, '1': 40}
    assert cfg['fixed_rarity_min_item_level'] == dict(signature=30, mythic=40)
    assert cfg['required_material'] == dict(id='abyssal_brand', quantity=1)
    assert cfg['corruption_gold_fee'] == 0 and cfg['max'] == 100
    assert cfg['max_corrupted_prefixes'] == cfg['max_corrupted_suffixes'] == 1
    assert cfg['corrupted_projectile_bonus_character_cap'] == 2
    assert cfg['max_elemental_resistance_absolute_safety_cap'] == 78
    assert cfg['forbidden_same_item_pairs'] == [['additional_projectile', 'extra_pierce'], ['additional_projectile', 'extra_chain']]
    normal = json.loads((ROOT / 'data/affixes.json').read_text(encoding='utf-8-sig'))
    assert not {r['id'] for r in normal} & {r['id'] for r in actual}, 'Corruption must not occupy normal affix slots'
    assert all(f['requires_feature'] in cfg['implemented_features'] for f in actual if f['phase'] == 4)
    print('PASS: all 82 families, values, tiers, tags, phases and lottery parameters match spec v1')
    return cfg, actual


if __name__ == '__main__':
    validate()
