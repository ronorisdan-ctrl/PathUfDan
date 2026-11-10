"""Seeded scenarios, not measured player income. Does not tune game data."""
import argparse
import json
import math
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def geometric_mean(rng, probability, trials):
    return sum(math.ceil(math.log1p(-rng.random()) / math.log1p(-probability)) for _ in range(trials)) / trials


def simulate(hours=100_000, bosses=6, elites=60, seed=20261104):
    cfg = json.loads((ROOT / 'data/corruption.json').read_text(encoding='utf-8-sig'))
    rng = random.Random(seed)
    results = {'seed': seed, 'simulated_hours_per_scenario': hours,
               'assumptions': {'bosses_per_hour': bosses, 'endgame_elites_per_hour': elites,
                               'note': 'Scenario inputs, not measured clear times; no drop-rate tuning.'}, 'income': []}
    for name, boss_chance, eligible_elites in [('T4', 0, 0), ('T5', cfg['brand_drops']['boss_by_tier']['5'], elites),
                                               ('T6', cfg['brand_drops']['boss_by_tier']['6'], elites),
                                               ('Endless capped', cfg['brand_drops']['endless_boss_cap'], elites)]:
        p_elite = cfg['brand_drops']['elite_chance']
        brands = sum(rng.random() < boss_chance for _ in range(hours * bosses))
        brands += sum(rng.random() < p_elite for _ in range(hours * eligible_elites))
        expected = bosses * boss_chance + eligible_elites * p_elite
        observed = brands / hours
        assert abs(observed - expected) < 0.02
        results['income'].append(dict(tier=name, expected_brands_per_hour=expected, simulated_brands_per_hour=observed))
    w = cfg['outcome_weights_basis_points']
    prefix = (w['single'] * 0.5 + w['double']) / 10000
    double = w['double'] / 10000
    category = cfg['rarity_category_weights']
    named_mythic = prefix * category['mythic'] / sum(category.values())
    both_t1 = double * 0.1 * 0.1
    results['attempts'] = []
    for label, probability in [('Any double', double), ('Forbidden Knowledge on eligible enabled level-40+ amulet', named_mythic),
                                ('Double T1, conditional on both families ordinary', both_t1)]:
        observed = geometric_mean(rng, probability, hours)
        assert abs(observed * probability - 1) < 0.025
        results['attempts'].append(dict(event=label, probability=probability, expected_attempts=1 / probability, simulated_mean_attempts=observed))
    results['note'] = 'Geometric expectations include the successful attempt; no guarantee/pity. Both-T1 assumes two ordinary selections; actual unconditional rates depend on eligible categories.'
    return results


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--hours', type=int, default=100_000)
    parser.add_argument('--bosses-per-hour', type=int, default=6)
    parser.add_argument('--elites-per-hour', type=int, default=60)
    parser.add_argument('--out', type=Path, default=ROOT / 'docs/corruption_economy.json')
    args = parser.parse_args()
    result = simulate(args.hours, args.bosses_per_hour, args.elites_per_hour)
    args.out.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
