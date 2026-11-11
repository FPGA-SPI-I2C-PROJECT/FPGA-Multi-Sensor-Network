from pathlib import Path
import collections,json,xml.etree.ElementTree as ET
p=Path(__file__).resolve().parent
r=json.loads((p/'connection_check.json').read_text())
x=ET.parse(p/'netlist.xml').getroot()
expected=collections.defaultdict(set)
for pin,net in r['pin_nets'].items():expected[net].add(pin)
actual=[]
for net in x.findall('./nets/net'):
    nodes={n.get('ref')+'.'+n.get('pin') for n in net.findall('node')}
    if nodes:actual.append(nodes)
want={frozenset(s) for s in expected.values()}
got={frozenset(s) for s in actual}
assert want==got,{'missing':list(map(sorted,want-got)),'unexpected':list(map(sorted,got-want))}
assert len(x.findall('./design/sheet'))==1
assert len(x.findall('./components/comp'))==len({pin.split('.')[0] for pin in r['pin_nets']})
print(json.dumps({'KiCad_netlist_matches_all_wires':True,'verified_pins':len(r['pin_nets']),'single_standalone_sheet':True,'direct_RTL_modules':r['direct_modules']}))
