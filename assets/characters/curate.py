#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p "python3.withPackages (p: [ p.pillow ])"
"""Curate downloaded Quaternius assets; no network access."""
import copy, json, pathlib, struct, hashlib, shutil
from PIL import Image
ROOT=pathlib.Path('/tmp/signs-assets-research')
OUT=pathlib.Path.cwd()/'assets/characters'
OUT.mkdir(parents=True,exist_ok=True)

def load(p):
 b=p.read_bytes()
 if p.suffix=='.glb':
  size=struct.unpack_from('<I',b,12)[0];j=json.loads(b[20:20+size]); data=b[28+size:]
 else:
  j=json.loads(b);data=(p.parent/j['buffers'][0]['uri']).read_bytes()
 return j,data

def values(j,b,a):
 ac=j['accessors'][a];v=j['bufferViews'][ac['bufferView']];fmt={5126:'f',5125:'I',5123:'H',5121:'B'}[ac['componentType']];n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[ac['type']]; stride=v.get('byteStride',struct.calcsize(fmt)*n);off=v.get('byteOffset',0)+ac.get('byteOffset',0)
 return [list(struct.unpack_from('<'+fmt*n,b,off+i*stride)) for i in range(ac['count'])]

def add(j,b,vals,typ='SCALAR',component=5126):
 while len(b)%4:b.append(0)
 fmt={5126:'f',5125:'I'}[component];raw=b''.join(struct.pack('<'+fmt*len(v),*v) for v in vals)
 view=len(j['bufferViews']);j['bufferViews'].append({'buffer':0,'byteOffset':len(b),'byteLength':len(raw)});b.extend(raw)
 ac={'bufferView':view,'componentType':component,'count':len(vals),'type':typ}
 if typ in ['SCALAR','VEC3']:ac.update(min=[min(v[i] for v in vals) for i in range(len(vals[0]))],max=[max(v[i] for v in vals) for i in range(len(vals[0]))])
 j['accessors'].append(ac);return len(j['accessors'])-1

def mul(a,b):
 x,y,z,w=a;X,Y,Z,W=b
 return [w*X+x*W+y*Z-z*Y,w*Y-x*Z+y*W+z*X,w*Z+x*Y-y*X+z*W,w*W-x*X-y*Y-z*Z]

written_textures=set()
def texture(p,name):
 path=p.parent/name
 if not path.exists():
  options=list(ROOT.rglob(name.replace('_png.png','.png')))
  if not options:raise RuntimeError(name)
  path=options[0]
 target=OUT/name
 if name not in written_textures:
  im=Image.open(path);im.thumbnail((1024,1024),Image.Resampling.LANCZOS);im.save(target);written_textures.add(name)
 return name

def images(j,p):
 for im in j.get('images',[]): im['uri']=texture(p,im['uri'])

for sex in ['Male','Female']:
 p=next((ROOT/'outfits').rglob(sex+'_Peasant.gltf'));j,raw=load(p);b=bytearray(raw);images(j,p)
 base=next((ROOT/'base').rglob('Superhero_'+sex+'_FullBody.gltf'));s,sb=load(base)
 # Keep complete facial features plus the neck; remove hidden torso and limbs.
 body=s['meshes'][-1]
 for pr in body['primitives']:
  pos=values(s,sb,pr['attributes']['POSITION']);idx=values(s,sb,pr['indices']); keep=[];threshold=1.50 if sex=='Male' else 1.47
  for k in range(0,len(idx),3):
   tri=idx[k:k+3]
   if all(pos[v[0]][1]>=threshold and abs(pos[v[0]][0])<0.14 for v in tri):keep.extend(tri)
  sb=bytearray(sb);pr['indices']=add(s,sb,keep,component=5125)
  used=[pos[v[0]] for v in keep];a=s['accessors'][pr['attributes']['POSITION']];a['min']=[min(v[k] for v in used) for k in range(3)];a['max']=[max(v[k] for v in used) for k in range(3)]
 images(s,base)
 # Append source resources while mapping joints onto the outfit skeleton.
 def merge(s,sb):
  offsets={key:len(j.setdefault(key,[])) for key in ['accessors','bufferViews','materials','textures','images','samplers','meshes','skins']}
  while len(b)%4:b.append(0)
  bo=len(b);b.extend(sb)
  for view in s.get('bufferViews',[]):
   view['buffer']=0;view['byteOffset']=view.get('byteOffset',0)+bo
  for ac in s.get('accessors',[]):ac['bufferView']+=offsets['bufferViews']
  for tex in s.get('textures',[]):
   tex['source']+=offsets['images']
   if 'sampler' in tex:tex['sampler']+=offsets['samplers']
  def mat_indices(d):
   for key,val in d.items():
    if isinstance(val,dict):
     if key.endswith('Texture'):val['index']+=offsets['textures']
     else:mat_indices(val)
  for mat in s.get('materials',[]):mat_indices(mat)
  for mesh in s.get('meshes',[]):
   for pr in mesh['primitives']:
    pr['attributes']={k:v+offsets['accessors'] for k,v in pr['attributes'].items()};pr['indices']+=offsets['accessors'];pr['material']+=offsets['materials']
  node_by_name={n['name']:i for i,n in enumerate(j['nodes'])}
  for skin in s.get('skins',[]):
   skin['joints']=[node_by_name[s['nodes'][v]['name']] for v in skin['joints']];skin['inverseBindMatrices']+=offsets['accessors']
   if 'skeleton' in skin:skin['skeleton']=node_by_name[s['nodes'][skin['skeleton']]['name']]
  root=j['scenes'][0]['nodes'][0]
  for n in s['nodes']:
   if 'mesh' not in n:continue
   n=copy.deepcopy(n);n['mesh']+=offsets['meshes'];n['skin']+=offsets['skins'];j['nodes'][root]['children'].append(len(j['nodes']));j['nodes'].append(n)
  for key in offsets:j[key].extend(s.get(key,[]))
 merge(s,sb)
 # Multiple authored hairstyles are built into each model; runtime selects one.
 for hair in (['Hair_SimpleParted','Hair_Buzzed','Hair_Beard'] if sex=='Male' else ['Hair_Buns','Hair_Long']):
  hp=next(p for p in (ROOT/'base').rglob(hair+'.gltf') if 'Rigged to Head Bone' in str(p));h,hb=load(hp);images(h,hp);merge(h,hb)
 # Rest-relative rotations preserve the different body proportions. Pelvis bob is
 # retained but all horizontal root travel and root rotation are excluded.
 ap=next((ROOT/'anim').rglob('UAL1_Standard.glb'));a,ab=load(ap);j['animations']=[]
 wanted=['Idle_Loop','Walk_Loop','Idle_Talking_Loop','Spell_Simple_Idle_Loop','Fixing_Kneeling','Interact']
 nd={n['name']:i for i,n in enumerate(j['nodes'])}
 for anim in a['animations']:
  if anim['name'] not in wanted:continue
  new={'name':anim['name'],'channels':[],'samplers':[]}
  for ch in anim['channels']:
   sn=a['nodes'][ch['target']['node']];name=sn['name'];prop=ch['target']['path']
   if name=='root' or not (prop=='rotation' or (name=='pelvis' and prop=='translation')):continue
   sam=anim['samplers'][ch['sampler']];times=values(a,ab,sam['input']);vv=values(a,ab,sam['output']);dn=j['nodes'][nd[name]]
   if prop=='rotation':
    r=sn.get('rotation',[0,0,0,1]);inv=[-r[0],-r[1],-r[2],r[3]];delta=mul(dn.get('rotation',[0,0,0,1]),inv);vv=[mul(delta,v) for v in vv]
   else:
    # glTF root is -90 deg X: local Z maps to world height.
    rest=dn['translation'];src=sn['translation'];vv=[[rest[0],rest[1],rest[2]+v[2]-src[2]] for v in vv]
   new['channels'].append({'sampler':len(new['samplers']),'target':{'node':nd[name],'path':prop}})
   new['samplers'].append({'input':add(j,b,times),'output':add(j,b,vv,'VEC4' if prop=='rotation' else 'VEC3'),'interpolation':'LINEAR'})
  j['animations'].append(new)
 j['buffers']=[{'uri':sex.lower()+'_villager.bin','byteLength':len(b)}]
 (OUT/(sex.lower()+'_villager.gltf')).write_text(json.dumps(j,separators=(',',':')))
 (OUT/(sex.lower()+'_villager.bin')).write_bytes(b)
for key in ['base','outfits','anim']:
 src=next((ROOT/key).rglob('License*.txt'));shutil.copyfile(src,OUT/(key+'-LICENSE.txt'))
shutil.copyfile(next((ROOT/'anim').rglob('README.txt')),OUT/'animation-README.txt')
(OUT/'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in sorted(OUT.iterdir()) if p.is_file() and p.suffix in ['.gltf','.bin','.png','.txt','.py','.json']))
print('Curated',sum(p.stat().st_size for p in OUT.iterdir()),'bytes')
