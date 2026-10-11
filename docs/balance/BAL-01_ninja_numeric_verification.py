"""BAL-01-REV4 proposed arithmetic and lifecycle model; never imports/runs the game.

This verifies design fixtures, not Godot hook implementation, GPU, or player saves.
Run from any directory: python docs/balance/BAL-01_ninja_numeric_verification.py
"""
from pathlib import Path
import hashlib
import json
import math

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ["native/units.json", "native/unit_growth.gd", "native/unit_skills.gd",
           "native/game.gd", "native/ground_combat.gd", "assets/units-animated/manifest.json"]
HASHES = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in SOURCES}
NINJA = next(u for u in json.loads((ROOT / SOURCES[0]).read_text(encoding="utf-8-sig"))["units"] if u["id"] == "ninja")
CHECKS = []


def check(label, passed):
    CHECKS.append({"name": label, "passed": bool(passed)})
    if not passed:
        raise AssertionError(label)


def close(label, actual, expected):
    check(label, math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-9))


def stats(level):
    evolution = {"stage": 0, "damageMultiplier": 1, "rangeMultiplier": 1, "intervalMultiplier": 1}
    for candidate in NINJA["evolutions"]:
        if level >= candidate["level"]:
            evolution = candidate
    damage = NINJA["damage"] * (1 + .08 * (level - 1)) * evolution["damageMultiplier"]
    health = NINJA["hp"] * (1 + .05 * (level - 1)) * (1.25 if evolution["stage"] >= 2 else 1.12 if evolution["stage"] == 1 else 1)
    interval = max(.25, NINJA["interval"] * evolution["intervalMultiplier"] / (1 + .015 * (level - 1)))
    armor = min(.65, .10 + .006 * (level - 1))
    attack_range = NINJA["range"] * (1 + .012 * (level - 1)) * evolution["rangeMultiplier"]
    return dict(level=level, damage=damage, health=health, interval=interval, armor=armor,
                range=attack_range, raw_dps=damage / interval)


# REV4 design constants; isolated specification only, no production activation.
COMBO_FACTORS = (1.0, .5, .5)
COMBO_PHASES = (.25, .55, .85)
BOMB_FACTOR = 4.0
BOMB_FUSE = .75
SHRAPNEL_FACTOR = .60
SHRAPNEL_RADIUS = .065
SHRAPNEL_LIMIT = 4
CHECKS = []
ANIMATION = json.loads((ROOT / SOURCES[5]).read_text(encoding='utf-8-sig'))


def attack_duration(level):
    attack = ANIMATION['animations']['attack']
    return min(attack['frames'] / attack['fps'], .95 * stats(level)['interval'])


def melee(damage, armor, hp, max_hp, factor=1.0, armor_break=False):
    effective_armor = armor * (.65 if armor_break else 1)
    execution = 1.5 if hp <= max_hp * .30 else 1
    return min(hp, damage * factor * execution * (1 - effective_armor))


def combo(level, hp, max_hp, armor, armor_break=False):
    damage = stats(level)['damage']
    impacts = []
    for factor in COMBO_FACTORS:
        if hp <= 0:
            break
        hit = melee(damage, armor, hp, max_hp, factor, armor_break)
        hp -= hit
        impacts.append(hit)
    return dict(impacts=impacts, hp_after=hp, total=sum(impacts))


def bomb_limit(level, base_armor):
    # Conservative threshold excludes execution, armor break and future buffs.
    return BOMB_FACTOR * stats(level)['damage'] * (1-base_armor)


class Mission:
    """Fixture model: validity/swept route come from supplied inputs, not Godot."""
    def __init__(self, actor=1, level=8, target=10, generation=1):
        self.actor, self.level, self.target, self.generation = actor, level, target, generation
        self.alive = True
        self.ended = False
        self.refund = 0
        self.combo_used = False
        self.combo_complete = False
        self.plant_attempted = False
        self.seen = set()
        self.preparing_combo = False

    def begin_combo(self, valid=True):
        if self.target is None:
            self.ended = True
            return False
        if self.level < 5 or self.combo_used or self.ended or not self.alive or not valid:
            return False
        self.combo_used = True  # reserve whole opening sequence before events
        self.preparing_combo = True
        return True

    def combo_hit(self, attack, index, hp, max_hp, armor, valid=True, safe=True, generation=1):
        key = (generation, self.actor, self.target, attack, index)
        if generation != self.generation or key in self.seen or self.ended or not self.alive or not self.preparing_combo:
            return hp
        if not valid or not safe:
            self.ended = True
            return hp
        self.seen.add(key)
        hp -= melee(stats(self.level)['damage'], armor, hp, max_hp, COMBO_FACTORS[index])
        if hp <= 0:
            self.ended = True
            self.preparing_combo = False
        if index == 2:
            self.preparing_combo = False
            self.combo_complete = True
        return hp

    def plant(self, hp, armor, ledger, now, valid=True, safe=True, generation=1, damage_snapshot=None):
        charge_key = (generation, self.actor, self.target)
        if self.ended or not self.alive or generation != self.generation or self.level < 2 or self.preparing_combo or self.plant_attempted:
            return False
        if not valid or not safe or self.target is None or hp <= 0:
            self.ended = True
            return False
        if self.level >= 5 and not self.combo_complete:
            return False
        self.plant_attempted = True
        damage = stats(self.level)['damage'] if damage_snapshot is None else damage_snapshot
        if charge_key in ledger:
            return False  # replay of this source's committed charge, not a target-wide cap
        ledger[charge_key] = dict(source=self.actor, target=self.target, generation=generation,
                                  explode_at=now+BOMB_FUSE, raw_damage=BOMB_FACTOR*damage,
                                  committed=True, source_end='charge_planted', level=self.level,
                                  explosion_id=f'g{generation}:n{self.actor}:t{self.target}:bomb1', center=(0,0), seen=False)
        self.ended = True  # completed sabotage consumes actor, payload remains
        return True


def fragment_hits(payload, candidates, seen, current_generation=1, read_generation=None):
    if payload['level'] < 8:
        return []
    origin = payload['center']
    eligible = []
    for enemy in candidates:
        distance = math.hypot(enemy['position'][0]-origin[0], enemy['position'][1]-origin[1])
        if enemy['id'] == payload['target'] or enemy.get('role') != 'path_assault' or enemy['hp'] <= 0 or enemy.get('escaped',False):
            continue
        if enemy.get('stationary', False) or enemy.get('fortification', False) or not enemy.get('ground', True) or enemy.get('sailing', False):
            continue
        if not enemy.get('safe_segment', True) or distance > SHRAPNEL_RADIUS or enemy.get('generation', 1) != payload['generation']:
            continue
        eligible.append((distance, enemy['id'], enemy))
    eligible.sort(key=lambda row: (row[0], row[1]))
    selected = eligible[:SHRAPNEL_LIMIT]  # immutable ordered identities, not new targets after a callback
    results = []
    for _, _, enemy in selected:
        active_generation = current_generation if read_generation is None else read_generation()
        if active_generation != payload['generation']:
            break
        identity = (payload['explosion_id'], enemy['id'])
        distance = math.hypot(enemy['position'][0]-origin[0],enemy['position'][1]-origin[1])
        if identity in seen or enemy['hp'] <= 0 or enemy.get('escaped',False) or enemy.get('role') != 'path_assault' or not enemy.get('safe_segment', True):
            continue
        if distance > SHRAPNEL_RADIUS or enemy.get('stationary',False) or enemy.get('fortification',False) or enemy.get('sailing',False) or not enemy.get('ground',True):
            continue
        seen.add(identity)  # commit once before external events
        armor = enemy['armor'] * (.65 if enemy.get('armor_break', False) else 1)
        damage = min(enemy['hp'], payload['raw_damage'] / BOMB_FACTOR * SHRAPNEL_FACTOR * (1-armor))
        enemy['hp'] -= damage
        results.append(dict(target=enemy['id'], damage=damage))
    return results


def explode(ledger, key, now, hp, armor, current_generation=1, target_exists=True, same_identity=True, role_valid=True,
            armor_break=False, candidates=None, fragment_results=None, seen=None, read_generation=None, battle_active=True, target_position=None):
    payload = ledger.get(key)
    if payload is None or now < payload['explode_at']:
        return 0
    if payload['seen']:
        return 0
    payload['seen'] = True  # commit before notification/reentry
    if not battle_active or payload['source_end'] != 'charge_planted' or payload['generation'] != current_generation or not target_exists or not same_identity or not role_valid or hp <= 0:
        ledger.pop(key, None)
        return 0
    if target_position is not None:
        payload['center'] = target_position  # attached identity; actual detonation location
    effective_armor = armor * (.65 if armor_break else 1)
    damage = min(hp, payload['raw_damage']*(1-effective_armor))
    # Tower dying from this very explosion does NOT cancel its shrapnel.
    if candidates is not None:
        result = fragment_hits(payload, candidates, set() if seen is None else seen, current_generation, read_generation)
        if fragment_results is not None:
            fragment_results.extend(result)
    ledger.pop(key, None)
    return damage


def choose_strongest(candidates):
    eligible = [e for e in candidates if e.get('valid',True) and e.get('reachable',True)
                and e.get('ground',True) and not e.get('sailing',False) and not e.get('escaped',False)
                and e.get('role') in ['path_assault','emplacement_assault'] and e['hp']>0]
    return min(eligible,key=lambda e:(-e['damage'],-e['maxHp'],-e['armor'],e['travel'],e['id'])) if eligible else None


def ready_mission(level=8, **kwargs):
    # Explicit isolated state fixture: the source actor has already finished3 hits.
    m=Mission(level=level,**kwargs)
    if level>=5:
        m.combo_used=True;m.combo_complete=True
    return m


def mission_sample(level,hp,armor):
    damage=stats(level)['damage'];interval=stats(level)['interval'];duration=attack_duration(level)
    remaining=hp;impacts=[];plant_at=None
    if level>=5:
        for factor,phase in zip(COMBO_FACTORS,COMBO_PHASES):
            actual=melee(damage,armor,remaining,hp,factor)
            remaining-=actual;impacts.append(dict(at=phase*duration,damage=actual))
            if remaining<=0:
                return dict(level=level,hp=hp,armor=armor,finish='combo_kill_no_charge',knife_damage=sum(r['damage'] for r in impacts),
                            primary_damage=hp,primary_hp_after=0,actor_exit_at=phase*duration,damage_complete_at=phase*duration)
        plant_at=interval+.5*duration
    elif level>=2:
        plant_at=.5*duration
    else:
        cycles=0
        while remaining>0:
            cycles+=1;remaining-=melee(damage,armor,remaining,hp)
        time=(cycles-1)*interval+.5*duration
        return dict(level=level,hp=hp,armor=armor,finish='baseline_repeat_melee',primary_damage=hp,primary_hp_after=0,actor_exit_at=time,damage_complete_at=time)
    bomb=min(remaining,BOMB_FACTOR*damage*(1-armor))
    remaining-=bomb
    return dict(level=level,hp=hp,armor=armor,finish='charge',knife_damage=sum(r['damage'] for r in impacts),bomb_damage=bomb,
                primary_damage=hp-remaining,primary_hp_after=remaining,actor_exit_at=plant_at,damage_complete_at=plant_at+BOMB_FUSE)


def candidate(identity,distance=.03,role='path_assault',hp=100,armor=.38,**flags):
    return dict(id=identity,position=(distance,0),role=role,hp=hp,armor=armor,**flags)



check('51/160 baseline no enabled skills',NINJA['damage']==51 and NINJA['hp']==160 and NINJA['skillUnlocks']==[])
growth=(ROOT/SOURCES[1]).read_text(encoding='utf-8-sig');game=(ROOT/SOURCES[3]).read_text(encoding='utf-8-sig')
check('source growth replacement','(1.0+.08*(permanent_level-1))*float(evolved.damageMultiplier)' in growth)
check('source prehit execution','float(enemy.hp) <= float(enemy.maxHp)*0.30' in game)
check('source threat grade5','damage = 5' in game)
check('source samurai uses emplacement role','"enemy_samurai"' in game and 'ENEMY_EMPLACEMENT_ROLE' in game)
close('Lv2 D baseline',stats(2)['damage'],55.08)
close('Lv5 D baseline',stats(5)['damage'],75.3984)
close('Lv8 highest evolution only',stats(8)['damage'],103.428)
close('Lv2 bomb raw4D',stats(2)['damage']*BOMB_FACTOR,220.32)
close('Lv8 bomb raw4D',stats(8)['damage']*BOMB_FACTOR,413.712)
# Source-faithful spawn samples: difficulty1, maxHP=(32+10s)*origin multiplier.
def ranked(identity,kind,wave,origin,travel=.1,**flags):
    hp_factor,damage,armor={'raider':(1,1,0),'runner':(.7,1,0),'shield':(1.65,2,.38),'heavy':(2.2,3,.25),'commander':(6,5,.3)}[origin]
    hp=(32+wave*10)*hp_factor
    return dict(id=identity,kind=kind,damage=damage,maxHp=hp,hp=hp,armor=armor,travel=travel,
                role='emplacement_assault' if kind in ['enemy_samurai','enemy_archer','enemy_gunner'] else 'path_assault',**flags)
samurai=ranked(1,'enemy_samurai',5,'heavy');cavalry=ranked(2,'enemy_cavalry',9,'runner');tower=ranked(3,'enemy_archer',3,'raider',stationary=True)
check('samurai wins source threat grade',choose_strongest([tower,cavalry,samurai])['id']==1)
blocked=dict(samurai,reachable=False)
check('cavalry wins when strong samurai unreachable',choose_strongest([blocked,cavalry,tower])['id']==2)
strong_tower=ranked(4,'enemy_gunner',6,'heavy',stationary=True)
check('strong tower wins maxHP samegrade',choose_strongest([samurai,cavalry,strong_tower])['id']==4)
check('current HP wounds do not rerank',choose_strongest([dict(samurai,hp=1),cavalry,tower])['id']==1)
commander=ranked(5,'commander',4,'commander')
check('commander strongest no instantkill bonus',choose_strongest([strong_tower,commander])['id']==5)
for flag in ['valid','reachable','ground']:
    check('invalid strongest excluded '+flag,choose_strongest([dict(commander,**{flag:False}),samurai])['id']==1)
check('all invalid no target',choose_strongest([dict(commander,hp=0),dict(samurai,escaped=True)]) is None)
check('friendly not assassination candidate',choose_strongest([dict(commander,role='friendly'),samurai])['id']==1)
check('armor breaks rank tie',choose_strongest([dict(samurai,id=7,armor=.1),dict(samurai,id=8,armor=.25)])['id']==8)
check('travel breaks numeric tie',choose_strongest([dict(samurai,id=7,travel=.2),dict(samurai,id=8,travel=.1)])['id']==8)
check('actorID final tie',choose_strongest([dict(samurai,id=8),dict(samurai,id=7)])['id']==7)
# Straight authored-lane fixture only; real full-footprint tracking is later QA.
speed=.052*1.4;enemy_speed=(.020+9*.00035)*1.5;contact=.031*.95
approach_time=(.10-contact)/(speed-enemy_speed)
check('moving cavalry catch-up possible in same lane',approach_time>0 and .10+enemy_speed*approach_time<.30)
close('moving target chase uses base speed',speed,.0728)
check('cannot guarantee contact with faster target',.09>speed)
# Lv2 plants immediately even healthy; no weakened-target or oneshot substitution.
m=Mission(level=2);ledger={}
check('healthy2000 target no lowHP gate',m.plant(2000,.38,ledger,0) and m.ended)
close('healthy enemy partial bomb damage',explode(ledger,(1,1,10),1,2000,.38),136.5984)
check('Lv1 cannot plant',not Mission(level=1).plant(10,.38,{},0))
check('Lv2 no combo',not Mission(level=2).begin_combo())
check('Lv5 must actually complete combo before plant',not Mission(level=5).plant(2000,.38,{},0))
m=Mission(level=5);hp=1000
check('Lv5 begins combo once',m.begin_combo() and not m.begin_combo())
for index in range(3):
    prior=hp;hp=m.combo_hit('opening',index,hp,1000,.38)
    close('same impact replay '+str(index),m.combo_hit('opening',index,hp,1000,.38),hp)
    check('each real subhit applied '+str(index),hp<prior)
check('threehit then plant completed',m.combo_complete and m.plant(hp,.38,{},1))
close('Lv5 combo highHP2D',combo(5,1000,1000,.38)['total'],93.494016)
cross=combo(5,100,100,.38)
close('first hit unboosted before30%',cross['impacts'][0],46.747008)
close('second hit unboosted before30%',cross['impacts'][1],23.373504)
close('third evaluates fresh30% and caps HP',cross['impacts'][2],29.879488)
for level in [5,8,10]:
    duration=attack_duration(level);interval=stats(level)['interval']
    times=[duration*p for p in COMBO_PHASES]
    check('three distinct times within original cadence L'+str(level),0<times[0]<times[1]<times[2]<duration<interval)
    for armor in [0,.25,.38]:
        close('combo2D L'+str(level)+' a'+str(armor),combo(level,2000,2000,armor)['total'],2*stats(level)['damage']*(1-armor))
m=Mission(level=5);m.begin_combo();hp=m.combo_hit('a',0,5,100,.38)
check('lethal first cancels remaining combo/charge',m.ended and m.combo_hit('a',1,hp,100,.38)==0 and not m.plant(5,.38,{},0))
m=Mission(level=5);m.begin_combo();m.alive=False
close('death cancels followup',m.combo_hit('a',1,1000,1000,.38),1000)
check('preplant death leaves no charge',not m.plant(1000,.38,{},0))
for field in ['valid','safe']:
    m=Mission(level=5);m.begin_combo()
    close('invalid subhit '+field,m.combo_hit('a',0,1000,1000,.38,**{field:False}),1000)
    check('invalid subhit consumes '+field,m.ended and m.refund==0)
    m=ready_mission();ledger={}
    check('invalid plant '+field,not m.plant(1000,.38,ledger,0,**{field:False}) and not ledger and m.ended)
m=Mission(level=5);m.begin_combo()
close('stale generation subhit ignored',m.combo_hit('a',0,1000,1000,.38,generation=2),1000)
check('no target no combo',not Mission(level=5,target=None).begin_combo())
check('no target no plant',not Mission(level=2,target=None).plant(1000,.38,{},0))
ledger={};m=ready_mission();check('intentional charge commits',m.plant(2000,.38,ledger,10))
check('consumed actor cannot repeat plant',not m.plant(2000,.38,ledger,10))
close('no early explosion',explode(ledger,(1,1,10),10.749999,2000,.38),0)
close('committed bomb survives intentional consumed actor',explode(ledger,(1,1,10),10.75,2000,.38),256.50144)
close('duplicate explosion no damage',explode(ledger,(1,1,10),11,2000,.38),0)
ledger={};ready_mission().plant(2000,.38,ledger,0)
ledger[(1,1,10)]['source_end']='death'
close('ordinary death cannot preserve delayed payload',explode(ledger,(1,1,10),1,2000,.38),0)
ledger={};ready_mission().plant(2000,.38,ledger,0,damage_snapshot=stats(8)['damage']*1.2)
close('buff snapshot freezes raw',ledger[(1,1,10)]['raw_damage'],496.4544)
close('armor increases can reduce delayed damage',explode(ledger,(1,1,10),1,2000,.50),248.2272)
ledger={};ready_mission().plant(2000,.38,ledger,0)
close('heal/large HP no guaranteed kill',explode(ledger,(1,1,10),1,3000,.38),256.50144)
ledger={};ready_mission().plant(1000,.38,ledger,0)
for actor in range(2,102):
    other=ready_mission(actor=actor)
    check('distinct ninja plants and consumes '+str(actor),other.plant(1000,.38,ledger,.1) and other.ended)
    ledger_before=dict(ledger)
    check('consumed ninja no repeat '+str(actor),not other.plant(1000,.38,{},1) and ledger==ledger_before)
check('101 distinct charges share pinned target',len(ledger)==101 and len({p['explosion_id'] for p in ledger.values()})==101)
check('other identity may hold own charge',ready_mission(actor=102,target=11).plant(1000,.38,ledger,.1))
# Deterministic simultaneous payload order: first own blast may kill; later ones
# cancel on the now-dead identity and cannot emit orphan fragments or rewards.
ledger={};ready_mission(actor=1).plant(1000,.38,ledger,0);ready_mission(actor=2).plant(1000,.38,ledger,0)
fragments=[];victim=candidate(31,hp=1000)
close('first shared-target charge kills primary',explode(ledger,(1,1,10),1,100,.38,candidates=[victim],fragment_results=fragments),100)
close('later shared-target charge sees dead primary',explode(ledger,(1,2,10),1,0,.38,candidates=[victim],fragment_results=fragments),0)
check('shared-target kill one fragment set only',len(fragments)==1 and not ledger)
ledger={};ready_mission(actor=1).plant(1000,.38,ledger,0);ready_mission(actor=2).plant(1000,.38,ledger,0)
fragments=[];victim=candidate(31,hp=1000);hp=1000
for actor in [1,2]:
    hp-=explode(ledger,(1,actor,10),1,hp,.38,candidates=[victim],fragment_results=fragments)
close('surviving target takes two distinct bombs',hp,486.99712)
check('distinct explosions may each hit same advancing victim',len(fragments)==2)
close('two finite fragment hits',1000-victim['hp'],76.950432)
check('shared-target no charge after disposal',not ledger)
# Attached moving-target burst follows current position, not plant position.
ledger={};ready_mission().plant(1000,.38,ledger,0)
near_old=candidate(31,.02);near_new=candidate(32,.20)
fragments=[]
explode(ledger,(1,1,10),1,1000,.38,target_position=(.20,0),candidates=[near_old,near_new],fragment_results=fragments)
check('moving charge uses live explosion center',[r['target'] for r in fragments]==[32])
ledger={};ready_mission().plant(1000,.38,ledger,0);payload=dict(ledger[(1,1,10)])
foes=[candidate(10),candidate(20,role='emplacement_assault'),candidate(21,stationary=True),candidate(22,fortification=True),
      candidate(23,role='friendly'),candidate(24,role='objective'),candidate(25,sailing=True),candidate(26,ground=False),
      candidate(27,safe_segment=False),candidate(28,.066),candidate(29,hp=0),candidate(30,generation=2),candidate(31,.065),candidate(32,escaped=True)]
seen=set();results=fragment_hits(payload,foes,seen)
check('only legitimate advancing fragment victim',[r['target'] for r in results]==[31])
close('fragment armored without execution',results[0]['damage'],38.475216)
check('moving primary also excluded from fragment',[r['target'] for r in results]!=[10])
check('duplicate fragment no new damage',fragment_hits(payload,foes,seen)==[])
check('Lv5 has no fragments',fragment_hits(dict(payload,level=5),[candidate(31)],set())==[])
check('max4 closest ordered',[r['target'] for r in fragment_hits(payload,[candidate(i,.01+i*.001) for i in range(2,9)],set())]==[2,3,4,5])
check('equal distance sorted byid',[r['target'] for r in fragment_hits(payload,[candidate(i,.02) for i in [40,3,21,8,7]],set())]==[3,7,8,21])
close('fragment4target total2.4D',sum(r['damage'] for r in fragment_hits(payload,[candidate(i,.02,hp=1000,armor=0) for i in range(4)],set())),248.2272)
close('armor break once',fragment_hits(payload,[candidate(31,hp=1000,armor_break=True)],set())[0]['damage'],46.7287704)
for field in ['target_exists','same_identity','role_valid','battle_active']:
    ledger={};ready_mission().plant(1000,.38,ledger,0);fragments=[];enemy=candidate(31)
    close('primary cancelled '+field,explode(ledger,(1,1,10),1,1000,.38,candidates=[enemy],fragment_results=fragments,**{field:False}),0)
    check('no orphan fragments '+field,not fragments and enemy['hp']==100 and not ledger)
ledger={};ready_mission().plant(1000,.38,ledger,0);fragments=[]
close('ally killed target before fuse',explode(ledger,(1,1,10),1,0,.38,candidates=[candidate(31)],fragment_results=fragments),0)
check('ally kill no fragments',not fragments)
ledger={};ready_mission().plant(1000,.38,ledger,0);fragments=[]
close('old battle target ID reuse no damage',explode(ledger,(1,1,10),1,1000,.38,current_generation=2,candidates=[candidate(31)],fragment_results=fragments),0)
check('old battle no secondary',not fragments)
ledger={};ready_mission().plant(1000,.38,ledger,0);fragments=[]
close('own explosion kills primary once',explode(ledger,(1,1,10),1,100,.38,candidates=[candidate(31)],fragment_results=fragments),100)
check('own primary kill still emits fragments',len(fragments)==1)
epochs=[1,2]
def epoch():
    return epochs.pop(0) if epochs else 2
check('generation shift stops residual fragments',len(fragment_hits(payload,[candidate(31,.01),candidate(32,.02)],set(),read_generation=epoch))==1)
projectiles=[dict(sourceId=10,targetId=2,damage=24,releaseAt=0)]
plans=dict(rangedPlan=dict(releaseAt=.25),counterPlan=dict(releaseAt=.25),attackCooldown=.85)
prior=json.dumps(dict(projectiles=projectiles,plans=plans),sort_keys=True)
ready_mission().plant(1000,.38,{},0)
check('no attack cancel or projectile erasure',prior==json.dumps(dict(projectiles=projectiles,plans=plans),sort_keys=True))
check('source hashes unchanged during fixture run',HASHES=={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in SOURCES})
samples=[mission_sample(l,h,a) for l in [1,2,5,8,10] for h in [100,300,1000] for a in [0,.25,.38]]
report=dict(directive_id='JP_DF-HQ-20261008-COMMON-FIRST-R1',task_id='BAL-01-REV4',owner='BALANCE',status='PASS',
            scope='isolated Python REV4 specification arithmetic/state fixtures; NOT Godot/runtime/GPU/natural-play verification',
            source_hashes=HASHES,verifier_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            passed=len(CHECKS),failed=0,checks=CHECKS,growth=[stats(l) for l in range(1,11)],
            proposed=dict(level2='plant_charge',level5='three_hits_then_charge',level8='charge_shrapnel',
                          charge_policy='one committed charge per ninja; distinct ninjas may share pinned target',
                          strongest_rank=['damage_desc','maxHp_desc','armor_desc','travel_asc','id_asc'],
                          combo_factors=COMBO_FACTORS,combo_phases=COMBO_PHASES,bomb_factor=BOMB_FACTOR,bomb_fuse=BOMB_FUSE,
                          shrapnel_factor=SHRAPNEL_FACTOR,shrapnel_radius=SHRAPNEL_RADIUS,shrapnel_limit=SHRAPNEL_LIMIT),
            selection_samples=[dict(name='samurai',winner=choose_strongest([samurai,cavalry,tower])['id']),
                               dict(name='cavalry',winner=choose_strongest([blocked,cavalry,tower])['id']),
                               dict(name='strongtower',winner=choose_strongest([samurai,cavalry,strong_tower])['id'])],mission_samples=samples)
output=Path(__file__).with_name('BAL-01_ninja_numeric_results.json')
output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'passed':report['passed'],'failed':0,'evidence':str(output)},ensure_ascii=False))
