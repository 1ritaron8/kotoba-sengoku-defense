"""Independent saved-data, progression and text/span checks; no game mutations."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = 0
failures = []

def check(condition, message):
    global checks
    checks += 1
    if not condition: failures.append(message)

def digest(value):
    canonical = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    return hashlib.sha256(canonical.encode()).hexdigest()

def kana(text):
    return ''.join(chr(ord(c)-0x60) if '\u30a1'<=c<='\u30f6' else c for c in text)

def text_check(value, label):
    check(all(value.get(k) for k in ('jp','reading','ko','parts')),label+' has Japanese, reading, Korean and ruby pieces')
    check(''.join(p['text'] for p in value['parts'])==value['jp'],label+' parts reconstruct exact text')
    reconstructed = ''.join(p.get('reading') or kana(p['text']) for p in value['parts'])
    check(reconstructed==value['reading'],label+' reading reconstructs from actual ruby pieces')
    check(re.search('[가-힣]',value['ko']) is not None,label+' has real Korean meaning')
    check(not re.search('[\u4e00-\u9fff]',value['reading']),label+' reading has no unexplained kanji')
    for p in value['parts']:
        if re.search('[\u4e00-\u9fff]',p['text']):
            check(bool(p.get('reading')),label+' every kanji-bearing piece has furigana')

def span_check(item, span, label):
    start, size = span['start'],span['length']
    check(isinstance(start,int) and isinstance(size,int) and start>=0 and size>0,label+' exact numeric span')
    check(item['jp'][start:start+size]==span['text'],label+' span is an actual source substring')
    check(len(span['text'])==size and bool(span['reading']),label+' source span length and reading')
    part_cursor = 0
    span_reading = ''
    for part in item['parts']:
        end = part_cursor+len(part['text'])
        overlap_start,overlap_end = max(start,part_cursor),min(start+size,end)
        if overlap_start<overlap_end and part.get('reading'):
            check(start<=part_cursor and start+size>=end,label+' does not split an indivisible ruby reading')
            if start<=part_cursor and start+size>=end:
                span_reading += part['reading']
        elif overlap_start<overlap_end:
            span_reading += kana(part['text'][overlap_start-part_cursor:overlap_end-part_cursor])
        part_cursor = end
    check(span_reading==span['reading'],label+' target reading matches its actual source ruby, including counter/unit sound changes')
    check(item['jp'][:start]+'＿'+item['jp'][start+size:] != item['jp'],label+' cloze actually removes source text')

def main():
    c = json.loads((ROOT/'native/curriculum.json').read_text(encoding='utf-8-sig'))
    plans = json.loads((ROOT/'native/learning_plans.json').read_text(encoding='utf-8-sig'))
    baseline = json.loads((ROOT/'tests/qa_intro_grammar_baseline.json').read_text(encoding='utf-8-sig'))
    words = [w for lessons in c.values() for l in lessons for w in l['newWords']]
    transfer_texts = [w['transferExample']['jp'] for w in words]
    check(len(set(transfer_texts))==900,'All 900 transfers retain individually distinct sentences')
    report_texts = [m['report']['jp'] for p in plans['stages'].values() for m in p['missions']]
    check(len(report_texts)==120 and len(set(report_texts))==120,'All 120 reports retain individually distinct sentences')
    identities = [[w['id'],w['jp'],w['reading'],w['ko'],w['parts']] for w in words]
    check(identities==baseline['wordIdentity'],'All 900 word IDs, spellings, readings, meanings and lexical ruby identities preserved')
    check(len(words)==900 and len({w['id'] for w in words})==900,'Exactly 900 distinct saved word identities')
    check(len(plans['stages'])==40,'Exactly 40 stages preserved')
    for tier in ('intermediate','advanced'):
        check(digest(c[tier])==baseline['higherTiers'][tier],tier+' curriculum unchanged')
    for sid,hash_value in baseline['higherPlans'].items():
        check(digest(plans['stages'][sid])==hash_value,sid+' higher-stage report/geometry/gameplay unchanged')
    step_ids, step_order, word_lookup = set(), {}, {w['id']:w for w in words}
    intro = c['basic']+c['beginner']
    for order,lesson in enumerate(intro,1):
        check(lesson['grammarOrder']==order,lesson['id']+' stable sequential grammar order')
        check(len(lesson['grammarSteps'])==2,lesson['id']+' exactly two compact foundation cards')
        check(len(lesson['newWords'])==(15 if order<=10 else 20),lesson['id']+' original vocabulary density')
        check(lesson['reviewIds']==baseline['lessons'][lesson['id']]['reviewIds'],lesson['id']+' existing review-budget/IDs preserved')
        check(lesson['title']==baseline['lessons'][lesson['id']]['title'],lesson['id']+' identity title preserved')
        for expr,old in zip(lesson['expressions'],baseline['lessons'][lesson['id']]['expressions']):
            for key in ('id','jp','reading','ko','parts'):
                check(expr.get(key)==old.get(key),lesson['id']+' optional expression identity preserved: '+key)
            check(expr['introOptional'] and expr['minimumGrammarOrder']>=1,lesson['id']+' old advanced bonus expression has a grammar guard')
        check(set(lesson['grammarPrerequisites'])==step_ids,lesson['id']+' prerequisites reference only earlier cards')
        for step in lesson['grammarSteps']:
            check(step['id'] not in step_ids,step['id']+' distinct grammar identity')
            step_ids.add(step['id'])
            step_order[step['id']] = order
            for key in ('titleKo','explanationKo','tipKo'):
                check(bool(step.get(key)) and len(step[key])<=180,step['id']+' concise Korean '+key)
            text_check(step['pattern'],step['id']+' pattern')
            text_check(step['example'],step['id']+' example')
            check(all(url.startswith('https://www.irodori.jpf.go.jp/') for url in step['sourceUrls']),step['id']+' official primary verification sources')
            exam = step['assessment']
            text_check(exam['item'],step['id']+' exam')
            span_check(exam['item'],exam['targetSpan'],step['id']+' exam')
            check(len(exam['choices'])==3 and len({q['id'] for q in exam['choices']})==3,step['id']+' three distinct exam choices')
            correct = [choice for choice in exam['choices'] if choice['id']==exam['answerId']]
            check(len(correct)==1 and correct[0]['jp']==exam['targetSpan']['text'],step['id']+' exact answer reconstructs the sentence')
            check(len({q['jp'] for q in exam['choices']})==3,step['id']+' no duplicated correct spellings')
            check(exam['item']['ko'] in exam['cueKo'],step['id']+' Korean semantic cue disambiguates meaning')
            for choice in exam['choices']: text_check(choice,step['id']+' choice '+choice['id'])
        for word in lesson['newWords']:
            check(word['example']['jp']!=word['transferExample']['jp'],word['id']+' two actually different contexts')
            for field in ('example','transferExample'):
                example = word[field]
                text_check(example,word['id']+' '+field)
                span_check(example,example['targetSpan'],word['id']+' '+field)
                check(example['targetSpan']['wordId']==word['id'],word['id']+' no particle/copula is awarded as vocabulary mastery')
                check(example['grammarIds'] and all(step_order.get(g,99)<=order for g in example['grammarIds']),word['id']+' only already-introduced grammar references')
                jp = example['jp']
                for minimum,pattern in [(5,r'あります'),(8,r'(大きい|小さい|長い|短い|広い|細い|強い)です'),
                        (9,r'います'),(10,r'(行き|来|見|聞き|話し|読み|書き|食べ|飲み|買い|売り|歩き|走り|待ち|守り)ます'),
                        (11,r'ではありません|ません'),(12,r'ですか|どこ'),(13,r'(店|市場|筆|墨|箸)で'),
                        (14,r'から|まで'),(15,r'ください'),(16,r'ました|でした'),(17,r'くない|かった'),
                        (19,r'ています|でいます'),(20,r'たいです')]:
                    if order<minimum:
                        check(re.search(pattern,jp) is None,word['id']+' '+field+' does not jump ahead to grammar order '+str(minimum))
    check(len(step_ids)==40,'Exactly 40 grammar introductions and exam items')
    check(c['basic'][0]['newWords'][0]['example']['grammarIds']==['basic-01-grammar-1'],'First 山です references only its actual nominal grammar')
    check(c['basic'][0]['newWords'][0]['transferExample']['grammarIds']==['basic-01-grammar-1','basic-01-grammar-2'],'First transfer actually adds は')
    lesson_lookup = {l['id']:l for l in intro}
    reports,linked = 0,0
    for sid,plan in plans['stages'].items():
        old = baseline['stageGameplay'][sid]
        check(plan['lessonId']==old['lessonId'] and plan['tier']==old['tier'],sid+' stage/lesson identity preserved')
        if plan['tier'] not in ('basic','beginner'): continue
        order = lesson_lookup[plan['lessonId']]['grammarOrder']
        check(len(plan['missions'])==3,sid+' original three mission identities retained')
        for mission,old_mission in zip(plan['missions'],old['missions']):
            reports += 1
            for key in ('id','wave','targets','answerId','action'):
                check(mission[key]==old_mission[key],mission['id']+' original gameplay coordinate/answer '+key)
            text_check(mission['report'],mission['id']+' report')
            answer = next(q for q in mission['targets'] if q['id']==mission['answerId'])
            check(answer['label']['jp'] in mission['report']['jp'],mission['id']+' exact correct visible target name remains in report')
            check(len(mission['report']['jp'])<=48,mission['id']+' short readable entry report')
            check(all(step_order.get(g,99)<=order for g in mission['report']['grammarIds']),mission['id']+' report does not reference future grammar')
            for minimum,pattern in [(5,r'あります|へ'),(8,r'(大きい|小さい|長い|短い|広い|細い|強い)です'),
                    (9,r'います'),(10,r'(行き|来|見|聞き|話し|読み|書き|食べ|飲み|買い|売り|歩き|走り|待ち|守り)ます'),
                    (11,r'ではありません|ません'),(12,r'ですか|どこ'),(13,r'で[^。]+ます'),
                    (14,r'から|まで'),(15,r'ください'),(16,r'ました|でした'),(17,r'くない|かった'),
                    (19,r'ています|でいます'),(20,r'たいです')]:
                if order<minimum:
                    check(re.search(pattern,mission['report']['jp']) is None,mission['id']+' report does not jump ahead to grammar order '+str(minimum))
            check(set(mission['itemIds'])<=set(old_mission['itemIds']),mission['id']+' no newly invented vocabulary credit')
            for wid in mission['itemIds']:
                linked += 1
                check(wid in word_lookup,mission['id']+' evidence references existing word')
                span_check(mission['report'],mission['report']['focusTargetSpan'],mission['id']+' actual focus evidence')
                check(mission['report']['focusTargetSpan']['wordId']==wid,mission['id']+' preserved focus really appears in report')
    check(reports==60,'Exactly sixty early-stage reports simplified')
    result = {'checks':checks,'failures':failures,'introLessons':20,'grammarSteps':40,'grammarAssessments':40,
              'earlyWords':350,'earlySentences':700,'earlyReports':reports,'earlyLinkedReports':linked,'totalWords':900,'totalStages':40,
              'scope':'Original data, vocabulary-save identity, source spans/ruby, conservative grammar ordering and unchanged mission gameplay. No GPU/voice/profile/native gameplay writes. Grammar naturalness is a separate manual review.'}
    (ROOT/'tests/qa_intro_grammar.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))
    raise SystemExit(1 if failures else 0)

if __name__=='__main__': main()
