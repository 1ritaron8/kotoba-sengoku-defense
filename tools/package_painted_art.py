"""Register generated PNG frames without drawing, recoloring, or warping them."""
from pathlib import Path
from PIL import Image
import json
import copy
import hashlib
import numpy as np
import argparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--manifest-only', action='store_true',
                    help='Update the manifest without rewriting the legacy registration measurements.')
args = parser.parse_args()

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'assets/characters/painted-v1'
manifest = {
    'version': 'painted-v1', 'bodyHeightScreen': 44,
    'camera': 'fixed elevated quarter view; directional source poses',
    'animationScope': 'authored four-diagonal idle/attack where action atlases are registered; retained NE/SW walk poses; other role/action sets remain pending',
    'frames': {}, 'factions': {'enemy': {'frames': {}}},
    'roleAliases': {'raider': 'spear', 'shield': 'spear', 'heavy': 'samurai',
                    'enemy_samurai': 'samurai', 'enemy_archer': 'archer',
                    'enemy_gunner': 'gunner', 'enemy_commander': 'commander',
                    'enemy_cavalry': 'cavalry'},
}
measurements = []

def register(name, texture, row, cuts_x, cuts_y, body_height, faction='friendly', single_sw=False):
    im = Image.open(ASSETS / texture).convert('RGBA')
    data = {'texture': 'res://assets/characters/painted-v1/' + texture,
            'bodyHeightPixels': body_height}
    for direction, columns in [('ne', [0, 1]), ('sw', [2, 3])]:
        frames = []
        if len(cuts_x) == 3:
            columns = [0, 1]
            use_row = 0 if direction == 'ne' else 1
        else:
            use_row = row
        if single_sw and direction == 'sw': columns = [0]
        for col in columns:
            rect = (cuts_x[col], cuts_y[use_row], cuts_x[col+1], cuts_y[use_row+1])
            cell = im.crop(rect)
            alpha = cell.getchannel('A')
            solid = alpha.point(lambda value: 255 if value >= 128 else 0)
            bounds = solid.getbbox()
            if bounds is None: raise ValueError((name, direction, col, 'empty'))
            # The lower band is used solely as an explicit source registration
            # proxy. It is not an anatomical or gait-quality acceptance test.
            lower_y = max(bounds[1], bounds[3]-max(4, int(body_height*.10)))
            lower = solid.crop((0, lower_y, cell.width, bounds[3])).getbbox()
            foot_x = (lower[0]+lower[2])*.5 if lower else cell.width*.5
            record = {'rect': [rect[0], rect[1], cell.width, cell.height],
                      'anchor': [foot_x, bounds[3]-1]}
            frames.append(record)
            measurements.append({'role':name,'faction':faction,'direction':direction,
                                 'rect':record['rect'],'solidBounds':bounds,
                                 'anchor':record['anchor'],'bodyHeightPixels':body_height})
        data[direction] = {'walk': frames, 'fps': 5.0}
    target = manifest['frames'] if faction == 'friendly' else manifest['factions']['enemy']['frames']
    target[name] = data


def register_actions(name, texture, cuts_x, cuts_y, body_height, faction='friendly', action='attack'):
    """Register four authored directions and idle/draw/release/recovery.

    Body height is fixed for the whole role/atlas, never inferred per frame.
    The existing directional walking source is retained separately.
    """
    im = Image.open(ASSETS / texture).convert('RGBA')
    target = manifest['frames'] if faction == 'friendly' else manifest['factions']['enemy']['frames']
    role = target[name]
    row_specific = isinstance(cuts_x[0], (list, tuple))
    assert (len(cuts_x) == 4 if row_specific else len(cuts_x) == 5) and len(cuts_y) == 5
    for row, direction in enumerate(['ne', 'se', 'sw', 'nw']):
        row_cuts = cuts_x[row] if row_specific else cuts_x
        assert len(row_cuts) == 5
        frames = []
        for col, state in enumerate(['idle', 'windup', 'release', 'recovery']):
            x0, x1 = row_cuts[col], row_cuts[col+1]
            y0, y1 = cuts_y[row], cuts_y[row+1]
            cell = im.crop((x0, y0, x1, y1))
            alpha = cell.getchannel('A')
            solid = alpha.point(lambda value: 255 if value >= 128 else 0)
            bounds = solid.getbbox()
            if bounds is None: raise ValueError((name, direction, state, 'empty action'))
            lower_y = max(bounds[1], bounds[3]-max(4, int(body_height*.10)))
            lower = solid.crop((0, lower_y, cell.width, bounds[3])).getbbox()
            frame = {'rect': [x0, y0, x1-x0, y1-y0],
                     'anchor': [(lower[0]+lower[2])*.5, bounds[3]-1]}
            frames.append(frame)
            measurements.append({'role': name, 'faction': faction, 'direction': direction,
                                 'state': state, 'texture': texture, 'rect': frame['rect'],
                                 'solidBounds': bounds, 'anchor': frame['anchor'],
                                 'bodyHeightPixels': body_height})
        record = role.setdefault(direction, {})
        common = {'texture': 'res://assets/characters/painted-v1/'+texture,
                  'bodyHeightPixels': body_height}
        record['idle'] = {**common, 'frames': [frames[0]], 'fps': 1.0}
        record['aim'] = {**common, 'frames': [frames[1]], 'fps': 1.0}
        record['recover'] = {**common, 'frames': [frames[3]], 'fps': 1.0}
        record[action] = {**common, 'frames': frames, 'fps': 8.0,
                            'releaseFrame': 2, 'requiresCommittedRelease': True}
    role['actionScope'] = 'four authored diagonal idle/aim/'+action+'/recover directions; gait availability separately registered'

# Boundaries follow actual transparent gaps; generated canvases are not always
# divisible by four. In particular, archer feet end below a nominal quarter.
x = [0, 314, 627, 941, 1254]
y = [0, 314, 640, 943, 1254]
for row, name in enumerate(['spear', 'archer', 'gunner', 'samurai']):
    register(name, 'allies.png', row, x, y, [240,244,245,255][row])
for row, name in enumerate(['spear', 'archer', 'gunner', 'runner']):
    register(name, 'enemies.png', row, x, y, [240,244,245,250][row], 'enemy')
sx = [0, 362, 724, 1086, 1448]
sy = [0, 394, 709, 1086]
register('monk','specialists-spaced.png',0,sx,sy,270)
register('ninja','specialists-spaced.png',1,sx,sy,280)
register('samurai','specialists-spaced.png',2,sx,sy,300,'enemy')
# Stage01's real boss is a foot commander. Register its red-armored source
# explicitly; it must neither disappear nor borrow the allied navy cavalry.
register('commander','specialists-spaced.png',2,sx,sy,300,'enemy')
manifest['factions']['enemy']['frames']['commander']['visualRole'] = 'red_armored_foot_general'
manifest['factions']['enemy']['frames']['commander']['sourceReuse'] = 'existing_painted_enemy_samurai'
manifest['pendingRoles'] = {'enemy_cavalry': {
    'role': 'cavalry', 'implementationStatus': 'approved_asset_not_available',
    'note': 'Distinct mounted role; not substituted with a foot commander or friendly mount.',
}}
# The bottom-right generated mount faces SE and is deliberately not used as SW.
# Preserve the honest single-pose limit instead of flipping equipment/identity.
register('commander','mounted-final.png',0,[0,627,1254],[0,627,1254],430,single_sw=True)
mount_b = Image.open(ASSETS/'mounted-sw-b.png').convert('RGBA')
solid_b = mount_b.getchannel('A').point(lambda value:255 if value>=128 else 0)
bounds_b = solid_b.getbbox()
lower_b = solid_b.crop((0,bounds_b[3]-43,mount_b.width,bounds_b[3])).getbbox()
record_b = {'texture':'res://assets/characters/painted-v1/mounted-sw-b.png',
            'rect':[0,0,mount_b.width,mount_b.height],
            'anchor':[(lower_b[0]+lower_b[2])*.5,bounds_b[3]-1]}
manifest['frames']['commander']['sw']['walk'].append(record_b)
measurements.append({'role':'commander','faction':'friendly','direction':'sw',
                     'rect':record_b['rect'],'solidBounds':bounds_b,
                     'anchor':record_b['anchor'],'bodyHeightPixels':430})
# Actual transparent gaps from alpha>=128 connected components. Helmet-to-foot
# body height is approximately208–216px; bow height is not the body scale.
register_actions('archer','archer-actions-padded.png',
                 [0,314,647,961,1254],[0,332,632,913,1254],212)
# Spear thrusts cross nominal quarter boundaries. Row-specific cuts preserve
# their complete weapon silhouettes, using actual connected-component gaps.
# Fixed224px standing-body calibration excludes the long spear and crouching.
register_actions('spear','spear-actions.png',
                 [[0,329,628,999,1254],[0,326,625,1007,1254],
                  [0,304,592,988,1254],[0,312,605,980,1254]],
                 [0,344,648,940,1254],224)
# Rust armor counterparts retain the same authored four directions. Their
# connected opaque silhouettes were inspected independently before reuse of
# these real transparent-gap cuts (smallest opaque frame margin: 8px).
register_actions('archer','enemy-archer-actions.png',
                 [0,314,647,961,1254],[0,332,632,913,1254],212,'enemy')
register_actions('spear','enemy-spear-actions.png',
                 [[0,329,628,999,1254],[0,326,625,1007,1254],
                  [0,304,592,988,1254],[0,312,605,980,1254]],
                 [0,344,648,940,1254],224,'enemy')

def transparent_cuts(texture):
    """Choose cuts only in actual alpha<=16 antialias gutters; never repaint the source."""
    image = Image.open(ASSETS/texture).convert('RGBA')
    opaque = np.asarray(image.getchannel('A'))>16
    height,width = opaque.shape
    def gap(n,k,occupied):
        available=[i for i in range(max(1,int(n*k/4)-70),min(n-1,int(n*k/4)+70)) if not occupied(i)]
        if not available: raise ValueError((texture,'no transparent cell boundary',k))
        return min(available,key=lambda i:abs(i-n*k/4))
    ys=[0]+[gap(height,k,lambda i:opaque[i].any()) for k in range(1,4)]+[height]
    xs=[]
    for row in range(4):
        band=opaque[ys[row]:ys[row+1]]
        xs.append([0]+[gap(width,k,lambda i:band[:,i].any()) for k in range(1,4)]+[width])
    return xs,ys

for role,texture,body,action in [
    ('gunner','gunner-actions-v2.png',270,'attack'),
    ('samurai','samurai-actions-padded-v2.png',260,'attack'),
    ('monk','monk-actions-padded-v2.png',200,'heal'),
    ('ninja','ninja-actions-v2.png',260,'attack'),
    ('commander','commander-actions-v2.png',235,'attack')]:
    cx,cy=transparent_cuts(texture)
    register_actions(role,texture,cx,cy,body,action=action)

# Manual release landmarks refer to unmodified source pixels. Bow origin is
# the gripping hand, rifle origin the muzzle, spear origin the shaft near tip.
release_landmarks={
    'spear':{'ne':([342,60],[356,52]),'se':([353,146],[369,147]),'sw':([31,133],[14,133]),'nw':([32,49],[17,41])},
    'archer':{'ne':([222,151],[242,146]),'se':([232,134],[252,139]),'sw':([87,135],[67,140]),'nw':([77,110],[57,100])},
    'gunner':{'ne':([286,54],[306,50]),'se':([300,81],[310,81]),'sw':([27,61],[7,59]),'nw':([37,39],[17,34])},
}
for faction,roles in [('friendly',manifest['frames']),('enemy',manifest['factions']['enemy']['frames'])]:
    for role,directions in release_landmarks.items():
        for direction,(origin,tip) in directions.items():
            attack=roles.get(role,{}).get(direction,{}).get('attack')
            if not attack:continue
            # Enemy rifle is still the old walking atlas; no invented muzzle.
            frame=attack['frames'][attack['releaseFrame']]
            frame['landmarks']={'weaponOrigin':origin,'weaponTip':tip}
            frame['landmarkRegistration']='manual visible grip/muzzle/shaft; direction axis follows source'

motion=json.loads((ASSETS/'motion-registration.json').read_text(encoding='utf-8'))
for faction,roles,texture in [('friendly',manifest['frames'],'spear-actions.png'),('enemy',manifest['factions']['enemy']['frames'],'enemy-spear-actions.png')]:
    for direction,source in motion['spearRigs'].items():
        rig=copy.deepcopy(motion.get('enemySpearRigOverrides',{}).get(direction,source) if faction=='enemy' else source)
        rig['texture']='res://assets/characters/painted-v1/'+texture
        record=roles['spear'][direction]
        record['rig']=rig
        record['idle']['frames'][0]['anchor']=rig['anchor']
        # A real directional source seeds UV drawing; never borrow NE for SE.
        record['walk']={**copy.deepcopy(record['idle']), 'strideBodyHeights':rig['strideBodyHeights'],
                        'gaitVerified':False,'renderTechnique':'painted-source-uv-rig'}
        record['idle']['frames'][0].setdefault('landmarks',{})['pelvis']=rig['pelvis']
        record['idle']['frames'][0]['landmarks'].update({side+'Foot':rig['parts'][side+'Foot']['end'] for side in ['left','right']})
for role_key,directions in motion.get('humanoidRigs',{}).items():
    faction,role=role_key.split('/')
    roles=manifest['frames'] if faction=='friendly' else manifest['factions']['enemy']['frames']
    for direction,rig in directions.items():
        record=roles[role][direction]
        if 'idle' not in record:
            source=copy.deepcopy(record['walk'][0])
            record['idle']={'texture':rig['texture'],'bodyHeightPixels':rig['bodyHeightPixels'],'frames':[source],'fps':1.0,'sourceStatus':'single retained walk pose; not authored idle animation'}
        record['rig']=copy.deepcopy(rig)
        if rig.get('groundedIdle', False):
            for frame in record['idle']['frames']:
                if frame.get('rect') == rig['rect']:
                    frame['anchor'] = copy.deepcopy(rig['anchor'])
        record['walk']={**copy.deepcopy(record['idle']),'strideBodyHeights':rig['strideBodyHeights'],'gaitVerified':False,'renderTechnique':'painted-source-uv-rig'}
for direction,rig in motion.get('quadrupedRigs',{}).items():
    record=manifest['frames']['commander'][direction]
    record['rig']=copy.deepcopy(rig)
    record['walk']={**copy.deepcopy(record['idle']),'strideBodyHeights':rig['strideBodyHeights'],'gaitVerified':False,'renderTechnique':'painted-source-quadruped-uv-rig'}
if motion.get('quadrupedRigs'):
    cavalry=copy.deepcopy(manifest['frames']['commander'])
    for direction in ['ne','se','sw','nw']:
        cavalry[direction]['rig']['temporarySourceReuse']=True
    cavalry['sourceStatus']='TEMPORARY: exact existing allied mounted commander texture/palette; distinct hostile cavalry art not supplied'
    manifest['factions']['enemy']['frames']['cavalry']=cavalry
    manifest['pendingRoles']={'enemy_cavalry':{'implementationStatus':'temporary_existing_mount_reuse','distinctEnemyArt':False}}
manifest['motionLimitations']=motion.get('unsupportedMotion',{})
if motion.get('sourceRestSoleRepair'):
    manifest['sourceRestSoleRepair']=copy.deepcopy(motion['sourceRestSoleRepair'])
if motion.get('locomotionRepair02'):
    manifest['locomotionRepair02']=copy.deepcopy(motion['locomotionRepair02'])
manifest['animationScope']='Existing source-specific humanoid and quadruped UV motion; original four-direction allied action atlases. New UV registration and procedural hit/death require rendered acceptance; missing enemy action art remains explicit.'
manifest['gaitAcceptance']={'status':'actual_engine_review_required','registeredRigRoles':['friendly/spear','enemy/spear']+list(motion.get('humanoidRigs',{}))+['friendly/commander','enemy/cavalry'],'notAcceptedBy':['unique PNG hashes','metadata count','timing trace alone']}

manifest['pendingAuthoredActions'] = [
    {'faction': faction, 'role': role, 'states': ['idle','heal' if role=='monk' else 'attack'],
     'directions': ['ne','se','sw','nw'], 'status': 'not_authored'}
    for faction, records in [('friendly',manifest['frames']),
                             ('enemy',manifest['factions']['enemy']['frames'])]
    for role, record in records.items()
    if not all(direction in record and ('heal' if role=='monk' else 'attack') in record[direction]
               and 'idle' in record[direction] for direction in ['ne','se','sw','nw'])
]
manifest['pendingWalkDirections'] = [
    {'faction':faction,'role':role,'directions':[d for d in ['ne','se','sw','nw'] if 'rig' not in record.get(d,{})]}
    for faction,records in [('friendly',manifest['frames']),('enemy',manifest['factions']['enemy']['frames'])]
    for role,record in records.items() if any('rig' not in record.get(d,{}) for d in ['ne','se','sw','nw'])
]
manifest['structures'] = {'fortification': {
    'texture': 'res://assets/painted-battlefield/enemy-firing-platform.png',
    'rect': [351, 139, 657, 853], 'anchor': [329, 851],
    'bodyHeightPixels': 853, 'bodyHeightScreen': 78,
    'crewOffset': [38, -420],
    'healthContract': 'same settled enemy ID and HP; no separate decorative target',
}}
manifest['sourceHashes']={path.name:hashlib.sha256(path.read_bytes()).hexdigest() for path in ASSETS.glob('*.png')}
(ASSETS/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
evidence = ASSETS/'asset-registration.json'
if not args.manifest_only:
    evidence.write_text(json.dumps(measurements,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'friendlyRoles':list(manifest['frames']),
                  'enemyRoles':list(manifest['factions']['enemy']['frames']),
                  'registeredFrames':len(measurements)},ensure_ascii=False))
