#!/usr/bin/env python3
"""Only downloads public renderer/basemap assets; never reads Ares preferences."""
import pathlib, urllib.request, tarfile, io, json, math, random, hashlib
ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / '.build/routing-lab/assets'
OUT.mkdir(parents=True, exist_ok=True)
VERSION = '5.12.0'
def download(url):
    return urllib.request.urlopen(url, timeout=45).read()
if not (OUT / 'maplibre-gl.js').exists():
    data = download(f'https://registry.npmjs.org/maplibre-gl/-/maplibre-gl-{VERSION}.tgz')
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        for source, target in [('package/dist/maplibre-gl.js','maplibre-gl.js'), ('package/dist/maplibre-gl.css','maplibre-gl.css'), ('package/LICENSE.txt','MAPLIBRE-LICENSE.txt')]:
            (OUT / target).write_bytes(archive.extractfile(source).read())
if not (OUT / 'world.geojson').exists():
    # Natural Earth 1:110m countries, public domain. Version pinned.
    data = download('https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_110m_admin_0_countries.geojson')
    (OUT / 'world.geojson').write_bytes(data)
expected = {
    'maplibre-gl.js': '06b392de571c99e242581b0f3f23893e6e95efd3656974d6edfd8f8599ddf362',
    'world.geojson': '6866c877d39cba9c357620878839b336d569f8c662d3cfab4cb1dbe2d39c977f'
}
for filename, digest in expected.items():
    if hashlib.sha256((OUT / filename).read_bytes()).hexdigest() != digest:
        raise RuntimeError(f'Unexpected asset contents: {filename}')
world = json.loads((OUT / 'world.geojson').read_text())
# Each record is an explicit simulated connection; display aggregation must preserve all records.
cities = [('Shanghai',121.47,31.23),('Tokyo',139.69,35.68),('San Francisco',-122.42,37.77),('London',-.12,51.50),('Singapore',103.82,1.35),('Sydney',151.21,-33.87),('Sao Paulo',-46.63,-23.55),('Cape Town',18.42,-33.92),('New York',-74.01,40.71),('Frankfurt',8.68,50.11),('Auckland',174.76,-36.85)]
def position(index): return list(cities[index][1:])
def arc(a,b,steps=48):
    def unit(p):
        lon,lat=map(math.radians,p); return [math.cos(lat)*math.cos(lon), math.cos(lat)*math.sin(lon), math.sin(lat)]
    u,v=unit(a),unit(b); omega=math.acos(max(-1,min(1,sum(x*y for x,y in zip(u,v)))))
    result=[]
    for i in range(steps+1):
        t=i/steps
        w=[(math.sin((1-t)*omega)*x+math.sin(t*omega)*y)/math.sin(omega) for x,y in zip(u,v)] if omega>1e-9 else u
        lon=math.degrees(math.atan2(w[1],w[0])); lat=math.degrees(math.atan2(w[2],math.hypot(w[0],w[1])))
        if result:
            while lon-result[-1][0]>180: lon-=360
            while lon-result[-1][0]<-180: lon+=360
        result.append([lon,lat])
    return result
scenarios=[]
for name,n,mode in [('Global',160,'global'),('Pacific',80,'pacific'),('Colocated',2000,'colocated'),('Stress',20000,'stress')]:
    rng=random.Random(42); records=[]; edges={}; unlocated=0; total=0
    for i in range(n):
        a,b=(1,2) if mode=='pacific' else ((0,1) if mode=='colocated' else (rng.randrange(len(cities)),rng.randrange(len(cities))))
        if a==b:b=(b+1)%len(cities)
        unknown=mode in ['global','stress'] and i%17==0
        size=1000+rng.randrange(1000000); total+=size
        records.append({'id':f'{name}-{i}','from':a,'to':None if unknown else b,'bytes':size})
        if unknown:unlocated+=1;continue
        key=(a,b)
        if key not in edges:edges[key]={'id':f'{a}-{b}','name':cities[a][0]+' → '+cities[b][0],'from':position(a),'to':position(b),'points':arc(position(a),position(b)),'count':0,'bytes':0}
        edges[key]['count']+=1;edges[key]['bytes']+=size
    assert sum(e['count'] for e in edges.values())+unlocated==n
    assert sum(e['bytes'] for e in edges.values())+sum(r['bytes'] for r in records if r['to'] is None)==total
    for e in edges.values():assert all(abs(a[0]-b[0])<=180 for a,b in zip(e['points'],e['points'][1:]))
    scenarios.append({'name':name,'total':n,'unlocated':unlocated,'bytes':total,'edges':list(edges.values()),'records':records})
(OUT/'fixtures.json').write_text(json.dumps(scenarios,separators=(',',':')))
(OUT/'manifest.json').write_text(json.dumps({'maplibre':VERSION,'naturalEarth':'5.1.2 / 110m / public domain','assets':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.iterdir() if p.suffix in ['.js','.geojson']}},indent=2))
# Inline data avoids file-origin fetch restrictions in WKWebView; renderer uses no tile/telemetry endpoint.
template=(pathlib.Path(__file__).parent/'map.html').read_text()
template=template.replace('<script src="maplibre-gl.js"></script>', '<script>'+(OUT/'maplibre-gl.js').read_text()+'</script>')
template=template.replace('<link href="maplibre-gl.css" rel="stylesheet">', '<style>'+(OUT/'maplibre-gl.css').read_text()+'</style>')
(OUT/'index.html').write_text(template.replace('__WORLD__',json.dumps(world,separators=(',',':'))).replace('__FIXTURES__',json.dumps(scenarios,separators=(',',':'))))
print('Prepared 4 scenarios; exact count/byte aggregation and antimeridian continuity checks passed.')
