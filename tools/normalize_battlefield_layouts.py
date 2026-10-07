"""Author lower-friendly layouts and gentle, terrain-safe route branches.

Drafts stay in tests/profiles. Production replacement is a separate explicit
--commit step after the Godot verifier has checked the actual runtime geometry.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import heapq
import itertools
import json
import math
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
PROFILE=ROOT/'tests/profiles/lower-layout-design'
SOURCE=ROOT/'native/maps.json'
ASPECTS=(1248/620,1408/720,1888/900,1672/941)
MAX_ASPECT=max(ASPECTS)
BASE_MARGIN=.018
GRID=.0125
BLUEPRINTS=json.loads((ROOT/'tools/lower_route_blueprints.json').read_text(encoding='utf-8'))['stages']

def xy(p): return float(p['x']),float(p['y'])
def rec(p): return {'x':round(p[0],6),'y':round(p[1],6)}
def add(a,b): return a[0]+b[0],a[1]+b[1]
def sub(a,b): return a[0]-b[0],a[1]-b[1]
def mul(a,t): return a[0]*t,a[1]*t
def lerp(a,b,t): return add(a,mul(sub(b,a),t))
def norm(v): return mul(v,1/max(math.hypot(*v),1e-12))
def distance(a,b): return math.dist(a,b)
def rotate(p,k):
    x,y=p
    return [(x,y),(1-y,x),(1-x,1-y),(y,1-x)][k%4]

def allowed(p,margin=0):
    dx=(p[0]-.5)*MAX_ASPECT
    dy=p[1]-.5
    return dy>0 and dx>=-math.sqrt(3)*dy+margin and dx<=dy/math.sqrt(3)-margin

def point_segment(p,a,b):
    axis=sub(b,a)
    denom=sum(x*x for x in axis)
    t=max(0,min(1,sum(x*y for x,y in zip(sub(p,a),axis))/max(denom,1e-12)))
    q=lerp(a,b,t)
    return distance(p,q),q,t

def lengths(points):
    result=[0.0]
    for a,b in zip(points,points[1:]): result.append(result[-1]+distance(a,b))
    return result

def along(points,fraction):
    dd=lengths(points)
    target=max(0,min(1,fraction))*dd[-1]
    for i in range(len(points)-1):
        if target<=dd[i+1]+1e-10:
            return lerp(points[i],points[i+1],(target-dd[i])/max(dd[i+1]-dd[i],1e-12)),i,(target-dd[i])/max(dd[i+1]-dd[i],1e-12)
    return points[-1],len(points)-2,1.0

def closest(p,points):
    best=(1e10,None,0,0)
    for i,(a,b) in enumerate(zip(points,points[1:])):
        d,q,t=point_segment(p,a,b)
        if d<best[0]: best=d,q,i,t
    return best

def rect_turn(item,k):
    x,y=xy(item); w=float(item.get('w',0)); h=float(item.get('h',0))
    corners=[rotate(p,k) for p in [(x,y),(x+w,y),(x+w,y+h),(x,y+h)]]
    lower=(min(p[0] for p in corners),min(p[1] for p in corners))
    upper=(max(p[0] for p in corners),max(p[1] for p in corners))
    return dict(rec(lower),w=round(upper[0]-lower[0],6),h=round(upper[1]-lower[1],6))

def rotate_source(value,k,path=''):
    if isinstance(value,list): return [rotate_source(x,k,path+'[]') for x in value]
    if not isinstance(value,dict): return value
    result={key:rotate_source(x,k,path+'.'+key if path else key) for key,x in value.items()}
    if 'x' not in value or 'y' not in value: return result
    if path in ['water','bridges[]','historicalBattlefield.waterFeatures[]']:
        result.update(rect_turn(value,k))
    else:
        result.update(rec(rotate(xy(value),k)))
        if path=='historicalBattlefield.heightFeatures[]':
            result['orientationRadians']=round(float(value.get('orientationRadians',0))+k*math.pi/2,6)
        elif path in ['historicalBattlefield.landmarkLabels[]','historicalBattlefield.sceneLandmarks[]']:
            if k%2 and isinstance(result.get('scale'),dict):
                result['scale']['w'],result['scale']['h']=result['scale'].get('h',.14),result['scale'].get('w',.18)
            # Footprint axes rotate above. Props are re-authored upright and
            # defended gates derive their facing from the final approach.
            result['orientationRadians']=float(value.get('orientationRadians',0))
    return result

def collision_rects(stage):
    result=[]
    if stage.get('water'): result.append(stage['water'])
    for feature in stage['historicalBattlefield'].get('waterFeatures',[]):
        kind=feature.get('kind','')
        if kind=='wetland' or not feature.get('blocksMovement',kind in ['river','stream','lake','wetland_lake']): continue
        result.append(feature)
    return result

def rect_intersection(a,b,rect,margin=0):
    lower=(rect['x']-margin,rect['y']-margin)
    upper=(rect['x']+rect['w']+margin,rect['y']+rect['h']+margin)
    low,high=0.0,1.0
    for axis in [0,1]:
        delta=b[axis]-a[axis]
        if abs(delta)<1e-12:
            if a[axis]<lower[axis] or a[axis]>upper[axis]: return False
        else:
            v1=(lower[axis]-a[axis])/delta; v2=(upper[axis]-a[axis])/delta
            low=max(low,min(v1,v2)); high=min(high,max(v1,v2))
            if low>high: return False
    return True

class Terrain:
    def __init__(self,stage):
        self.water=collision_rects(stage)
        self.obstacles=[o for o in stage.get('obstacles',[]) if o.get('blockPlacement')]
        # Native props are upright meshes, not the full abstract landmark
        # areas. Match the actual _build_wall/_build_fort clamps in world units.
        # Levees are walkable raised roads and are not treated as walls.
        self.structures=[]
        world_width=18.5; world_depth=world_width/MAX_ASPECT/math.sin(math.radians(65))
        for landmark in stage['historicalBattlefield'].get('sceneLandmarks',[]):
            kind=landmark.get('kind',''); p=xy(landmark)
            scale=landmark.get('scale',{}); wx=float(scale.get('w',.18))*world_width; hy=float(scale.get('h',.14))*world_depth
            if kind in ['palisade','earthen_wall','outer_earthwork','dry_earthwork']:
                horizontal=wx>hy; span=max(1.4,min(6.0,max(wx,hy)))
                width,height=(span/world_width,.7/world_depth) if horizontal else (.7/world_width,span/world_depth)
            elif kind in ['earthen_fort','hill_fort','low_hill_fort','mountain_fort','plain_fort','field_fort','temple_fort','island_earthen_fort','lowland_island_fort','river_cliff_fort','terrace_fort','earthwork_castle_town']:
                if any(distance(p,xy(goal))<.10 for goal in stage['objectives']): continue
                fort_width=max(2.4,min(4.4,wx));fort_depth=max(1.7,min(3.4,hy))
                width=(fort_width+.6)/world_width
                height=(.97*fort_depth+.35)/world_depth
                # _build_fort's side banks extend from -.32 depth to +.68
                # and its back bank sits at +.65 depth, not around the pivot.
                offset=.165*fort_depth+.175
                yaw=float(landmark.get('orientationRadians',0))
                p=add(p,(math.sin(yaw)*offset/world_width,math.cos(yaw)*offset/world_depth))
            else: continue
            yaw=float(landmark.get('orientationRadians',0))
            # A conservative bounding rectangle includes the wall thickness.
            rotated_width=abs(width*math.cos(yaw))+abs(height*math.sin(yaw))
            rotated_height=abs(width*math.sin(yaw))+abs(height*math.cos(yaw))
            self.structures.append({'x':p[0]-rotated_width/2,'y':p[1]-rotated_height/2,'w':rotated_width,'h':rotated_height,'landmarkId':landmark.get('id'),'kind':kind})
    def point(self,p,margin=.008):
        return self.segment(p,p,margin)
    def segment(self,a,b,margin=.008):
        if any(rect_intersection(a,b,r,margin) for r in self.water): return False
        if any(rect_intersection(a,b,r,margin) for r in self.structures): return False
        if any(point_segment(xy(o),a,b)[0]<=float(o['r'])+margin for o in self.obstacles): return False
        return True
    def circle(self,p,r):
        if p[0]-r<.022 or p[0]+r>.978 or p[1]-r<.028 or p[1]+r>.972: return False
        if any(rect_intersection(p,p,o,r+.002) for o in self.water): return False
        if any(rect_intersection(p,p,o,r+.002) for o in self.structures): return False
        if any(distance(p,xy(o))<=float(o['r'])+r+.002 for o in self.obstacles): return False
        return True

def safe_goals(stage,terrain):
    old=[xy(x) for x in stage['objectives']]
    pool=[]
    for y in [i/100 for i in range(77,89,2)]:
        for x in [i/100 for i in range(25,61,2)]:
            p=(x,y)
            if allowed(p,.035) and terrain.point(p,.029): pool.append(p)
    if not pool: raise ValueError('No land in lower base sector '+stage['id'])
    if len(old)==1:
        if allowed(old[0],.035) and .75<=old[0][1]<=.89 and terrain.point(old[0],.029): return old
        return [min(pool,key=lambda p:distance(p,old[0]))]
    candidates=[]
    for selection in itertools.combinations(pool,3):
        if min(distance(a,b) for a,b in itertools.combinations(selection,2))<.145: continue
        if max(p[1] for p in selection)-min(p[1] for p in selection)>.09: continue
        ordered=sorted(selection)
        for permutation in itertools.permutations(ordered):
            cost=sum(distance(a,b) for a,b in zip(old,permutation))
            cost+=.1*(max(p[1] for p in selection)-min(p[1] for p in selection))
            candidates.append((cost,permutation))
    if not candidates: raise ValueError('No separated multi-base land '+stage['id'])
    return list(min(candidates,key=lambda row:row[0])[1])

def entry_and_branch(stage,terrain,goals):
    original=xy(stage.get('commonEnemyEntry',stage['paths'][0]['points'][0]))
    center=(sum(p[0] for p in goals)/len(goals),sum(p[1] for p in goals)/len(goals))
    candidates=[]
    if (original[1]<=.24 or (original[0]<=.065 or original[0]>=.935) and original[1]<=.60) and terrain.point(original,.024): candidates.append(original)
    for y in [.07,.12,.20,.30,.40,.50]:
        for x in [.04,.96]:
            if terrain.point((x,y),.024): candidates.append((x,y))
    for x in [.14,.26,.38,.50,.62,.74,.86]:
        if terrain.point((x,.04),.024): candidates.append((x,.04))
    for entry in sorted(set(candidates),key=lambda p:distance(p,original)+max(0,p[1]-.22)*.3):
        direction=norm(sub(center,entry))
        for d in [.18,.15,.12]:
            branch=add(entry,mul(direction,d))
            if terrain.segment(entry,branch,.024): return entry,branch
    raise ValueError('No natural dry inlet '+stage['id'])

def astar(start,goal,terrain,lane=0):
    def snap(p): return round(p[0]/GRID),round(p[1]/GRID)
    def value(p): return p[0]*GRID,p[1]*GRID
    ss=snap(start); gg=snap(goal)
    def nearest(node,exact):
        choices=[(node[0]+dx,node[1]+dy) for dx in range(-3,4) for dy in range(-3,4)]
        valid=[n for n in choices if 2<=n[0]<=78 and 2<=n[1]<=77 and terrain.segment(exact,value(n),.020)]
        return min(valid,key=lambda n:distance(exact,value(n))) if valid else None
    ss=nearest(ss,start); gg=nearest(gg,goal)
    if ss is None or gg is None: raise ValueError('No safe grid endpoint')
    center_axis=sub(goal,start); center_length=math.hypot(*center_axis); direction=norm(center_axis); normal=(-direction[1],direction[0])
    frontier=[(distance(value(ss),goal),0,ss)]
    scores={ss:0}; parents={}; used=set()
    while frontier:
        _,cost,current=heapq.heappop(frontier)
        if current in used: continue
        used.add(current)
        if current==gg:
            nodes=[current]
            while current!=ss: current=parents[current];nodes.append(current)
            result=[start]+[value(n) for n in reversed(nodes)]+[goal]
            return simplify(result,terrain)
        for dx,dy in [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]:
            nxt=current[0]+dx,current[1]+dy
            if not (2<=nxt[0]<=78 and 2<=nxt[1]<=77): continue
            p=value(nxt); previous=value(current)
            if not terrain.segment(previous,p,.020): continue
            progress=max(0,min(1,sum(a*b for a,b in zip(sub(p,start),direction))/max(center_length,1e-9)))
            desired=add(lerp(start,goal,progress),mul(normal,lane*math.sin(progress*math.pi)))
            added=distance(previous,p)*(1+distance(p,desired)*2.0)
            new=cost+added
            if new<scores.get(nxt,1e9):
                scores[nxt]=new;parents[nxt]=current
                heapq.heappush(frontier,(new+distance(p,goal),new,nxt))
    raise ValueError('No land connection')

def simplify(points,terrain):
    compact=[points[0]]
    for p in points[1:]:
        if distance(p,compact[-1])>.00001: compact.append(p)
    result=[compact[0]]; index=0
    while index<len(compact)-1:
        selected=index+1
        for nxt in range(index+2,len(compact)):
            if terrain.segment(compact[index],compact[nxt],.019): selected=nxt
        result.append(compact[selected]);index=selected
    return result

def rounded(points,terrain,radius=.045):
    output=[points[0]]
    for i in range(1,len(points)-1):
        a,b,c=points[i-1:i+2]
        cut=min(radius,distance(a,b)*.3,distance(b,c)*.3)
        chosen=None
        for _ in range(8):
            inner=add(b,mul(norm(sub(a,b)),cut)); outer=add(b,mul(norm(sub(c,b)),cut))
            curve=[add(add(mul(inner,(1-t)**2),mul(b,2*(1-t)*t)),mul(outer,t*t)) for t in [n/8 for n in range(9)]]
            if all(terrain.segment(p,q,.008) for p,q in zip([output[-1]]+curve,curve+[outer])):
                chosen=curve;break
            cut*=.55
        if chosen: output.extend(chosen)
        else: output.append(b)
    output.append(points[-1])
    clean=[output[0]]
    for p in output[1:]:
        if distance(p,clean[-1])>.00015: clean.append(p)
    return clean

def natural_branch(entry,branch,goal,lane,terrain):
    span=distance(branch,goal); axis=norm(sub(goal,branch)); normal=(-axis[1],axis[0]); entrance=norm(sub(branch,entry))
    common=lerp(entry,branch,.60)
    for multiplier in [1,.7,.4,0]:
        first=add(branch,add(mul(entrance,span*.29),mul(normal,lane*multiplier)))
        second=add(lerp(branch,goal,.72),mul(normal,lane*multiplier))
        curve=[]
        for n in range(35):
            t=n/34
            p=add(add(mul(branch,(1-t)**3),mul(first,3*(1-t)**2*t)),add(mul(second,3*(1-t)*t*t),mul(goal,t**3)))
            curve.append(p)
        if all(.024<=p[0]<=.976 and .028<=p[1]<=.968 for p in curve) and all(terrain.segment(a,b,.010) for a,b in zip(curve,curve[1:])):
            return [entry,common]+curve
    raw=astar(branch,goal,terrain,lane)
    return [entry]+rounded([common]+raw,terrain)

def authored_roads(stage,entry,goals,terrain):
    blueprint=BLUEPRINTS[str(stage['stageNumber'])]
    if len(blueprint['routes'])!=len(stage['paths']): raise ValueError('Incomplete authored topology '+stage['id'])
    routes=[]
    goal_by_id={o['id']:p for o,p in zip(stage['objectives'],goals)}
    corrections=[]
    for index,path in enumerate(stage['paths']):
        waypoints=[entry]+[tuple(p) for p in blueprint['trunk']+blueprint['routes'][index]]+[goal_by_id[path['objectiveId']]]
        safe=[]
        for ordinal,p in enumerate(waypoints):
            if not terrain.point(p,.021):
                q=nearest_safe(p,terrain,.022)
                if q is None or distance(p,q)>.115: raise ValueError('Authored terrain anchor is obstructed '+stage['id']+' '+str(p))
                corrections.append({'pathIndex':index,'anchorIndex':ordinal,'requested':rec(p),'actual':rec(q)})
                p=q
            if not safe or distance(p,safe[-1])>.003: safe.append(p)
        raw=[safe[0]]
        for a,b in zip(safe,safe[1:]):
            if terrain.segment(a,b,.021): raw.append(b)
            else: raw.extend(astar(a,b,terrain)[1:])
        prefix=lerp(raw[0],raw[1],min(.35,.045/max(distance(raw[0],raw[1]),.0001)))
        pts=[raw[0]]+rounded([prefix]+raw[1:],terrain,.075)
        if any(not terrain.segment(a,b,.002) for a,b in zip(pts,pts[1:])): raise ValueError('Unsafe authored route '+stage['id'])
        routes.append(pts)
    # All routes have the identical early trunk. Store its first actual point,
    # rather than claiming the two paths split at an unrelated old coordinate.
    if any(distance(routes[0][1],r[1])>.000001 for r in routes): raise ValueError('Inconsistent authored inlet '+stage['id'])
    return routes,blueprint,corrections

def nearest_safe(p,terrain,r=.016):
    if terrain.point(p,r) and .035<=p[0]<=.965 and .04<=p[1]<=.95: return p
    choices=[]
    for x in range(3,78):
        for y in range(4,76):
            q=x*GRID,y*GRID
            if terrain.point(q,r): choices.append(q)
    return min(choices,key=lambda q:distance(q,p)) if choices else None

def relocate_landmarks(stage,old_goals,new_goals):
    history=stage['historicalBattlefield']
    for group in ['landmarkLabels','sceneLandmarks','heightFeatures','traces']:
        for item in history.get(group,[]):
            if 'x' not in item: continue
            p=xy(item)
            nearest=min(range(len(old_goals)),key=lambda i:distance(p,old_goals[i]))
            d=distance(p,old_goals[nearest])
            # Move the defended gate/fort and its immediate rise together.
            # Unrelated historical terrain keeps its rotated relationship.
            if d<.035 or (d<.18 and item.get('kind') in ['hill','hill_slope','low_rise','ridge','mountain_fort','hill_fort','low_hill_fort','plateau','stone_terrace','river_terrace']):
                move=sub(new_goals[nearest],old_goals[nearest])
                q=add(p,move)
                item.update(rec((min(.94,max(.06,q[0])),min(.93,max(.07,q[1])))))

def supply_loop(stage,terrain):
    start=xy(stage['objectives'][0])
    rx,ry={6:(.14,.095),16:(.13,.11),26:(.14,.07),36:(.12,.09)}[int(stage['stageNumber'])]
    center=(start[0],start[1]-ry)
    loop=[]
    for n in range(65):
        angle=math.pi/2+n/64*2*math.pi
        bend=1+.055*math.sin(2*angle+stage['stageNumber']*.17)
        loop.append((center[0]+rx*math.cos(angle)*bend,center[1]+ry*math.sin(angle)))
    loop[0]=start;loop[-1]=start
    if not all(terrain.segment(a,b,.008) for a,b in zip(loop,loop[1:])): raise ValueError('No clear rear supply circulation '+stage['id'])
    return [rec(p) for p in loop]

def build(stage):
    variants=[]
    for k in range(4):
        candidate=rotate_source(stage,k)
        terrain=Terrain(candidate)
        try:
            goals=safe_goals(candidate,terrain)
            entry,branch=entry_and_branch(candidate,terrain,goals)
            for goal in goals: astar(branch,goal,terrain)
        except ValueError:
            continue
        old=[xy(o) for o in candidate['objectives']]
        score=sum(distance(a,b) for a,b in zip(old,goals))+distance(xy(candidate['commonEnemyEntry']),entry)*.45
        score+=min(k,4-k)*.014
        variants.append((score,k,candidate,goals,entry,branch))
    if not variants: raise ValueError('No terrain-valid lower layout '+stage['id'])
    _,k,result,goals,entry,branch=min(variants,key=lambda x:x[0])
    old_goals=[xy(o) for o in result['objectives']]
    relocate_landmarks(result,old_goals,goals)
    for objective,p in zip(result['objectives'],goals): objective.update(rec(p))
    terrain=Terrain(result)
    path_by_id={o['id']:p for o,p in zip(result['objectives'],goals)}
    count=len(result['paths'])
    route_points,blueprint,corrections=authored_roads(result,entry,goals,terrain)
    for index,path in enumerate(result['paths']):
        pts=route_points[index]
        if any(not terrain.segment(a,b,.002) for a,b in zip(pts,pts[1:])): raise ValueError('Unsafe road '+stage['id'])
        path['points']=[rec(p) for p in pts]
    result['commonEnemyEntry'].update(rec(entry))
    result['commonEnemyEntry']['branchPoint']=rec(route_points[0][1])
    if 'landingIndex' in result:
        # These historical approaches are entirely land routes. Old sparse
        # waypoint indices must not mark newly sampled dry road points as boats.
        result['landingIndex']=0
    # Source path metadata remains authoritative. Every route starts at the
    # same inlet and the same real fork instead of inventing a second spawn.
    for post in result.get('tactics',{}).get('groundPosts',[]):
        index=int(post['pathIndex'])
        posts=[p for p in result['tactics']['groundPosts'] if int(p['pathIndex'])==index]
        ordinal=next(i for i,p in enumerate(posts) if p['id']==post['id'])
        fraction=.29+.43*(ordinal+.5)/len(posts)
        # The very short shared farm trunk otherwise puts this tiny support
        # circle entirely inside an earlier post on another road. Use its own
        # separated downstream approach, preserving radius and role.
        if int(stage['stageNumber'])==32 and str(post['id']).endswith('ground-2'): fraction=.82
        p,segment,t=along(route_points[index],fraction)
        post['segmentIndex']=segment;post['t']=round(t,6)
    # Relocate each emplacement to usable land beside a real road. IDs,
    # radii, elevation and the roster/economic contract are unchanged.
    chosen=[];chosen_r=[]
    for zone in result['buildZones']:
        r=float(zone['r']); old=xy(zone); pool=[]
        exclusive_center=int(stage['stageNumber'])==23
        for path_index,pts in enumerate(route_points):
            for fraction in [i/100 for i in range(8,94,3)]:
                p,segment,t=along(pts,fraction)
                tangent=norm(sub(pts[segment+1],pts[segment])); normal=(-tangent[1],tangent[0])
                for side in [-1,1]:
                    for offset in [max(.052,r+.025),max(.075,r+.045),max(.09,r+.07),.185,.20]:
                        q=add(p,mul(normal,side*offset))
                        if not terrain.circle(q,r): continue
                        if any(closest(q,other)[0]<r+.017 for other in route_points): continue
                        if any(distance(q,g)<r+.072 for g in goals): continue
                        if any(distance(q,prior)<(max(.074,prior_r+.006) if exclusive_center else .074) for prior,prior_r in zip(chosen,chosen_r)): continue
                        cost=distance(q,old)+abs(offset-.12)*.25
                        pool.append((cost,q))
        if not pool:
            for x in range(11,90,2):
                for y in range(12,89,2):
                    q=x/100,y/100
                    if not terrain.circle(q,r): continue
                    road_distance=min(closest(q,other)[0] for other in route_points)
                    if not r+.017<=road_distance<=.205: continue
                    if any(distance(q,g)<r+.072 for g in goals) or any(distance(q,prior)<(max(.074,prior_r+.006) if exclusive_center else .074) for prior,prior_r in zip(chosen,chosen_r)): continue
                    pool.append((distance(q,old)+abs(road_distance-.12)*.25,q))
        if not pool:
            raise ValueError('No full clear emplacement '+stage['id']+' '+zone['id'])
        q=min(pool,key=lambda row:row[0])[1]
        zone.update(rec(q));chosen.append(q);chosen_r.append(r)
    # Preserve side-entry IDs and roles, and connect them through actual dry
    # space to their own route. Never cross walls/water as a visual shortcut.
    for index,side in enumerate(result.get('sideAmbushEntrances',[])):
        route_index=int(side['pathIndex']); pts=route_points[route_index]; candidates=[]
        for fraction in [.38,.48,.58,.68,.78]:
            anchor,segment,t=along(pts,fraction)
            tangent=norm(sub(pts[segment+1],pts[segment])); normal=(-tangent[1],tangent[0])
            for direction in [-1,1]:
                for offset in [.085,.11,.135]:
                    outside=add(anchor,mul(normal,direction*offset))
                    if not (.055<=outside[0]<=.945 and .06<=outside[1]<=.93): continue
                    if terrain.segment(outside,anchor,.007) and all(distance(outside,p)>.035 for p in chosen):
                        candidates.append((distance(outside,xy(side['point'])),outside,anchor))
        if not candidates: raise ValueError('No safe side ingress '+stage['id'])
        _,outside,anchor=min(candidates,key=lambda row:row[0])
        side['point']=rec(outside);side['connectionPoints']=[rec(outside),rec(lerp(outside,anchor,.5)),rec(anchor)]
    if result.get('escortRoute'):
        # A supply convoy circulates around its rear depot; it does not
        # repeatedly reverse direction on a single dead-end segment.
        result['escortRoute']=supply_loop(result,terrain)
    for torch in result.get('torches',[]):
        q=nearest_safe(xy(torch),terrain,.018)
        if q is not None: torch.update(rec(q))
    # Operation auras stay tied to their original emplacement ordinal.
    for aura in result.get('trait',{}).get('auras',[]):
        original_zones=rotate_source(stage,k)['buildZones']
        nearest=min(range(len(original_zones)),key=lambda i:distance(xy(aura),xy(original_zones[i])))
        aura.update(rec(xy(result['buildZones'][nearest])))
    history=result['historicalBattlefield']
    history['layoutCoordinatePolicyKo']='아군 기지와 출진구를 화면 중앙 기준 8시~5시 하단에 둔 게임용 전장 배치입니다. 실제 방위·거리·성곽 경계와 행군선을 복원한 좌표가 아닙니다.'
    history['roadArtPolicyKo']='공통 육지 진입구에서 실제 지형을 따라 완만하게 갈라지는 2~4개 침투로입니다. 새 paths의 모든 점과 통과 폭을 그대로 미술 가이드에 반영하고, 물·절벽·성벽을 횡단하거나 불필요한 사각/U자 우회로 길이를 늘리지 않습니다. 아군 기지와 출진구는 하단에 있습니다.'
    history['routeTopologyKo']=blueprint['reasonKo']
    history['artDirectionKo']=history.get('artDirectionKo','')+' 최종 표시 방향은 실제 북쪽이 아니라 아군 하단 배치입니다. 방향·도로·표식은 최신 가이드의 새 좌표를 따르며 원문 속 방위 문구를 화면 좌표로 재사용하지 않습니다.'
    history['ambushClearings']=[] # Enriched from actual Game-generated sites.
    manifest={'stageId':stage['id'],'stageNumber':stage['stageNumber'],'sourceQuarterTurns':k,
              'oldObjectives':stage['objectives'],'newObjectives':result['objectives'],
              'oldCommonEntry':stage['commonEnemyEntry'],'newCommonEntry':result['commonEnemyEntry'],
              'zoneMapping':[{'id':new['id'],'old':rec(xy(old)),'new':rec(xy(new))} for old,new in zip(stage['buildZones'],result['buildZones'])],
              'oldRouteLengths':[lengths([xy(p) for p in path['points']])[-1] for path in stage['paths']],
              'newRouteLengths':[lengths([xy(p) for p in path['points']])[-1] for path in result['paths']],
              'learningPositionsRequireRegeneration':True,'mirroredPresentation':False,'routeTopologyKo':blueprint['reasonKo'],'terrainAnchorCorrections':corrections,'physicalStructureKeepouts':terrain.structures}
    return result,manifest

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--commit',action='store_true');parser.add_argument('--finalize',type=Path,help='Verified learning anchor shard for the current private geometry');args=parser.parse_args()
    PROFILE.mkdir(parents=True,exist_ok=True)
    baseline=PROFILE/'source-maps-baseline.json'
    if not baseline.exists(): baseline.write_bytes(SOURCE.read_bytes())
    original=json.loads(baseline.read_text(encoding='utf-8'))
    source_hash=hashlib.sha256(baseline.read_bytes()).hexdigest()
    if args.finalize:
        draft=PROFILE/'maps-lower-draft.json'
        geometry_hash=hashlib.sha256(draft.read_bytes()).hexdigest()
        proof=json.loads((PROFILE/'runtime-verification.json').read_text(encoding='utf-8'))
        shard=json.loads(args.finalize.read_text(encoding='utf-8'))
        if not proof.get('passed') or proof.get('failures') or proof.get('draftSha256')!=geometry_hash: raise SystemExit('Refuse finalization: current actual geometry was not verified')
        if shard.get('mapsSha256','').lower()!=geometry_hash: raise SystemExit('Refuse finalization: learning coordinates refer to a different geometry')
        stages=json.loads(draft.read_text(encoding='utf-8'))
        clearings={s['stageId']:s['ambushClearings'] for s in proof['ambushEnrichments']}
        changed_anchors=0
        for stage in stages:
            history=stage['historicalBattlefield']
            history['ambushClearings']=clearings[stage['id']]
            for mission,point in shard.get('stages',{}).get(stage['id'],{}).items():
                if mission not in history.get('learningSupportAnchors',{}): raise SystemExit('Refuse finalization: unknown original mission '+mission)
                history['learningSupportAnchors'][mission].update(rec(xy(point)))
                changed_anchors+=1
        if changed_anchors!=9: raise SystemExit('Refuse finalization: expected exactly nine original mission anchors')
        draft.write_text(json.dumps(stages,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        manifest_path=PROFILE/'layout-transform-manifest.json'
        manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
        manifest['verifiedGeometrySha256']=geometry_hash
        manifest['draftMapsSha256']=hashlib.sha256(draft.read_bytes()).hexdigest()
        manifest['learningAnchorShard']=str(args.finalize.resolve())
        manifest['learningMissionAnchorUpdates']=changed_anchors
        manifest['actualGeometryChecks']=proof['checks']
        for old,new,record in zip(original,stages,manifest['stages']):
            record['zoneMapping']=[{'id':nz['id'],'old':dict(rec(xy(oz)),r=oz['r']),'new':dict(rec(xy(nz)),r=nz['r'])} for oz,nz in zip(old['buildZones'],new['buildZones'])]
        manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print('Finalized private maps, rerun actual CPU before commit:',manifest['draftMapsSha256'])
        return
    if args.commit:
        draft=PROFILE/'maps-lower-draft.json'
        verification=json.loads((PROFILE/'runtime-verification.json').read_text(encoding='utf-8'))
        if verification.get('failures') or not verification.get('passed') or verification.get('draftSha256')!=hashlib.sha256(draft.read_bytes()).hexdigest(): raise SystemExit('Refuse commit: actual runtime verification does not match draft')
        if hashlib.sha256(SOURCE.read_bytes()).hexdigest()!=source_hash: raise SystemExit('Refuse commit: production maps changed since baseline')
        SOURCE.write_bytes(draft.read_bytes())
        print('Committed validated maps SHA256',hashlib.sha256(SOURCE.read_bytes()).hexdigest())
        return
    records=[];stages=[]
    for stage in original:
        try:
            built,record=build(stage)
        except ValueError as problem:
            if 'No full clear emplacement' not in str(problem): raise
            built=record=None
            for cap in [.075,.065,.055]:
                trial=copy.deepcopy(stage)
                for zone in trial['buildZones']: zone['r']=min(float(zone['r']),cap)
                try:
                    built,record=build(trial)
                    record['emplacementRadiusCap']=cap
                    record['zoneMapping']=[{'id':new['id'],'old':dict(rec(xy(old)),r=old['r']),'new':dict(rec(xy(new)),r=new['r'])} for old,new in zip(stage['buildZones'],built['buildZones'])]
                    break
                except ValueError as retry:
                    if 'No full clear emplacement' not in str(retry): raise
            if built is None: raise problem
        stages.append(built);records.append(record)
        (PROFILE/'draft-progress.json').write_text(json.dumps({'stages':stages,'records':records},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print('Draft',stage['stageNumber'],stage['id'],'quarter',record['sourceQuarterTurns'],'paths',len(stage['paths']),flush=True)
    draft=PROFILE/'maps-lower-draft.json'
    draft.write_text(json.dumps(stages,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    manifest={'version':1,'sourceMapsSha256':source_hash,'draftMapsSha256':hashlib.sha256(draft.read_bytes()).hexdigest(),'scope':'canonical source redesign; never rotate raster output vertically','stageCount':len(stages),'stages':records}
    (PROFILE/'layout-transform-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Draft ready SHA256',manifest['draftMapsSha256'])

if __name__=='__main__': main()
