"""Phase 2E: Trap Vault runs summary. python tests/smartbot/p2e_trap.py <tag>"""
import csv,glob,re,sys,os,collections
tag = sys.argv[1] if len(sys.argv) > 1 else "trap1"
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
VRE = re.compile(r"vaults:([^|]*)\|t=(\d+)\|sigils=(\d+)\|shards=(\d+)(\|trap_alive=(\d+))?")
agg=collections.defaultdict(lambda:[0,0,0,0,[]])
for fn in sorted(glob.glob(os.path.join(out, 'atlas_p2e_vault_*_%s_rot*.csv' % tag))):
  if 'perf' in fn: continue
  rot=fn[-5]
  for r in csv.DictReader(open(fn, encoding="utf-8")):
    m=VRE.search(r['notes']); a=agg[(r['class'],rot)]
    a[0]+=1; a[1]+= r['outcome']=='died'
    if m:
      kinds=m.group(1).split('+')
      a[2]+=sum(1 for k in kinds if k.endswith(':done')); a[3]+=sum(1 for k in kinds if not k.endswith(':sealed'))
      a[4].append(int(m.group(2)))
      if r['outcome']=='died': print('  died', r['class'],'rot',rot,r['cause_of_death'],m.group(0))
for k,v in sorted(agg.items()): print(k, 'runs',v[0],'died',v[1],'vaults done/opened',v[2],v[3],'vault_t',sorted(v[4]))
