from pathlib import Path
import json, re, uuid, collections

OUT = Path(__file__).resolve().parent
ROOT = OUT.parent
ROOT_UUID = '842367cd-ab44-5340-8309-25462fd8a06b'
parts, libs, placements, terminals, routes, junctions = [], [], [], {}, [], set()
pin_nets={}

def uid(): return str(uuid.uuid4())
def q(s): return json.dumps(str(s), ensure_ascii=False)
def n(v): return f'{v:g}'
def effects(size=1.4, justify=''):
    return f'(effects (font (size {n(size)} {n(size)}))'+(f' (justify {justify})' if justify else '')+')'
def text(s,x,y,size=1.4,angle=0,justify='left'):
    parts.append(f'(text {q(s)} (at {n(x)} {n(y)} {angle}) {effects(size,justify)} (uuid {q(uid())}))')
def rect(x1,y1,x2,y2,dash=False):
    parts.append(f'(rectangle (start {n(x1)} {n(y1)}) (end {n(x2)} {n(y2)}) (stroke (width 0.3) (type {"dash" if dash else "default"})) (fill (type none)) (uuid {q(uid())}))')
def label(s,x,y,angle=0,size=1.25):
    parts.append(f'(label {q(s)} (at {n(x)} {n(y)} {angle}) {effects(size,"left bottom")} (uuid {q(uid())}))')
def wire(net,*pts):
    clean=[]
    for p in pts:
        p=tuple(p)
        if not clean or clean[-1]!=p: clean.append(p)
    for a,b in zip(clean,clean[1:]):
        assert a[0]==b[0] or a[1]==b[1], (net,a,b)
        parts.append(f'(wire (pts (xy {n(a[0])} {n(a[1])}) (xy {n(b[0])} {n(b[1])})) (stroke (width 0.18) (type default)) (uuid {q(uid())}))')
        routes.append((net,a,b))
def junction(x,y): junctions.add((x,y))
def terminal(key,net,x,y,shape='input',angle=180):
    terminals[key]=(net,(x,y))
    parts.append(f'(hierarchical_label {q(net)} (shape {shape}) (at {n(x)} {n(y)} {angle}) {effects(1.9,"right" if angle==180 else "left")} (uuid {q(uid())}))')
def block(key,title,instance,ref,box,pins,glue=False,notes=()):
    x1,y1,x2,y2=box; cx=(x1+x2)/2; cy=(y1+y2)/2
    lname='TopDiagram:'+key
    def local(x,y): return n(x-cx),n(cy-y)
    sx1,sy1=local(x1,y1); sx2,sy2=local(x2,y2)
    body=[f'(rectangle (start {sx1} {sy1}) (end {sx2} {sy2}) (stroke (width 0.35) (type {"dash" if glue else "default"})) (fill (type background)))']
    pdef=[]
    for idx,(pname,net,side,x,y,direction) in enumerate(pins,1):
        terminals[key+'.'+pname]=(net,(x,y))
        pin_nets[ref+'.'+str(idx)]=net
        lx,ly=local(x,y); ang={'L':0,'R':180,'T':270,'B':90}[side]
        pdef.append(f'(pin {direction} line (at {lx} {ly} {ang}) (length 0) (name {q(pname)} {effects(1.35)}) (number {q(idx)} {effects(1)}))')
        if not glue:
            if side=='L': tx,ty,ta,j=x+2.5,y,0,'left'
            elif side=='R': tx,ty,ta,j=x-2.5,y,0,'right'
            elif side=='T': tx,ty,ta,j=x,y+3,90,'right'
            else: tx,ty,ta,j=x,y-3,90,'left'
            lx2,ly2=local(tx,ty)
            body.append(f'(text {q(pname)} (at {lx2} {ly2} {ta}) {effects(1.35,j)})')
    libs.append(f'''(symbol {q(lname)} (pin_names (offset 0) hide) (pin_numbers hide)
      (in_bom no) (on_board no)
      (property "Reference" {q(ref)} (at 0 0 0) {effects(1)[:-1]} (hide yes)))
      (property "Value" {q(key)} (at 0 0 0) {effects(1)[:-1]} (hide yes)))
      (symbol {q(key+'_0_1')} {' '.join(body)})
      (symbol {q(key+'_1_1')} {' '.join(pdef)}))''')
    suid=uid()
    placements.append(f'''(symbol (lib_id {q(lname)}) (at {n(cx)} {n(cy)} 0) (unit 1)
      (in_bom no) (on_board no) (dnp no) (uuid {q(suid)})
      (property "Reference" {q(ref)} (at {n(cx)} {n(cy)} 0) {effects(1)[:-1]} (hide yes)))
      (property "Value" {q(key)} (at {n(cx)} {n(cy)} 0) {effects(1)[:-1]} (hide yes)))
      (instances (project "sensor_network_master" (path {q('/'+ROOT_UUID)} (reference {q(ref)}) (unit 1)))))''')
    text(title,cx,y1-5,2.3,justify='')
    instance_y={'uart_controller_master':220,'sensor_request_master':97,'oled_sensor_display':346}.get(key,y2-5)
    if instance: text(instance,cx,instance_y,1.6,justify='')
    for s,x,y,size in notes: text(s,x,y,size,justify='')

text('sensor_network_master',297,17,5,justify='')
text('TOP BLOCK DIAGRAM  |  Direct child modules and connected RTL signals',297,27,1.7,justify='')
rect(43,36,535,397)

block('request_button','request_button','button','U1',(100,85,185,130),[
 ('clk','clk','L',100,95,'input'),('reset','reset','L',100,102,'input'),
 ('button','btnC','L',100,115,'input'),('pressed','button_request','R',185,110,'output')])
block('uart_controller_master','uart_controller_master','u_uart_controller_master','U2',(100,150,205,248),[
 ('clk','clk','L',100,160,'input'),('reset','reset','L',100,173,'input'),('rx','RsRx','L',100,190,'input'),
 ('request','uart_request','R',205,160,'output'),('request_mask[2:0]','uart_request_mask[2:0]','R',205,175,'output'),
 ('request_mode[1:0]','uart_request_mode[1:0]','R',205,190,'output'),
 ('mode_in[1:0]','sw_sync[1:0]','R',205,205,'input'),('tx','RsTx','R',205,220,'output'),
 ('master_busy','uart_blocked','R',205,235,'input'),
 ('reply_overflow','uart_reply_overflow','B',160,248,'output')])
block('Top_control','Top RTL logic','assign / always','G1',(260,85,345,248),[
 ('clk','clk','T',285,85,'input'),('reset','reset','T',320,85,'output'),
 ('button_request','button_request','L',260,110,'input'),
 ('uart_request','uart_request','L',260,160,'input'),
 ('uart_request_mask[2:0]','uart_request_mask[2:0]','L',260,175,'input'),
 ('uart_request_mode[1:0]','uart_request_mode[1:0]','L',260,190,'input'),
 ('mode_in[1:0]','sw_sync[1:0]','L',260,205,'output'),
 ('sw[15:0]','sw[15:0]','L',260,220,'input'),('uart_blocked','uart_blocked','L',260,235,'output'),
 ('request','request','R',345,110,'output'),('mode[1:0]','selected_request_mode[1:0]','R',345,125,'output'),
 ('request_mask[2:0]','selected_request_mask[2:0]','R',345,140,'output'),('busy','request_busy','R',345,235,'input')],True,
 [('reset / switch sync',302.5,157,1.45),('request arbitration',302.5,174,1.45),('mode / mask mux',302.5,191,1.45),('UART priority',302.5,213,1.5)])
block('sensor_request_master','sensor_request_master','acquisition','U3',(405,85,505,248),[
 ('clk','clk','T',420,85,'input'),('reset','reset','T',437,85,'input'),
 ('request','request','L',405,110,'input'),('mode[1:0]','selected_request_mode[1:0]','L',405,125,'input'),
 ('request_mask[2:0]','selected_request_mask[2:0]','L',405,140,'input'),('spi_miso','spi_miso','L',405,155,'input'),
 ('error_code[2:0]','error_code[2:0]','L',405,200,'output'),('busy','request_busy','L',405,235,'output'),
 ('spi_sclk','spi_sclk','R',505,105,'output'),('spi_mosi','spi_mosi','R',505,120,'output'),
 ('spi_cs_n','spi_cs_n','R',505,135,'output'),('board_sda','board_sda','R',505,150,'bidirectional'),
 ('board_scl','board_scl','R',505,165,'bidirectional'),
 ('temperature[7:0]','temperature[7:0]','B',415,248,'output'),('humidity[7:0]','humidity[7:0]','B',435,248,'output'),
 ('distance[8:0]','distance[8:0]','B',455,248,'output'),('valid_mask[2:0]','valid_mask[2:0]','B',475,248,'output'),
 ('update','display_update','B',495,248,'output')])
block('oled_sensor_display','oled_sensor_display','display','U4',(395,310,505,370),[
 ('clk','clk','L',395,340,'input'),('reset','reset','L',395,352,'input'),
 ('temperature[7:0]','temperature[7:0]','T',415,310,'input'),('humidity[7:0]','humidity[7:0]','T',435,310,'input'),
 ('distance[8:0]','distance[8:0]','T',455,310,'input'),('valid_mask[2:0]','valid_mask[2:0]','T',475,310,'input'),
 ('update','display_update','T',495,310,'input'),
 ('oled_sda','oled_sda','R',505,335,'bidirectional'),('oled_scl','oled_scl','R',505,350,'bidirectional'),
 ('ready','oled_ready','B',415,370,'output'),('error','oled_error','B',435,370,'output'),
 ('nack_seen','oled_nack','B',455,370,'output'),('timeout_seen','oled_timeout','B',475,370,'output')])
block('Top_LED','Top LED assignment','assign led[15:0]','G2',(260,315,345,370),[
 ('valid_mask[2:0]','valid_mask[2:0]','T',340,315,'input'),
 ('error_code[2:0]','error_code[2:0]','T',320,315,'input'),('request_busy','request_busy','T',300,315,'input'),
 ('ready','oled_ready','R',345,325,'input'),('error','oled_error','R',345,337,'input'),
 ('nack','oled_nack','R',345,349,'input'),('timeout','oled_timeout','R',345,361,'input'),
 ('led[15:0]','led[15:0]','L',260,355,'output')],True,
 [('status + error decode',302,344,1.45)])

# Top input and output ports.
for key,net,x,y,shape,ang in [
 ('top.clk','clk',27,45,'input',180),('top.btnC','btnC',27,115,'input',180),
 ('top.RsRx','RsRx',27,190,'input',180),('top.spi_miso','spi_miso',27,265,'input',180),
 ('top.sw','sw[15:0]',27,280,'input',180),
 ('top.spi_sclk','spi_sclk',555,105,'output',0),('top.spi_mosi','spi_mosi',555,120,'output',0),
 ('top.spi_cs_n','spi_cs_n',555,135,'output',0),('top.board_sda','board_sda',555,150,'bidirectional',0),
 ('top.board_scl','board_scl',555,165,'bidirectional',0),('top.RsTx','RsTx',555,205,'output',0),
 ('top.tx_debug','RsTx',555,220,'output',0),('top.oled_sda','oled_sda',555,335,'bidirectional',0),
 ('top.oled_scl','oled_scl',555,350,'bidirectional',0),('top.rx_debug','RsRx',555,395,'output',0),
 ('top.led','led[15:0]',555,405,'output',0)]:
    terminal(key,net,x,y,shape,ang)
# Actual external port names for debug aliases; they share the corresponding data net.
for i,p in enumerate(parts):
    if p.startswith('(hierarchical_label "RsTx"') and '(at 555 220 ' in p: parts[i]=p.replace('"RsTx"','"tx_debug"',1)
    if p.startswith('(hierarchical_label "RsRx"') and '(at 555 395 ' in p: parts[i]=p.replace('"RsRx"','"rx_debug"',1)

# Clock and reset rails. Junction dots identify every intended branch.
wire('clk',(27,45),(60,45),(285,45),(380,45),(420,45))
wire('clk',(60,45),(60,95),(60,160))
wire('clk',(60,95),(100,95)); wire('clk',(60,160),(100,160))
wire('clk',(285,45),(285,85)); wire('clk',(420,45),(420,85))
wire('clk',(380,45),(380,340),(395,340))
for p in [(60,45),(285,45),(380,45),(60,95)]: junction(*p)
label('clk',75,45); label('clk',380,333,90)
wire('reset',(320,85),(320,60),(70,60),(70,102),(70,173))
wire('reset',(320,60),(385,60),(437,60),(437,85))
wire('reset',(70,102),(100,102)); wire('reset',(70,173),(100,173))
wire('reset',(385,60),(385,352),(395,352))
for p in [(320,60),(385,60),(70,102)]: junction(*p)
label('reset',80,60); label('reset',385,345,90)

wire('btnC',(27,115),(100,115))
wire('button_request',(185,110),(260,110)); label('button_request',190,110)
for net,y in [('uart_request',160),('uart_request_mask[2:0]',175),('uart_request_mode[1:0]',190),('sw_sync[1:0]',205),('uart_blocked',235)]:
    wire(net,(205,y),(260,y));label(net,208,y,size=1.1)
for net,y in [('request',110),('selected_request_mode[1:0]',125),('selected_request_mask[2:0]',140)]:
    wire(net,(345,y),(405,y));label(net,347,y,size=1.05)
wire('sw[15:0]',(27,280),(235,280),(235,220),(260,220));label('sw[15:0]',110,280)
wire('spi_miso',(27,265),(390,265),(390,155),(405,155));label('spi_miso',285,265)
wire('RsRx',(27,190),(85,190),(100,190))
wire('RsRx',(85,190),(85,395),(555,395));junction(85,190); label('RsRx',105,395)
wire('RsTx',(205,220),(218,220),(218,290),(545,290),(545,220),(545,205),(555,205))
wire('RsTx',(545,220),(555,220));junction(545,220);label('RsTx',510,290)
wire('uart_reply_overflow',(160,248),(160,257));label('uart_reply_overflow',160,255,90,size=1.1)
text('unused',164,257,1.1)
parts.append(f'(no_connect (at 160 257) (uuid {q(uid())}))')
for net,y in [('spi_sclk',105),('spi_mosi',120),('spi_cs_n',135),('board_sda',150),('board_scl',165),('oled_sda',335),('oled_scl',350)]:
    wire(net,(505,y),(555,y))
for net,x in [('temperature[7:0]',415),('humidity[7:0]',435),('distance[8:0]',455),('valid_mask[2:0]',475),('display_update',495)]:
    if net=='valid_mask[2:0]':
        wire(net,(x,248),(x,278),(x,310));junction(x,278)
    else: wire(net,(x,248),(x,310))
    label(net,x,300,90,size=1.3)
wire('valid_mask[2:0]',(475,278),(340,278),(340,315))
wire('request_busy',(405,235),(370,235),(345,235));junction(370,235);label('request_busy',347,235,size=1.1)
wire('request_busy',(370,235),(370,295),(300,295),(300,315));label('request_busy',300,313,90,size=1.1)
wire('error_code[2:0]',(405,200),(375,200),(375,285),(320,285),(320,315));label('error_code[2:0]',320,313,90,size=1.1)
label('valid_mask[2:0]',340,313,90,size=1.1)
for net,x,y,lane,dy in [('oled_ready',415,325,350,377),('oled_error',435,337,355,381),('oled_nack',455,349,360,385),('oled_timeout',475,361,365,389)]:
    wire(net,(x,370),(x,dy),(lane,dy),(lane,y),(345,y))
    label(net,lane,dy,90,size=1.0)
wire('led[15:0]',(260,355),(245,355),(245,405),(555,405));label('led[15:0]',275,405)

# Parent RTL equations make mux / synchronization boundaries explicit.
text('Top logic: reset = reset_pipe[3] (sw[15]); sw_sync = two-stage synchronization of sw[4:0].',100,304,1.25)
text('request = !request_busy && (uart_request || button_request)',100,317,1.2)
text('mode / mask = uart_request ? UART values : sw_sync[1:0] / sw_sync[4:2]',100,324,1.2)
text('button_grant = !request_busy && button_request && !uart_request',100,337,1.2)
text('uart_blocked = request_busy || button_grant',100,344,1.2)
text('Solid boxes: 4 direct child modules. Dashed boxes: logic inside Top (not extra modules).',100,363,1.25)
text('Dot = joined wires. Crossing without a dot = separate signals. [msb:lsb] = RTL vector width.',100,374,1.25)
text('OLED_SELF_TEST=0. SPI and board I2C are separate from the OLED I2C bus.',100,384,1.25)

for x,y in sorted(junctions):
    parts.append(f'(junction (at {n(x)} {n(y)}) (diameter 1.1) (color 0 0 0 0) (uuid {q(uid())}))')
header=f'''(kicad_sch (version 20260306) (generator "eeschema") (generator_version "10.0")
 (uuid {q(ROOT_UUID)}) (paper "A2")
 (title_block (title "sensor_network_master - connected Top block diagram") (date "2026-11-06") (rev "2.0")
 (comment 1 "Single sheet; direct child modules; physical wire connections"))
 (lib_symbols {' '.join(libs)})'''
sch=header+'\n'+'\n'.join(parts+placements)+f'\n(sheet_instances (path "/" (page "1"))) (embedded_fonts no))\n'
(OUT/'sensor_network_master.kicad_sch').write_text(sch,encoding='utf-8')

# Verify real wire continuity and ensure two named signals never share endpoints/junctions.
def on(p,a,b):
    return (a[0]==b[0]==p[0] and min(a[1],b[1])<=p[1]<=max(a[1],b[1])) or (a[1]==b[1]==p[1] and min(a[0],b[0])<=p[0]<=max(a[0],b[0]))
points={p for _,a,b in routes for p in [a,b]}|junctions|{p for _,p in terminals.values()}
nodes=collections.defaultdict(set)
for net,a,b in routes:
    for p in points:
        if on(p,a,b): nodes[p].add(net)
conflicts={str(p):sorted(nets) for p,nets in nodes.items() if len(nets)>1}
assert not conflicts, 'Wire endpoints or junctions short distinct signals: '+str(conflicts)
for key,(net,p) in terminals.items(): assert net in nodes[p],(key,net,p)
nets=collections.defaultdict(list)
for k,(net,p) in terminals.items():nets[net].append({'terminal':k,'xy':p})
for net,ts in nets.items():
    segs=[(a,b) for name,a,b in routes if name==net]
    seen={ts[0]['xy']}; changed=True
    while changed:
        changed=False
        for a,b in segs:
            if any(on(p,a,b) for p in seen):
                for p in points:
                    if on(p,a,b) and p not in seen:seen.add(p);changed=True
    assert all(t['xy'] in seen for t in ts),(net,ts)
report={'direct_modules':4,'sheets':1,'nets':len(nets),'wire_segments':len(routes),'all_terminals_physically_connected':True,'unintended_shorts':0,'net_connections':dict(nets),'pin_nets':pin_nets}
(OUT/'connection_check.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k not in ['net_connections','pin_nets']}))
