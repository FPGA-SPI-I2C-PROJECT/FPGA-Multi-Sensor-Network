from pathlib import Path
import collections,json,xml.etree.ElementTree as ET,re
p=Path(__file__).resolve().parent
r=json.loads((p/'connection_check.json').read_text())
x=ET.parse(p/'top_netlist.xml').getroot()
expected=collections.defaultdict(set)
for pin,net in r['pin_nets'].items():expected[net].add(pin)
actual=[]
for net in x.findall('./nets/net'):
    nodes={n.get('ref')+'.'+n.get('pin') for n in net.findall('node')}
    if nodes: actual.append(nodes)
assert {frozenset(s) for s in actual}=={frozenset(s) for s in expected.values()},'KiCad netlist differs from expected RTL wiring'
assert len(x.findall('./design/sheet'))==1
for ref,module in [('U1','request_button'),('U2','uart_controller_master'),('U3','sensor_request_master'),('U4','oled_sensor_display')]:
    source=(p.parent/'i2c_sensor_oled_driver.srcs/sources_1/new'/f'{module}.v').read_text(encoding='utf-8')
    header=source[:source.index(');')]
    # All RTL port names, ignoring width annotations and diagram-only pin suffixes.
    expected_ports=[]
    chunks=re.split(r'\b(?:input|output|inout)\b',header)[1:]
    for c in chunks:
        c=re.sub(r'//[^\n]*','',c)
        c=re.sub(r'\[[^\]]*\]','',c)
        c=re.sub(r'\b(?:wire|reg|signed|logic)\b','',c)
        expected_ports+=re.findall(r'\b[A-Za-z_]\w*\b',c)
    symbol_ports=[re.sub(r'_\d+$','',n.get('pinfunction')).split('[')[0] for n in x.findall('./nets/net/node') if n.get('ref')==ref]
    assert set(symbol_ports)==set(expected_ports),(module,symbol_ports,expected_ports)
print(json.dumps({'KiCad_export_matches_wiring':True,'module_port_sets_match_RTL':4,'verified_symbol_pins':len(r['pin_nets']),'single_sheet':True}))
