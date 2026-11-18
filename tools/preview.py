# Faithful port of the Monkey C onUpdate() drawing code to PIL, for preview only.
import math
from PIL import Image, ImageDraw, ImageFont

W=H=176
SUB=(113,1,62,62)                      # Instinct sub-window bounding box
FB="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FR="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
F={"XTINY":ImageFont.truetype(FB,11),"SMALL":ImageFont.truetype(FB,16),
   "MEDIUM":ImageFont.truetype(FB,20),"LARGE":ImageFont.truetype(FB,30)}
WHITE,BLACK=1,0

# ---- sample data in the same format the HA template returns ----
RAW="""H|45.0|-100.0
L|p|Alex Example|45.50916|-100.65119|not_home|0
L|p|Sam Example|44.99463|-100.00624|Work|0
L|p|Jordan Example|44.99985|-99.99973|home|0
C|climate.living_room|Living Room|heat|18.8|17.5|10.0|28.0|0.5|idle|off,heat
O|14
U|Remote UI
U|Water flow rate
U|Gas flow rate
U|Garage Speaker
U|Back Door Camera
B|Jordan's Phone|3"""
home=None; locs=[]; clim=[]; off=[]; batt=[]; offc=0
for line in RAW.split("\n"):
    f=line.split("|")
    if f[0]=="H": home=(float(f[1]),float(f[2]))
    if f[0]=="L": locs.append(dict(type=f[1],name=f[2],lat=float(f[3]),lon=float(f[4]),state=f[5]))
    if f[0]=="C": clim.append(dict(id=f[1],name=f[2],mode=f[3],cur=float(f[4]),target=float(f[5]),action=f[9],modes=f[10].split(",")))
    if f[0]=="O": offc=int(f[1])
    if f[0]=="U": off.append(f[1])
    if f[0]=="B": batt.append((f[1],f[2]))

def ft(t): return "--" if t is None else f"{t:.1f}°"
def up(s): s=s[:1].upper()+s[1:]; return s.replace("_"," ")

class Dc:
    def __init__(s):
        s.im=Image.new("1",(W,H),0); s.d=ImageDraw.Draw(s.im); s.fg=WHITE
    def color(s,c): s.fg=c
    def text(s,x,y,font,txt,just="C",vc=True):
        fnt=F[font]
        lines=txt.split("\n"); lh=fnt.size+3
        tot=lh*len(lines)
        y0=y-tot/2 if vc else y
        for i,l in enumerate(lines):
            w=s.d.textlength(l,font=fnt)
            xx={"C":x-w/2,"L":x,"R":x-w}[just]
            s.d.text((xx,y0+i*lh),l,font=fnt,fill=s.fg)
    def circle(s,x,y,r,fill=False):
        s.d.ellipse((x-r,y-r,x+r,y+r),outline=s.fg,fill=s.fg if fill else None)
    def rect(s,x,y,w,h): s.d.rectangle((x,y,x+w-1,y+h-1),fill=s.fg)
    def rrect(s,x,y,w,h,r): s.d.rounded_rectangle((x,y,x+w-1,y+h-1),r,fill=s.fg)
    def poly(s,pts): s.d.polygon([tuple(p) for p in pts],fill=s.fg)
    def line(s,a,b,c,d): s.d.line((a,b,c,d),fill=s.fg)
    def tw(s,txt,font): return s.d.textlength(txt,font=F[font])

# ---------------- Dashboard ----------------
def dashboard():
    dc=Dc(); cx=W//2
    sx=SUB[0]+SUB[2]//2; sy=SUB[1]+SUB[3]//2
    n=offc+len(batt)
    dc.circle(sx,sy,SUB[2]//2,True); dc.color(BLACK)
    dc.text(sx,sy-4,"MEDIUM",str(n)); dc.text(sx,sy+16,"XTINY","ISSUES"); dc.color(WHITE)
    lcx=SUB[0]//2+8
    dc.text(lcx,34,"SMALL","HOME")
    t=clim[0]
    dc.text(cx,76,"LARGE",ft(t["cur"]))
    dc.text(cx,104,"XTINY","Set "+ft(t["target"])+"  "+up(t["mode"]))
    h=sum(1 for l in locs if l["type"]=="p" and l["state"]=="home")
    a=sum(1 for l in locs if l["type"]=="p" and l["state"]!="home")
    dc.text(cx,126,"XTINY",f"{h} home  {a} away")
    dc.text(cx,148,"XTINY","Updated 1m")
    return dc.im

# ---------------- Menu2 (approximation of native look) ----------------
def menu(title,items,focus=0):
    dc=Dc(); cx=W//2
    dc.text(cx,30,"XTINY",title)
    dc.line(30,42,146,42)
    # focused item large in middle, neighbours small above/below (Instinct style)
    y=88
    lab,subl=items[focus]
    dc.rect(0,62,W,54); dc.color(BLACK)
    dc.text(cx,y-(8 if subl else 0),"SMALL",lab)
    if subl: dc.text(cx,y+12,"XTINY",subl)
    dc.color(WHITE)
    if focus+1<len(items): dc.text(cx,132,"XTINY",items[focus+1][0])
    if focus+2<len(items): dc.text(cx,150,"XTINY",items[focus+2][0])
    return dc.im

# ---------------- Map ----------------
ZOOMS=[0,200,1000,5000,20000,100000,500000]
def offset(c,lat,lon):
    return ((lon-c[1])*111320*math.cos(math.radians(c[0])),(lat-c[0])*110574)
def dist(o): return math.hypot(*o)
def nice(m):
    if m<100: return 100.0
    p=10**math.floor(math.log10(m))
    for s in (1,2,5,10):
        if m<=s*p: return s*p
def fdist(m):
    if m<1000: return f"{int(m)}m"
    if m<10000: return f"{m/1000:.1f}km"
    return f"{int(m/1000)}km"
def bname(o):
    if dist(o)<30: return ""
    deg=math.degrees(math.atan2(o[0],o[1]))%360
    return ["N","NE","E","SE","S","SW","W","NW"][int((deg+22.5)/45)%8]
def house(dc,x,y):
    dc.poly([[x,y-7],[x-6,y-1],[x+6,y-1]]); dc.rect(x-4,y-1,9,6)
def mapview(zoom=0,selected=0,center=None,label="HOME"):
    dc=Dc(); cx=W//2; cy=66; r=58
    c=center or home
    offs=[offset(c,l["lat"],l["lon"]) for l in locs]
    maxD=max(dist(o) for o in offs)
    homeOff=None
    if label!="HOME":
        homeOff=offset(c,*home); maxD=max(maxD,dist(homeOff))
    scale=nice(maxD*1.1) if zoom==0 else ZOOMS[zoom]
    dc.circle(cx,cy,r); dc.circle(cx,cy,r//2); dc.line(cx,cy-r-4,cx,cy-r+4)
    dc.text(cx+r//2+2,cy,"XTINY",fdist(scale/2),"L")
    if label=="HOME": house(dc,cx,cy)
    else: dc.poly([[cx,cy-5],[cx-4,cy+4],[cx+4,cy+4]])
    def scr(o):
        px=o[0]/scale*r; py=o[1]/scale*r; d=math.hypot(px,py); cl=False
        if d>r: px=px*r/d; py=py*r/d; cl=True
        return cx+int(px),cy-int(py),cl
    if homeOff:
        x,y,_=scr(homeOff); house(dc,x,y)
    for i,l in enumerate(locs):
        x,y,cl=scr(offs[i])
        if cl: dc.circle(x,y,4)
        elif l["type"]=="p": dc.circle(x,y,4,True)
        else: dc.rect(x-3,y-3,7,7)
        if i==selected: dc.circle(x,y,8)
        dc.text(x+7,y-9,"XTINY",l["name"][0],"L",False)
    sel=locs[selected]
    dc.rect(0,126,W,H-126); dc.color(BLACK)
    dc.text(cx,135,"XTINY",sel["name"][:16])
    dc.text(cx,149,"XTINY",up(sel["state"])[:14])
    dc.text(cx,163,"XTINY",fdist(dist(offs[selected]))+" "+bname(offs[selected])); dc.color(WHITE)
    sx=SUB[0]+SUB[2]//2; sy=SUB[1]+SUB[3]//2
    dc.circle(sx,sy,SUB[2]//2,True); dc.color(BLACK)
    dc.text(sx,sy-9,"XTINY",label); dc.text(sx,sy+9,"XTINY","AUTO" if zoom==0 else fdist(ZOOMS[zoom])); dc.color(WHITE)
    return dc.im

# ---------------- Thermostat ----------------
def thermo(pending=None):
    dc=Dc(); cx=W//2; t=clim[0]
    sx=SUB[0]+SUB[2]//2; sy=SUB[1]+SUB[3]//2; m=t["mode"].upper()
    dc.circle(sx,sy,SUB[2]//2,True); dc.color(BLACK)
    dc.text(sx,sy-8,"XTINY","MODE"); dc.text(sx,sy+9,"SMALL",m[:5]); dc.color(WHITE)
    tg=pending if pending is not None else t["target"]
    dc.text(SUB[0]//2+8,34,"XTINY","SET TO" if pending is not None else "TARGET")
    dc.text(cx,80,"LARGE",ft(tg))
    dc.poly([[16,70],[11,78],[21,78]]); dc.poly([[16,104],[11,96],[21,96]])
    nl="Now "+ft(t["cur"])+("  "+up(t["action"]) if t["action"] else "")
    dc.text(cx,108,"XTINY",nl)
    dc.text(cx,128,"XTINY",t["name"][:18])
    dc.text(cx,150,"XTINY","START: mode")
    return dc.im

# ---------------- compose onto a watch-face style bezel ----------------
LIGHT=(196,204,190); DARK=(24,26,24)
S=3
def bezel(im,title):
    big=im.resize((W*S,H*S),Image.NEAREST)
    rgb=Image.new("RGB",big.size,DARK)
    rgb.paste(Image.new("RGB",big.size,LIGHT),mask=big.convert("L"))
    # round mask with sub-window cutout
    mask=Image.new("L",big.size,0); md=ImageDraw.Draw(mask)
    md.ellipse((0,0,W*S-1,H*S-1),fill=255)
    sx,sy,sw,sh=[v*S for v in SUB]; md.ellipse((sx,sy,sx+sw,sy+sh),fill=255)
    pad=40; tile=Image.new("RGB",(W*S+2*pad,H*S+2*pad+44),(245,245,245))
    td=ImageDraw.Draw(tile)
    td.ellipse((pad-22,pad-22,pad+W*S+22,pad+H*S+22),fill=(55,58,55))
    # sub-window ring
    td.ellipse((pad+sx-6,pad+sy-6,pad+sx+sw+6,pad+sy+sh+6),fill=(55,58,55))
    tile.paste(rgb,(pad,pad),mask)
    td.ellipse((pad+sx,pad+sy,pad+sx+sw,pad+sy+sh),outline=(90,95,90),width=3)
    f=ImageFont.truetype(FB,22)
    w=td.textlength(title,font=f); td.text(((tile.width-w)/2,tile.height-50),title,font=f,fill=(40,40,40))
    return tile

shots=[
 (dashboard(),"Dashboard"),
 (menu("Home Assistant",[("Map","3 tracked"),("Thermostat","18.8° > 17.5°"),("Problems","14 offline, 1 low batt"),("Refresh",None)]),"Main menu (START)"),
 (thermo(),"Thermostat"),
 (thermo(pending=19.0),"Thermostat after UP x3"),
 (mapview(0,0),"Map: auto zoom"),
 (mapview(2,1),"Map: 1 km zoom"),
 (menu("Problems (15)",[("Jordan's Phone","Battery 3%"),("Remote UI","Unavailable"),("Water flow rate",None),("Gas flow rate",None)]),"Problems"),
 (menu("Mode",[("Heat",None),("Off",None)]),"Mode picker"),
]
tiles=[bezel(i,t) for i,t in shots]
cols=4; tw,th=tiles[0].size
sheet=Image.new("RGB",(tw*cols,th*((len(tiles)+cols-1)//cols)),(245,245,245))
for k,t in enumerate(tiles): sheet.paste(t,((k%cols)*tw,(k//cols)*th))
sheet.save("preview.png")
print(sheet.size)
