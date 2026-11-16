#!/usr/bin/env python3
"""Proposes a 메뉴 분류 (menu_category) for the published menus that have none, so the budget filter can confirm meals.

Reads the PUBLIC menus (anon key from .env), classifies each item by its name with conservative keyword rules, and writes
a CSV for the Admin's menu import (메뉴·가격 -> 여러 식당 CSV 가져오기, "갱신" mode, matched by menu_id). It changes nothing by
itself. It is a PROPOSAL: review the drafts in the Admin, then publish them.

A meal (식사 / 면류 / 분식) is only proposed with a clear name and a plausible price (식사 5,000-15,000원, 면류 4,000-15,000원,
분식 3,000-12,000원). Sets, combos (+), multi-person and large portions, sides, drinks and desserts get their own class and
never count as a meal; anything unclear is left blank, so it stays "정보 미확인" rather than a guessed match.

  python3 scripts/propose_menu_categories.py [output.csv]
"""
import sys
import re,json,csv,urllib.request,collections
env={}
for l in open('.env'):
    m=re.match(r'\s*([A-Z_]+)\s*=\s*(.*)',l)
    if m: env[m.group(1)]=m.group(2).strip().strip('"\'')
url=env['SUPABASE_URL']; key=env['SUPABASE_PUBLISHABLE_KEY']
def get_all(path):
    rows=[]
    for off in range(0,20000,1000):
        r=urllib.request.Request(url+path,headers={'apikey':key,'Authorization':'Bearer '+key,'Range':f'{off}-{off+999}'})
        d=json.loads(urllib.request.urlopen(r,timeout=60).read()); rows+=d
        if len(d)<1000: break
    return rows
menus=get_all('/rest/v1/restaurant_menus?select=id,restaurant_id,name_ko,description_ko,price_krw,category,available,status&order=id')
rests={r['id']:r for r in get_all('/rest/v1/restaurant_overrides?select=id,kakao_place_id,name_ko')}

MULTI=re.compile(r'\+|세트|set|\d\s*[~\-]?\s*\d?\s*인|인분\s*세트|패밀리|모둠|커플|콤보|한마리|두마리|반반|파티|플래터|맥주\s*\d|\d+\s*명|2P|3P|4P|\(대\)|\(중\)|대자|중자|특대|\bL\b|라지|점보',re.I)
DRINK=re.compile(r'커피|아메리카노|라떼|카푸치노|에스프레소|에이드|스무디|주스|쥬스|티$|차$|콜라|사이다|제로|맥주|소주|막걸리|생맥|하이볼|음료|탄산|쉐이크|프라페|밀크티|와인|위스키|칵테일|병$|캔$|생수|\d+ml|\d+cc|아이스티|요거트|버블|타피오카|사케|청하|매화수|모히또|\bHOT\b|\bICE\b',re.I)
DESSERT=re.compile(r'케이크|빙수|아이스크림|와플|마카롱|쿠키|디저트|푸딩|크로플|도넛|도너츠|타르트|브라우니|젤라또|스콘|빵$|호떡|꽈배기|찹쌀|파르페|츄러스')
SIDE=re.compile(r'후식|쥐포|공기밥|밥\s*추가|추가|사리|비조리|큰컵|컵라면|슬라이스|셀프|토핑|소스|리필|감자튀김|프렌치|치즈볼|콘샐러드|^계란(찜|말이|후라이|프라이)$|^달걀|김치$|단무지|샐러드|스프|수프|양파링|어니언링|너겟|치즈스틱|공기$|옵션|곱빼기\s*추가')
SNACK=re.compile(r'떡볶이|김밥|라볶이|토스트|쫄면')
NOODLE=re.compile(r'면$|국수|라면|라멘|우동|짜장|짬뽕|칼국수|냉면|밀면|파스타|쌀국수|막국수|수제비|소바|스파게티|볶음면|비빔면|메밀|짜파|잔치|누들|자장|짬짜|우육면')
MEAL=re.compile(r'밥$|덮밥|비빔밥|볶음밥|국밥|정식|백반|찌개|탕$|돈가스|돈까스|카레|버거|도시락|죽$|오므라이스|카레라이스|순두부|육개장|제육덮|해장국|곰탕|설렁탕|갈비탕|삼계탕|감자탕|리조또|필라프|샌드위치|타코|부리또|쌈밥|보리밥|돌솥|뚝배기|케밥|포케|비빔')
SHARED=re.compile(r'닭갈비|낙지|쭈꾸미|오징어|치킨|피자|족발|보쌈|삼겹|갈비|양꼬치|꼬치|회$|모듬|전골|전$|파전|안주|골뱅이|닭발|막창|곱창|대창|육회|탕수육|깐풍|양장피|마라샹궈|훠궈|샤브|무한|한판|통닭|닭강정|수육|야끼|오뎅탕|나가사키|스테이크|바베큐|바비큐')
def classify(m):
    n=re.sub(r'\s+','',m['name_ko'] or '')
    desc=(m.get('description_ko') or '')
    if not n or m['price_krw'] is None: return None,''
    if DRINK.search(n) and not MEAL.search(n): return '음료','음료/주류'
    if MULTI.search(n) or MULTI.search(desc[:60]): return '기타','다인/세트/대용량 표시'
    if SIDE.search(n): return '사이드','사이드/추가/기타 곁들임'
    if DESSERT.search(n): return '디저트','디저트'
    hits=[]
    if SNACK.search(n): hits.append('분식')
    if NOODLE.search(n): hits.append('면류')
    if MEAL.search(n): hits.append('식사')
    if SHARED.search(n): hits.append('안주')
    p=m['price_krw']
    if len(hits)==1:
        h=hits[0]
        if h=='식사' and not (5000<=p<=15000): return None,''
        if h=='면류' and not (4000<=p<=15000): return None,''
        if h=='분식' and not (3000<=p<=12000): return None,''
        return h,'이름 키워드: '+h
    if hits==['분식','면류'] and re.search(r'쫄면|라볶이|라면$',n): return '분식','분식 면'
    if set(hits)=={'식사','면류'} and re.search(r'칼국수|짜장|짬뽕|냉면|국수|우동|라멘|파스타|면$',n) and not re.search(r'밥|덮|탕',n): return '면류','면 요리'
    return None,''
out=[]; cnt=collections.Counter(); per=collections.defaultdict(list)
for m in menus:
    if m['status']!='active': continue
    cat,why=classify(m)
    cnt[cat]+=1
    if cat and not (m['category'] or '').strip():
        r=rests.get(m['restaurant_id'])
        if not r or not r['kakao_place_id']: continue
        out.append({'kakao_place_id':r['kakao_place_id'],'restaurant_name':r['name_ko'],'menu_name':m['name_ko'],'price_krw':m['price_krw'],'menu_category':cat,'description':'','is_available':'' ,'menu_id':m['id'],'proposal_basis':why})
        per[r['kakao_place_id']].append((cat,m['price_krw']))
print('classified',dict(cnt))
meal_r={k for k,v in per.items() if any(c in('식사','면류','분식') for c,_ in v)}
fit=lambda a:{k for k,v in per.items() if any(c in('식사','면류','분식') and p<=a for c,p in v)}
print('restaurants with >=1 proposed priced meal line:',len(meal_r),'| fit <=8000:',len(fit(8000)),'| <=10000:',len(fit(10000)),'| <=12000:',len(fit(12000)))
cols=['kakao_place_id','restaurant_name','menu_name','price_krw','menu_category','description','is_available','menu_id','proposal_basis']
OUT=sys.argv[1] if len(sys.argv)>1 else 'menu_categories_proposed.csv'
with open(OUT,'w',encoding='utf-8-sig',newline='') as fh:
    w=csv.DictWriter(fh,fieldnames=cols,lineterminator='\r\n'); w.writeheader(); w.writerows(out)
print('rows written',len(out))
print('written to',OUT)
