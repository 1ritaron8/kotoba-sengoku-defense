"""Read-only route review: movement geometry, not artwork quality certification."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from normalize_battlefield_layouts import Terrain, xy, lengths, closest, collision_rects

ROOT = Path(__file__).resolve().parent.parent
COLORS = ['#35bcda', '#ffce5f', '#ad8af5', '#e8996d']


def metrics(points):
    pts = [xy(p) for p in points]
    distance = lengths(pts)[-1]
    direct = math.dist(pts[0], pts[-1])
    turns = []
    directions = []
    for a, b in zip(pts, pts[1:]):
        if math.dist(a, b) > .00001:
            directions.append(math.atan2(b[1] - a[1], b[0] - a[0]))
    for a, b in zip(directions, directions[1:]):
        turns.append(abs(math.atan2(math.sin(b - a), math.cos(b - a))))
    axis = (pts[-1][0]-pts[0][0], pts[-1][1]-pts[0][1])
    backward = sum(max(0, -((b[0]-a[0])*axis[0]+(b[1]-a[1])*axis[1])/max(direct, .00001)) for a, b in zip(pts, pts[1:]))
    return {'lengthNormalized': round(distance, 6), 'directDistance': round(direct, 6),
            'detourFactor': round(distance/max(direct, .00001), 3),
            'totalTurnDegrees': round(math.degrees(sum(turns)), 1),
            'maxWaypointTurnDegrees': round(math.degrees(max(turns, default=0)), 1),
            'backwardDistanceNormalized': round(backward, 6)}


def audit(maps, source):
    rows = []
    for stage in maps:
        paths = [dict(id=p['id'], objectiveId=p['objectiveId'], **metrics(p['points'])) for p in stage['paths']]
        ll = [p['lengthNormalized'] for p in paths]
        tt = [p['totalTurnDegrees'] for p in paths]
        ratio = max(ll)/min(ll)
        flags = []
        if ratio > 1.18:
            flags.append('unequal_travel_distance')
        if max(tt)-min(tt) > 75:
            flags.append('unequal_curvature')
        if max(p['detourFactor'] for p in paths) > 1.30:
            flags.append('excessive_detour')
        if max(p['backwardDistanceNormalized'] for p in paths) > .035:
            flags.append('backtracking')
        if max(p['maxWaypointTurnDegrees'] for p in paths) > 65:
            flags.append('sharp_waypoint_corner')
        if stage['stageNumber'] in (5, 11, 12):
            flags.append('user_reported_visual_route_problem')
        history = stage['historicalBattlefield']
        rows.append({'stageNumber': stage['stageNumber'], 'stageId': stage['id'],
                     'name': stage.get('name', stage.get('title', stage['id'])),
                     'terrainDesignKo': history.get('terrainDesignKo', ''),
                     'lengthRatio': round(ratio, 3), 'turnSpreadDegrees': round(max(tt)-min(tt), 1),
                     'paths': paths, 'flags': flags,
                     'reviewStatus': 'redesign_candidate' if flags else 'visual_review_required',
                     'mainRoadWidthWorld': 1.10,
                     'widthEvidence': 'native/battlefield_3d.gd ROAD_HALF_WIDTH=.55; final raster artwork still requires visual review',
                     'hunterApproaches': len(stage.get('sideAmbushEntrances', [])),
                     'weather': history.get('presentationWeather', {})})
    return {'sourcePath': str(source.resolve()), 'sourceSha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'stageCount': len(rows), 'redesignCandidateCount': sum(bool(r['flags']) for r in rows),
            'notFinalArtworkApproval': True,
            'rules': {'lengthRatioReviewThreshold': 1.18, 'turnSpreadReviewThresholdDegrees': 75,
                      'detourReviewThreshold': 1.30,
                      'interpretation': 'Review triggers, not automatic balance failures. Separate siege objectives and documented terrain constraints require individual design judgement; no speed compensation disguises awkward roads.'},
            'stages': rows}


def draw_sheets(maps, report, out):
    font_path = 'C:/Windows/Fonts/malgun.ttf'
    title = ImageFont.truetype(font_path, 20)
    text = ImageFont.truetype(font_path, 15)
    label = ImageFont.truetype(font_path, 13)
    for page in range(4):
        sheet = Image.new('RGB', (1660, 2580), '#171c21')
        draw = ImageDraw.Draw(sheet)
        draw.text((20, 9), '주력 도로 검토 · 화면 하단 아군 / 실선 주력 / 주황 점선 진지 공격 / 붉은 원 기지', font=title, fill='white')
        for ordinal, stage in enumerate(maps[page*10:page*10+10]):
            row = report['stages'][page*10+ordinal]
            left = 20+(ordinal%2)*820
            top = 46+(ordinal//2)*505
            w, h = 795, 447
            draw.rectangle((left, top, left+w, top+h), fill='#485a3f', outline='#91a087')
            def pixel(p):
                x, y = xy(p) if isinstance(p, dict) else p
                return left+x*w, top+y*h
            for water in collision_rects(stage):
                x, y = pixel(water)
                draw.rectangle((x, y, x+water['w']*w, y+water['h']*h), fill='#325f73')
            for feature in stage['historicalBattlefield'].get('heightFeatures', []):
                x, y = pixel(feature)
                rx = float(feature.get('w', .15))*w*.5
                ry = float(feature.get('h', .15))*h*.5
                draw.ellipse((x-rx, y-ry, x+rx, y+ry), outline='#71845a', width=2)
            for obstacle in stage.get('obstacles', []):
                if not obstacle.get('blockPlacement'): continue
                x, y = pixel(obstacle); r=float(obstacle['r'])*w
                draw.ellipse((x-r, y-r*h/w, x+r, y+r*h/w), fill='#555650')
            for i, path in enumerate(stage['paths']):
                points = [pixel(p) for p in path['points']]
                draw.line(points, fill=COLORS[i], width=5)
                x, y = points[0]
                draw.ellipse((x-4, y-4, x+4, y+4), fill=COLORS[i])
                draw.text((x+5, y+3), str(i+1), font=label, fill='white')
            for approach in stage.get('sideAmbushEntrances', []):
                for a, b in zip(approach.get('connectionPoints', []), approach.get('connectionPoints', [])[1:]):
                    a, b = pixel(a), pixel(b)
                    # Dashed diagnostic distinguishes a hunter trail from a full road.
                    span=max(1, int(math.dist(a, b)/5))
                    for step in range(0, span, 2):
                        t=step/span; u=min(1, (step+1)/span)
                        draw.line([(a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t),(a[0]+(b[0]-a[0])*u,a[1]+(b[1]-a[1])*u)], fill='#e89757', width=1)
            for zone in stage['buildZones']:
                x, y=pixel(zone)
                draw.rectangle((x-2, y-2, x+2, y+2), fill='#dedccb')
            for goal in stage['objectives']:
                x,y=pixel(goal)
                draw.ellipse((x-6,y-6,x+6,y+6),fill='#e25e66',outline='white')
            header=f"{stage['stageNumber']:02d} {row['name']} · 거리 {row['lengthRatio']:.2f}배 · 굴곡 차 {row['turnSpreadDegrees']:.0f}°"
            draw.text((left, top+h+4), header, font=text, fill='#ffb690' if row['flags'] else '#dde2d5')
        sheet.save(out/f'route-review-{page+1:02d}.png')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,default=ROOT/'native/maps.json')
    parser.add_argument('--out',type=Path,default=ROOT/'output/route-review')
    args=parser.parse_args()
    maps=json.loads(args.source.read_text(encoding='utf-8-sig'))
    args.out.mkdir(parents=True,exist_ok=True)
    report=audit(maps,args.source)
    (args.out/'route-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    with (args.out/'route-audit.csv').open('w',encoding='utf-8-sig',newline='') as file:
        writer=csv.writer(file);writer.writerow(['전장','이름','최장/최단 거리','굴곡 차(도)','검토 이유'])
        for r in report['stages']: writer.writerow([r['stageNumber'],r['name'],r['lengthRatio'],r['turnSpreadDegrees'],'; '.join(r['flags'])])
    draw_sheets(maps,report,args.out)
    print(json.dumps({'stages':40,'candidates':[r['stageNumber'] for r in report['stages'] if r['flags']],
                      'worstLengthRatio':max(r['lengthRatio'] for r in report['stages']),
                      'sourceSha256':report['sourceSha256'],'out':str(args.out)},ensure_ascii=False))


if __name__=='__main__': main()
