from pathlib import Path
import collections, hashlib, json, re, uuid

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[1]
SRC=ROOT/'i2c_sensor_oled_driver.srcs/sources_1/new'
ROOT_ID='842367cd-ab44-5340-8309-25462fd8a06b'
parts=[]; libraries=[]; instances=[]; wires=[]; terms={}; pin_nets={}; module_ports={}; boxes=[]; text_boxes=[]; label_points=[]
X=lambda x:round(x*.85+12,5)
Y=lambda y:round(y*.93+1.5,5)
def u():return str(uuid.uuid4())
def q(s):return json.dumps(str(s),ensure_ascii=False)
def f(v):return f'{v:g}'
def fx(size,j=''):
    return f'(effects (font (size {f(size)} {f(size)}))'+(f' (justify {j})' if j else '')+')'
def xy(p):return f'{f(X(p[0]))} {f(Y(p[1]))}'
def text(s,x,y,size=1,angle=0,j='left'):
    parts.append(f'(text {q(s)} (at {xy((x,y))} {angle}) {fx(size,j)} (uuid {q(u())}))')
def rectangle(box):
    x1,y1,x2,y2=box
    parts.append(f'(rectangle (start {xy((x1,y1))}) (end {xy((x2,y2))}) (stroke (width 0.12) (type default)) (fill (type none)) (uuid {q(u())}))')
def line(*points,width=.11):
    parts.append(f'(polyline (pts '+ ' '.join(f'(xy {xy(p)})' for p in points)+f') (stroke (width {f(width)}) (type default)) (fill (type none)) (uuid {q(u())}))')
def circle(x,y,r=.48):
    parts.append(f'(circle (center {xy((x,y))}) (radius {f(r)}) (stroke (width 0.1) (type default)) (fill (type none)) (uuid {q(u())}))')
def label(net,x,y,angle=0,size=.95):
    label_points.append((net,(x,y)))
    parts.append(f'(label {q(net)} (at {xy((x,y))} {angle}) {fx(size,"left bottom")} (uuid {q(u())}))')
def wire(net,*points):
    for a,b in zip(points,points[1:]):
        a=tuple(a);b=tuple(b)
        if a==b:continue
        assert a[0]==b[0] or a[1]==b[1],(net,a,b)
        wires.append((net,a,b))
def port(name,net,x,y,direction):
    angle=180 if direction=='input' else 0
    parts.append(f'(hierarchical_label {q(name)} (shape {direction}) (at {xy((x,y))} {angle}) {fx(2.25,"right" if angle else "left")} (uuid {q(u())}))')
    terms['TOP.'+name]=(net,(x,y))
def component(key,ref,pins,box=None,title=None,inst=None,kind=None):
    # Embedded pin-only symbols make a single editable file; visible rectangles/text match the reference.
    if box:
        cx=(box[0]+box[2])/2;cy=(box[1]+box[3])/2
    else:
        cx=sum(p[3] for p in pins)/len(pins);cy=sum(p[4] for p in pins)/len(pins)
    l=[]
    for i,(name,net,side,x,y,direction) in enumerate(pins,1):
        lx=X(x)-X(cx);ly=Y(cy)-Y(y)
        ang={'L':0,'R':180,'T':270,'B':90}[side]
        l.append(f'(pin {direction} line (at {f(lx)} {f(ly)} {ang}) (length 0) (name {q(name)} {fx(.85)}) (number {q(i)} {fx(.75)}))')
        terms[ref+'.'+name]=(net,(x,y));pin_nets[ref+'.'+str(i)]=net
        if title:
            if side=='L':text(name,x+1.2,y-.85,.86,j='left')
            elif side=='R':text(name,x-1.2,y-.85,.86,j='right')
            elif side=='T':text(name,x,y+1.2,.86,90,j='right')
            else:text(name,x,y-1.2,.78,90,j='left')
    name='TopDiagram:'+key
    libraries.append(f'''(symbol {q(name)} (pin_names (offset 0) hide) (pin_numbers hide) (in_bom no) (on_board no)
      (property "Reference" {q(ref)} (at 0 0 0) {fx(.8)[:-1]} (hide yes)))
      (property "Value" {q(key)} (at 0 0 0) {fx(.8)[:-1]} (hide yes)))
      (symbol {q(key+'_1_1')} {' '.join(l)}))''')
    instances.append(f'''(symbol (lib_id {q(name)}) (at {f(X(cx))} {f(Y(cy))} 0) (unit 1) (in_bom no) (on_board no) (dnp no) (uuid {q(u())})
      (property "Reference" {q(ref)} (at {f(X(cx))} {f(Y(cy))} 0) {fx(.8)[:-1]} (hide yes)))
      (property "Value" {q(key)} (at {f(X(cx))} {f(Y(cy))} 0) {fx(.8)[:-1]} (hide yes)))
      (instances (project "sensor_network_master" (path {q('/'+ROOT_ID)} (reference {q(ref)}) (unit 1)))))''')
    if title:
        rectangle(box);boxes.append(box)
        text(title,cx,box[1]-4.2,1.5,j='')
        text(inst,cx,box[1]-1.9,.78,j='')
        module_ports[key]=[p[0] for p in pins]
    elif kind=='mux':
        x1,y1,x2,y2=box
        line((x1,y1),(x2,y1+1.5),(x2,y2-1.5),(x1,y2),(x1,y1))
        text('0',x1+1,y1+1.6,.7);text('1',x1+1,y2-1.6,.7)
    elif kind in ('AND','OR'):
        rectangle(box);text('&' if kind=='AND' else '≥1',cx,cy,1.1,j='')
    elif kind in ('RST','SYNC'):
        rectangle(box);text(kind,cx,cy,1.05,j='')
    elif kind=='split':
        x1,y1,x2,y2=box
        line((x1,y1),(x1,y2),width=.5)
        for _,_,side,x,y,_ in pins:
            if side=='R':line((x1,y),(x,y),width=.1)
    elif kind=='concat':
        x1,y1,x2,y2=box
        line((x1,y1),(x1,y2),width=.55)
        text('LED',cx,y1-2,.85,j='')
        for _,_,side,x,y,_ in pins:
            if side=='R':line((x1,y),(x,y),width=.15)

text('TOP_SENSOR_NETWORK_MASTER',159,24.2,5.5,j='')
rectangle((47,32,271,175))

component('btn_debouncer','U1',[
 ('clk','clk','L',72,80,'input'),('reset','reset','L',72,86,'input'),
 ('button','btnC','L',72,92,'input'),('pressed','button_request','R',95,86,'output')],
 (72,76,95,96),'btn_debouncer','u_btn_debouncer')
component('uart_controller_master','U2',[
 ('clk','clk','L',72,110,'input'),('reset','reset','L',72,116,'input'),
 ('rx','RsRx','L',72,124,'input'),('mode_in[1:0]','sw_sync[1:0]','L',72,132,'input'),
 ('request','uart_request','R',110,110,'output'),('request_mode[1:0]','uart_request_mode[1:0]','R',110,117,'output'),
 ('request_mask[2:0]','uart_request_mask[2:0]','R',110,124,'output'),('tx','RsTx','R',110,133,'output'),
 ('master_busy','uart_blocked','B',100,140,'input'),('reply_overflow','uart_reply_overflow','B',90,140,'output')],
 (72,106,110,140),'uart_controller_master','u_uart_controller_master')
component('sensor_request_master','U3',[
 ('clk','clk','L',155,80,'input'),('reset','reset','L',155,87,'input'),
 ('request','request','L',155,94,'input'),('mode[1:0]','selected_request_mode[1:0]','L',155,105,'input'),
 ('request_mask[2:0]','selected_request_mask[2:0]','L',155,115,'input'),('spi_miso','spi_miso','L',155,125,'input'),
 ('busy','request_busy','L',155,137,'output'),('error_code[2:0]','error_code[2:0]','L',155,147,'output'),
 ('temperature[7:0]','temperature[7:0]','R',193,82,'output'),('humidity[7:0]','humidity[7:0]','R',193,89,'output'),
 ('distance[8:0]','distance[8:0]','R',193,96,'output'),('valid_mask[2:0]','valid_mask[2:0]','R',193,103,'output'),
 ('update','display_update','R',193,110,'output'),('spi_sclk','spi_sclk','R',193,119,'output'),
 ('spi_mosi','spi_mosi','R',193,126,'output'),('spi_cs_n','spi_cs_n','R',193,133,'output'),
 ('board_sda','board_sda','R',193,140,'bidirectional'),('board_scl','board_scl','R',193,147,'bidirectional')],
 (155,76,193,155),'sensor_request_master','acquisition')
component('oled_sensor_display','U4',[
 ('clk','clk','L',229,78,'input'),('reset','reset','L',229,85,'input'),
 ('temperature[7:0]','temperature[7:0]','L',229,82,'input'),('humidity[7:0]','humidity[7:0]','L',229,89,'input'),
 ('distance[8:0]','distance[8:0]','L',229,96,'input'),('valid_mask[2:0]','valid_mask[2:0]','L',229,103,'input'),
 ('update','display_update','L',229,110,'input'),('oled_sda','oled_sda','R',253,82,'bidirectional'),
 ('oled_scl','oled_scl','R',253,89,'bidirectional'),('ready','oled_ready','R',253,96,'output'),
 ('error','oled_error','R',253,103,'output'),('nack_seen','oled_nack','R',253,110,'output'),
 ('timeout_seen','oled_timeout','R',253,117,'output')],
 (229,76,253,118),'oled_sensor_display','display')

# Small inline symbols stand for existing parent expressions; none are RTL child modules.
component('sw_bits','B1',[
 ('sw[15:0]','sw[15:0]','L',55,59,'input'),('sw[15]','sw[15]','R',59,57,'output'),('sw[4:0]','sw[4:0]','R',59,61,'output')],(55,57,59,61),kind='split')
component('reset_sync','L1',[
 ('clk','clk','T',83,44,'input'),('sw[15]','sw[15]','L',78,48,'input'),('reset','reset','R',88,48,'output')],(78,44,88,52),kind='RST')
component('sw_sync','L2',[
 ('clk','clk','L',78,61,'input'),('reset','reset','L',78,65,'input'),('sw[4:0]','sw[4:0]','L',78,63,'input'),('sw_sync[4:0]','sw_sync[4:0]','R',90,63,'output')],(78,59,90,67),kind='SYNC')
component('sw_sync_bits','B2',[
 ('sw_sync[4:0]','sw_sync[4:0]','L',106,63,'input'),('sw_sync[1:0]','sw_sync[1:0]','R',112,61,'output'),('sw_sync[4:2]','sw_sync[4:2]','R',112,67,'output')],(106,61,112,67),kind='split')
component('request_or','L3',[
 ('button_request','button_request','L',130,82,'input'),('uart_request','uart_request','L',130,86,'input'),('OR','button_request | uart_request','R',138,84,'output')],(130,80,138,88),kind='OR')
component('request_and','L4',[
 ('OR','button_request | uart_request','L',141,84,'input'),('not_busy','request_busy','T',143,81,'input'),('request','request','R',146,86,'output')],(141,81,146,89),kind='AND')
circle(143,80.3,.45)
component('mode_mux','M1',[
 ('0','sw_sync[1:0]','L',137,108,'input'),('1','uart_request_mode[1:0]','L',137,112,'input'),('sel','uart_request','T',141,107,'input'),('out','selected_request_mode[1:0]','R',145,110,'output')],(137,107,145,113),kind='mux')
component('mask_mux','M2',[
 ('0','sw_sync[4:2]','L',137,119,'input'),('1','uart_request_mask[2:0]','L',137,123,'input'),('sel','uart_request','T',141,118,'input'),('out','selected_request_mask[2:0]','R',145,121,'output')],(137,118,145,124),kind='mux')
component('button_grant','L5',[
 ('button_request','button_request','L',125,140,'input'),('not_busy','request_busy','L',125,142,'input'),('not_uart','uart_request','L',125,144,'input'),('grant','button_grant','R',133,143,'output')],(125,138,133,148),kind='AND')
circle(124.4,142,.42);circle(124.4,144,.42)
component('uart_busy_or','L6',[
 ('busy','request_busy','L',138,147,'input'),('grant','button_grant','L',138,149,'input'),('blocked','uart_blocked','R',144,148,'output')],(138,145,144,151),kind='OR')
component('led_concat','B3',[
 ('ready','oled_ready','L',262,96,'input'),('error','oled_error','L',262,103,'input'),
 ('nack','oled_nack','L',262,110,'input'),('timeout','oled_timeout','L',262,117,'input'),
 ('busy','request_busy','L',262,130,'input'),('error_code[2:0]','error_code[2:0]','L',262,143,'input'),
 ('valid_mask[2:0]','valid_mask[2:0]','L',262,150,'input'),('zero','0','B',262,155,'input'),
 ('led[15:0]','led[15:0]','R',266,153,'output')],(262,96,266,155),kind='concat')
text('0',262,158,.85,j='')

for name,net,x,y,d in [
 ('clk','clk',47,40,'input'),('sw[15:0]','sw[15:0]',47,59,'input'),('btnC','btnC',47,92,'input'),
 ('RsRx','RsRx',47,124,'input'),('spi_miso','spi_miso',47,151,'input'),
 ('oled_sda','oled_sda',271,82,'bidirectional'),('oled_scl','oled_scl',271,89,'bidirectional'),
 ('spi_sclk','spi_sclk',271,119,'output'),('spi_mosi','spi_mosi',271,126,'output'),
 ('spi_cs_n','spi_cs_n',271,133,'output'),('board_sda','board_sda',271,140,'bidirectional'),
 ('board_scl','board_scl',271,147,'bidirectional'),('led[15:0]','led[15:0]',271,153,'output'),
 ('RsTx','RsTx',271,160,'output'),('tx_debug','RsTx',271,166,'output'),('rx_debug','RsRx',271,172,'output')]:port(name,net,x,y,d)

# Common rails and source conditioning.
wire('clk',(47,40),(57,40),(64,40),(83,40),(149,40),(223,40),(253,40))
wire('clk',(57,40),(57,80),(57,110));wire('clk',(57,80),(72,80));wire('clk',(57,110),(72,110))
wire('clk',(64,40),(64,61),(78,61));wire('clk',(83,40),(83,44))
wire('clk',(149,40),(149,80),(155,80));wire('clk',(223,40),(223,78),(229,78));label('clk',245,40)
wire('reset',(88,48),(91,48),(91,54),(68,54),(62,54),(62,86),(62,116))
wire('reset',(62,86),(72,86));wire('reset',(62,116),(72,116))
wire('reset',(68,54),(68,65),(78,65));wire('reset',(91,54),(147,54),(225,54),(253,54))
wire('reset',(147,54),(147,87),(155,87));wire('reset',(225,54),(225,85),(229,85));label('reset',245,54)
wire('sw[15:0]',(47,59),(55,59))
wire('sw[15]',(59,57),(60.5,57),(60.5,48),(78,48));label('sw[15]',65,48,size=.8)
wire('sw[4:0]',(59,61),(60,61),(60,63),(78,63));label('sw[4:0]',69,63,size=.75)
wire('sw_sync[4:0]',(90,63),(106,63));label('sw_sync[4:0]',92,63,size=.85)
wire('sw_sync[1:0]',(112,61),(118,61),(122,61),(122,108),(137,108));label('sw_sync[1:0]',125,108,size=.75)
wire('sw_sync[1:0]',(118,61),(118,70),(66,70),(66,132),(72,132))
wire('sw_sync[4:2]',(112,67),(124,67),(124,119),(137,119));label('sw_sync[4:2]',125,119,size=.75)

# Control paths: request OR/AND and independent mode/mask multiplexers.
wire('btnC',(47,92),(72,92))
wire('button_request',(95,86),(116,86),(127,86),(127,82),(130,82));label('button_request',97,86,size=.95)
wire('button_request',(116,86),(116,140),(125,140))
wire('uart_request',(110,110),(119,110),(119,98),(129,98),(129,86),(130,86));label('uart_request',120,98,size=.8)
wire('uart_request',(119,110),(119,144),(125,144))
wire('uart_request',(119,110),(120,110),(120,100),(141,100),(141,107))
wire('uart_request',(141,100),(146,100),(146,117),(141,117),(141,118))
wire('button_request | uart_request',(138,84),(141,84))
wire('request',(146,86),(154,86),(154,94),(155,94));label('request',149,86,size=.75)
wire('uart_request_mode[1:0]',(110,117),(130,117),(130,112),(137,112));label('uart_request_mode[1:0]',111,117,size=.68)
wire('uart_request_mask[2:0]',(110,124),(131,124),(131,123),(137,123));label('uart_request_mask[2:0]',111,124,size=.68)
wire('selected_request_mode[1:0]',(145,110),(148,110),(148,105),(155,105))
wire('selected_request_mask[2:0]',(145,121),(150,121),(150,115),(155,115))
label('selected_request_mode[1:0]',148,110,90,size=.65)
label('selected_request_mask[2:0]',150,121,90,size=.65)
wire('request_busy',(155,137),(151,137),(151,78),(143,78),(143,81))
wire('request_busy',(151,137),(151,150),(136,150),(136,147),(138,147))
wire('request_busy',(151,150),(121,150),(121,142),(125,142))
wire('button_grant',(133,143),(134,143),(134,149),(138,149))
wire('uart_blocked',(144,148),(148,148),(148,153),(100,153),(100,140));label('uart_blocked',102,153,size=.9)

# All five sensor data/control lines go straight from acquisition to display.
for net,y in [('temperature[7:0]',82),('humidity[7:0]',89),('distance[8:0]',96),('valid_mask[2:0]',103),('display_update',110)]:
    if net=='valid_mask[2:0]':wire(net,(193,y),(219,y),(229,y))
    else:wire(net,(193,y),(229,y))
    label(net,197,y,size=1)

# External interfaces. Board and OLED I2C remain separate nets.
wire('spi_miso',(47,151),(112,151),(112,155),(152,155),(152,125),(155,125));label('spi_miso',75,151,size=.9)
wire('RsRx',(47,124),(64,124),(72,124))
wire('RsRx',(64,124),(64,172),(271,172));label('RsRx',205,172,size=.85)
wire('RsTx',(110,133),(114,133),(114,160),(267,160),(271,160));label('RsTx',205,160,size=.85)
wire('RsTx',(267,160),(267,166),(271,166))
wire('uart_reply_overflow',(90,140),(90,144))
parts.append(f'(no_connect (at {xy((90,144))}) (uuid {q(u())}))')
for net,y in [('spi_sclk',119),('spi_mosi',126),('spi_cs_n',133),('board_sda',140),('board_scl',147)]:wire(net,(193,y),(271,y))
wire('oled_sda',(253,82),(271,82));wire('oled_scl',(253,89),(271,89))

# Compact bit-assembly strip for the existing Top LED assignment.
for net,y in [('oled_ready',96),('oled_error',103),('oled_nack',110),('oled_timeout',117)]:
    wire(net,(253,y),(262,y));label(net,253.4,y,size=.65)
wire('request_busy',(151,150),(154,150),(154,156),(258,156),(258,130),(262,130));label('request_busy',211,156,size=.8)
wire('error_code[2:0]',(155,147),(153,147),(153,158),(256,158),(256,143),(262,143));label('error_code[2:0]',228,158,size=.8)
wire('valid_mask[2:0]',(219,103),(219,154),(260,154),(260,150),(262,150))
wire('led[15:0]',(266,153),(271,153))
# The constant pin is represented by the standard inline constant stub.
wire('0',(262,155),(262,156));terms['CONST0']=('0',(262,156))

def on(p,a,b):
    return (a[0]==b[0]==p[0] and min(a[1],b[1])<=p[1]<=max(a[1],b[1])) or (a[1]==b[1]==p[1] and min(a[0],b[0])<=p[0]<=max(a[0],b[0]))
points={p for _,a,b in wires for p in [a,b]}|{p for _,p in terms.values()}|{p for _,p in label_points}
at=collections.defaultdict(set)
for net,a,b in wires:
    for p in points:
        if on(p,a,b):at[p].add(net)
conflicts={str(p):sorted(v) for p,v in at.items() if len(v)>1}
assert not conflicts,'Unintended joined endpoints: '+str(conflicts)
for name,(net,p) in terms.items():assert net in at[p],('unwired',name,net,p)
for net,p in label_points:assert net in at[p],('floating label',net,p)
for net,a,b in wires:
    for x1,y1,x2,y2 in boxes:
        traverses=(a[0]==b[0] and x1<a[0]<x2 and max(min(a[1],b[1]),y1)<min(max(a[1],b[1]),y2)) or (a[1]==b[1] and y1<a[1]<y2 and max(min(a[0],b[0]),x1)<min(max(a[0],b[0]),x2))
        assert not traverses,('wire crosses module interior',net,a,b,(x1,y1,x2,y2))

# Split each wire at its genuine same-net branch points; never join mere crossings.
segments=set()
for net,a,b in wires:
    ps=[p for p in points if on(p,a,b)]
    ps.sort(key=lambda p:(p[0],p[1]))
    for pa,pb in zip(ps,ps[1:]):segments.add((net,pa,pb))
adj=collections.defaultdict(set)
for net,a,b in sorted(segments):
    parts.append(f'(wire (pts (xy {xy(a)}) (xy {xy(b)})) (stroke (width 0) (type default)) (uuid {q(u())}))')
    adj[(net,a)].add(b);adj[(net,b)].add(a)
for (net,p),neighbors in adj.items():
    if len(neighbors)>2:parts.append(f'(junction (at {xy(p)}) (diameter .65) (color 0 0 0 0) (uuid {q(u())}))')
for net in set(pin_nets.values()):
    endpoints=[p for n,p in terms.values() if n==net]
    seen={endpoints[0]};todo=list(seen)
    while todo:
        for nb in adj[(net,todo.pop())]-seen:seen.add(nb);todo.append(nb)
    assert set(endpoints)<=seen,('disconnected',net,set(endpoints)-seen)

# Validate all module port names against the latest Top instance connections.
top=(SRC/'sensor_network_master.v').read_text(encoding='utf-8')
source_hash=hashlib.sha256(top.encode()).hexdigest()
for module,inst in [('btn_debouncer','u_btn_debouncer'),('uart_controller_master','u_uart_controller_master'),('sensor_request_master','acquisition'),('oled_sensor_display','display')]:
    match=re.search(r'\b'+inst+r'\s*\((.*?)\);',top,re.S)
    assert match,inst
    actual=set(re.findall(r'\.(\w+)\s*\(',match.group(1)))
    assert actual=={re.sub(r'\[.*?\]','',s) for s in module_ports[module]},(module,actual,module_ports[module])
    ref={'btn_debouncer':'U1','uart_controller_master':'U2','sensor_request_master':'U3','oled_sensor_display':'U4'}[module]
    connections=dict(re.findall(r'\.(\w+)\s*\(([^()]*)\)',match.group(1)))
    for pname in module_ports[module]:
        pname_base=re.sub(r'\[.*?\]','',pname)
        expression=connections[pname_base].strip()
        if '?' in expression:expression=expression.rsplit(':',1)[-1].strip()
        drawn=terms[ref+'.'+pname][0]
        assert re.sub(r'\[.*?\]','',drawn)==re.sub(r'\[.*?\]','',expression),(module,pname,drawn,expression)

header=f'''(kicad_sch (version 20260306) (generator "eeschema") (generator_version "10.0")
 (uuid {q(ROOT_ID)}) (paper "A4")
 (title_block (title "sensor_network_master") (date "2026-11-06") (rev "3.0"))
 (lib_symbols {' '.join(libraries)}))'''
header=header[:-1]
sch=header+'\n'+'\n'.join(parts+instances)+'\n(sheet_instances (path "/" (page "1"))) (embedded_fonts no))\n'
(OUT/'sensor_network_master.kicad_sch').write_text(sch,encoding='utf-8')
report={'direct_modules':list(module_ports),'pin_nets':pin_nets,'all_wires_physically_connected':True,'unintended_shorts':0,'wire_segments':len(segments),'module_ports_match_Top':True,'source_sha256':source_hash}
(OUT/'connection_check.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='pin_nets'}))
