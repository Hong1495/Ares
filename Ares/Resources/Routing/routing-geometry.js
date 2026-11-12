// Pure geometry operations. No connection truncation; identical geometry shares a feature.
const RoutingGeometry = (() => {
function arc(a,b){const rad=Math.PI/180;const unit=p=>[Math.cos(p[1]*rad)*Math.cos(p[0]*rad),Math.cos(p[1]*rad)*Math.sin(p[0]*rad),Math.sin(p[1]*rad)];const u=unit(a),v=unit(b),omega=Math.acos(Math.max(-1,Math.min(1,u.reduce((s,x,i)=>s+x*v[i],0))));const points=[];for(let i=0;i<=64;i++){const t=i/64;let w;if(Math.abs(Math.sin(omega))<1e-6){let lon=b[0];while(lon-a[0]>180)lon-=360;while(lon-a[0]<-180)lon+=360;points.push([a[0]+t*(lon-a[0]),a[1]+t*(b[1]-a[1])]);continue}w=u.map((x,k)=>(Math.sin((1-t)*omega)*x+Math.sin(t*omega)*v[k])/Math.sin(omega));let lon=Math.atan2(w[1],w[0])/rad,lat=Math.atan2(w[2],Math.hypot(w[0],w[1]))/rad;if(points.length){while(lon-points.at(-1)[0]>180)lon-=360;while(lon-points.at(-1)[0]<-180)lon+=360}points.push([lon,Math.max(-85,Math.min(85,lat))]);}return points;}

// Split at the date line so world view shows both sides without duplicate worlds.
function splitDateLine(points) {
    const segments = [[]];
    const normalize = x => ((x+180)%360+360)%360-180;
    let previous;
    for (const [longitude, latitude] of points) {
        const point=[normalize(longitude),latitude];
        if (previous && Math.abs(point[0]-previous[0])>180) {
            const adjusted=point[0]+(previous[0]>0?360:-360);
            const edge=previous[0]>0?180:-180;
            const fraction=(edge-previous[0])/(adjusted-previous[0]);
            const crossing=previous[1]+fraction*(point[1]-previous[1]);
            segments.at(-1).push([edge,crossing]);
            segments.push([[-edge,crossing]]);
        }
        segments.at(-1).push(point);previous=point;
    }
    return segments;
}
function features(routes) {
    const lines = new Map(), points = new Map(), memberships = new Map();
    for (const route of routes) {
        const located = route.endpoints.filter(e => e.location).map(e => [e.location.longitude, e.location.latitude]);
        function add(store, key, geometry) {
            let feature = store.get(key);
            if (!feature) {
                feature = {type:'Feature', properties:{key}, geometry};
                store.set(key,feature);
                memberships.set(key,[]);
            }
            const members = memberships.get(key);
            if (members.at(-1) !== route.id) members.push(route.id);
        }
        for (const point of located) add(points, 'p'+JSON.stringify(point), {type:'Point',coordinates:point});
        for (let i=1;i<located.length;i++) {
            const a=located[i-1],b=located[i];
            if (a[0]===b[0] && a[1]===b[1]) continue;
            const ordered=JSON.stringify(a)<JSON.stringify(b)?[a,b]:[b,a];
            const key='l'+JSON.stringify(ordered);
            if (lines.has(key)) { memberships.get(key).push(route.id); }
            else add(lines,key,{type:'MultiLineString',coordinates:splitDateLine(arc(...ordered))});
        }
    }
    return {lines:{type:'FeatureCollection',features:[...lines.values()]},points:{type:'FeatureCollection',features:[...points.values()]},memberships};
}
function bounds(points) {
    if (!points.length) return null;
    const xs=[...new Set(points.map(p=>(p[0]%360+360)%360))].sort((a,b)=>a-b);
    let gap=-1,index=0;
    for(let i=0;i<xs.length;i++){const g=(i===xs.length-1?xs[0]+360:xs[i+1])-xs[i];if(g>gap){gap=g;index=i}}
    const left=xs[(index+1)%xs.length];
    let minX=Infinity,minY=Infinity,maxX=-Infinity,maxY=-Infinity;
    for(const p of points){let x=(p[0]%360+360)%360;if(x<left)x+=360;minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,p[1]);maxY=Math.max(maxY,p[1])}
    return [[minX,minY],[maxX,maxY]];
}
return {arc,features,bounds,splitDateLine};
})();
if (typeof module !== 'undefined') module.exports = RoutingGeometry;
