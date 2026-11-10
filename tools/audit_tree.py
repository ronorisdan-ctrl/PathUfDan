#!/usr/bin/env python3
"""Phase 0 passive tree audit: classify every node Keep / Convert / Cut.

Writes docs/passive_tree_audit_phase0.csv (and .xlsx when openpyxl exists).
Verdicts are proposals: rules below plus a short hand-written override table.
Re-run after any tree change; the override table is keyed by node id.
"""
import csv, json, os, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = json.load(open(os.path.join(ROOT, "data", "passive_tree.json"), encoding="utf-8"))
N = {n["id"]: n for n in T}

TAGS = {
 "str": "attribute", "dex": "attribute", "int": "attribute", "vit": "attribute", "agi": "attribute", "wil": "attribute",
 "fire_damage": "fire", "ignite_chance": "fire,ignite", "res_fire": "fire,resist",
 "res_cold": "cold,resist", "lightning_damage": "lightning", "res_lightning": "lightning,resist",
 "elemental_damage": "elemental", "void_damage": "void", "res_void": "void,resist", "arcane_damage": "arcane",
 "physical_damage": "physical", "bleed_chance": "bleed,physical", "dot_damage": "dot",
 "status_chance": "ailment", "status_duration": "ailment",
 "melee_damage": "melee", "one_handed_damage": "melee,one_hand", "two_handed_damage": "melee,two_hand",
 "attack_damage": "attack", "attack_speed": "attack,speed", "projectile_damage": "projectile",
 "projectile_speed": "projectile", "pierce": "projectile", "bow_damage": "projectile,bow", "firearm_damage": "projectile,firearm",
 "spell_damage": "spell", "cast_speed": "spell,speed", "area": "area",
 "crit_chance": "crit", "crit_chance_flat": "crit", "crit_multi": "crit",
 "minion_damage": "minion", "minion_life": "minion", "minion_limit": "minion", "minion_speed": "minion",
 "turret_damage": "deployable", "turret_limit": "deployable", "turret_speed": "deployable", "trap_damage": "deployable,trap",
 "max_life": "life", "life_regen": "life", "life_on_hit": "life,sustain", "life_on_kill": "life,sustain",
 "max_mana": "mana", "mana_regen": "mana", "mana_cost": "mana",
 "armour": "armour,defence", "evasion": "evasion,defence", "block_chance": "block,defence", "damage_reduction": "defence",
 "move_speed": "speed,mobility", "cooldown_recovery": "cooldown", "damage": "generic", "damage_vs_elite": "elite",
}
FLAG_TAGS = {"momentum": "melee,attack", "fortress": "defence,stationary", "perfect_aim": "projectile,range",
 "automaton": "deployable", "convergence": "elemental,ailment", "one_mind": "minion", "blood_magic": "life,mana",
 "glass_cannon": "generic", "crimson_dance": "bleed", "wind_dancer": "dodge,mobility", "executioner": "crit,execute",
 "mind_over_matter": "mana,defence", "void_pact": "ailment", "bulwark": "block,defence", "vampiric": "life,sustain"}

# Hooks that exist in code today (verified 2026-11-04)
HOOKS = "on_block (player._on_block), on_dodge (player.start_dodge), on_kill (player.on_kill / Events.enemy_killed), on_hit conditional (Combat._conditional), stationary timer (fortress), status presence checks"

OVR = {
 # keystones
 "ks_momentum": ("Keep", "Rework drawback", "Drawback (10% less on first hit) is near-free once stacks build. Add a real cost, e.g. stacks decay fast or -X% attack speed."),
 "xa_ks": ("Keep", "Rework drawback", "Mind over Matter has NO drawback (pure upside: +25% mana, 30% damage to mana). Needs a cost, e.g. -20% mana regen or no life leech."),
 "xp_ks": ("Convert", "Rule-changing keystone", "Prismatic Soul is stats only (no flag). Give it a rule, e.g. resist caps +5% but you cannot be ignited/chilled/shocked AND cannot inflict them."),
 "ks_glass": ("Keep", "Reviewed", "Stat keystone but a clear, real trade (40% more dmg / 40% less life). Acceptable as the generic all-in pick."),
 "ks_one_mind": ("Keep", "Reviewed", "Overlaps Legion of Bone proposal; make them exclusive_with if both ship."),
 "ks_automaton": ("Keep", "Reviewed", "Directly opposite Clockwork Mind proposal (-1 vs +2 turrets). Keep as the 'few strong turrets' pole; mark exclusive_with."),
 # flagged non-keystones
 "w_bulwark": ("Keep", "Already behavioural", "Has 'bulwark' flag (on-block buff). Natural place to hang Iron Riposte (block counterattack) next door."),
 "xs_r0": ("Keep", "Already behavioural", "Has 'vampiric' flag (2% leech)."),
 # hand cluster ends -> behaviour notables (Phase 2 candidates)
 "w_brutal": ("Convert", "Behaviour notable", "Weapon Master end. Candidate: Opened Veins-style bleed payoff, or 'kills with melee reset the shortest cooldown' [F on_kill]."),
 "r_deadeye": ("Convert", "Behaviour notable", "Marksman end. Candidate: Marked for Death (crits vs Marked chain once) [F chain]."),
 "r_engineer": ("Convert", "Behaviour notable", "Engineer end. Candidate: Volatile Mechanisms (deployables explode on expiry/death) [F aoe]. Keep +1 turret limit as a stat."),
 "r_crit2": ("Convert", "Behaviour notable", "Shadow end (only 3-node cluster). Candidate: Shadowstep (dodge leaves a chilling frost nova) [F on_dodge]."),
 "m_flame": ("Convert", "Behaviour notable", "Elementalist end. Candidate: ignite spreads to nearby enemies on kill [F on_kill]."),
 "m_command": ("Convert", "Behaviour notable", "Necromancy end. Candidate: minions inherit your crit chance [F packet copy], or summons explode on death."),
 "m_flow": ("Convert", "Behaviour notable", "Arcane Flow end. Candidate: Rift Step (blink leaves a 3s damaging zone) [F zone behaviour]."),
 "w_life3": ("Convert", "Behaviour notable", "Vitality end. Candidate: Rallying Cry (killing a stunned enemy refreshes your shortest-cooldown buff) [F on_kill], or a War Herald entry."),
 "c_dot2": ("Convert", "Behaviour notable", "Heart DoT end. Candidate: Frailty Bloom (cursed/afflicted enemies that die spread Frailty) [F on_kill]."),
 # bridge roads -> hybrid notables (already exist as 5-6 node roads!)
 "h_wr3": ("Convert", "Bridge notable", "W-R road centre. Candidate: Hunter-Knight (leap/slam marks enemies; marked take more projectile dmg)."),
 "h_rm3": ("Convert", "Bridge notable", "R-M road centre. Candidate: Hexshot (first projectile hit applies your last curse)."),
 "h_mw3": ("Convert", "Bridge notable", "M-W road centre. Candidate: Spellblade (melee hits trigger last-cast nova at 30%). Already named Spellblade."),
 # weak numeric notables
 "w_2h": ("Keep", "Buff or merge", "Heavy Grip (+10% 2H) is weaker than many minors. Buff in Phase 3 or swap to a 2H conditional."),
 "w_blk1": ("Keep", "Buff or merge", "Shield Discipline (+3% block) is minor-sized. Buff in Phase 3."),
 "m_ele": ("Keep", "Buff or merge", "Elemental Attunement (+10% elemental) is minor-sized. Buff in Phase 3."),
}

def mods_text(n):
    out = []
    for m in n["mods"]:
        v = m["value"]
        if m["type"] == "flat": out.append(f"+{v} {m['stat']}")
        elif m["type"] == "inc": out.append(f"{v:+}% inc {m['stat']}")
        else: out.append(f"{v:+}% MORE {m['stat']}")
    return "; ".join(out)

def tags(n):
    s = set()
    for m in n["mods"]:
        s.update(TAGS.get(m["stat"], m["stat"]).split(","))
    for f in n.get("flags", []):
        s.update(FLAG_TAGS.get(f, f).split(","))
    return ",".join(sorted(s))

def bfs(start):
    d = {start: 0}; q = [start]
    for u in q:
        for v in N[u]["links"]:
            if v not in d: d[v] = d[u] + N[v]["cost"]; q.append(v)
    return d

dist = {c: bfs(f"{c[0]}_start") for c in ("warrior", "ranger", "mage")}

def sector(nid):
    ds = {c: dist[c].get(nid, 999) for c in dist}
    best = min(ds.values())
    near = [c for c, v in ds.items() if v - best <= 1]
    return "/".join(near) if len(near) < 3 else "shared"

rows = []
for n in T:
    nid, typ = n["id"], n["type"]
    gen = bool(n.get("gen"))
    flags = ",".join(n.get("flags", []))
    v, cat, why = "Keep", "", ""
    if nid in OVR:
        v, cat, why = OVR[nid]
    elif typ == "start":
        cat, why = "Start", "Class start."
    elif typ == "keystone":
        cat, why = "Reviewed", "Has a flag and a real drawback."
    elif n["cluster"] == "Wanderer's Road":
        i = int(nid.split("_")[1])
        if i in (2, 4):
            v, cat, why = "Cut", "Merge travel", "6-node +4 attribute chain -> 4 nodes of +6. Merge into neighbour; refund via migration."
        else:
            v, cat, why = "Keep", "Buff travel", "Survives the merge; raise to +6 attribute (and consider dual-attribute)."
    elif gen and nid.endswith("_r0"):
        v, cat, why = "Convert", "Conditional notable", "Generated cluster notable next to the keystone. Replace stat blob with a 'while X / on Y / against Z' notable for the archetype."
    elif gen and "_p" in nid and len([k for k in N if k.startswith(nid[:len(nid)-1])]) >= 4:
        if nid.endswith("3") or nid.endswith("4"):
            v, cat, why = "Cut", "Shorten path", "4-node approach path; shorten to 2-3 nodes (generator recomputes positions)."
        else:
            cat, why = "Travel", "Approach path."
    elif typ == "minor":
        cat, why = "Travel/stat", "Filler that leads somewhere; tag it."
    else:
        cat, why = "Numeric", "Numeric greater/notable; fine as a stepping stone. Revisit in Phase 3."
    deg = len(n["links"])
    rows.append({
        "id": nid, "name": n["name"], "type": typ, "cluster": n["cluster"], "sector": sector(nid),
        "generated": "yes" if gen else "", "cost": n["cost"], "links": deg,
        "dist_W": dist["warrior"].get(nid, ""), "dist_R": dist["ranger"].get(nid, ""), "dist_M": dist["mage"].get(nid, ""),
        "mods": mods_text(n), "flags": flags, "desc": n.get("desc", ""),
        "behaviour_now": "yes" if flags else "", "proposed_tags": tags(n),
        "verdict": v, "category": cat, "notes": why, "your_call": "",
    })

out = os.path.join(ROOT, "docs", "passive_tree_audit_phase0")
with open(out + ".csv", "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
c = collections.Counter(r["verdict"] for r in rows)
print("verdicts", dict(c), "total", len(rows))
print("behaviour now", sum(1 for r in rows if r["behaviour_now"]))
for cl in ("warrior","ranger","mage"):
    ks = sorted((dist[cl][n["id"]], n["id"]) for n in T if n["type"]=="keystone")
    print(cl, "keystone costs", ks)
json.dump(rows, open(out + ".json", "w"), indent=1)
