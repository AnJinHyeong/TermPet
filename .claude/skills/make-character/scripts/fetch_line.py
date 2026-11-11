#!/usr/bin/env python3
"""LINE 스티커 팩 하나를 공개 CDN에서 받아 오기 (개인용 캐릭터 소스).

    python3 fetch_line.py PACKAGE_ID OUT_DIR

- 팩 정보: https://stickershop.line-scdn.net/products/0/0/1/<pkg>/iphone/productInfo.meta
- 스티커: /stickershop/v1/sticker/<id>/iPhone/sticker@2x.png  (움직이는 팩이면 sticker_animation@2x.png = APNG)
- 저장: OUT_DIR/<pkg>_<id>.png, OUT_DIR/<pkg>_info.json (팩 이름·스티커 목록)
- 압축 파일(zip) 통째로 받기는 권한 검사에 막혔던 적이 있어 개별 PNG 만 받는다.
"""
import json
import os
import sys
import urllib.request

CDN = 'https://stickershop.line-scdn.net'
UA = {'User-Agent': 'Mozilla/5.0'}


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()


def main(pkg, out):
    os.makedirs(out, exist_ok=True)
    meta = json.loads(get(f'{CDN}/products/0/0/1/{pkg}/iphone/productInfo.meta'))
    animated = bool(meta.get('hasAnimation'))
    title = meta.get('title', {})
    name = title.get('ko') or title.get('ja') or title.get('en') or next(iter(title.values()), str(pkg))
    ids = [s['id'] for s in meta.get('stickers', [])]
    print(f'{pkg}: {name} — 스티커 {len(ids)}개{" (움직임)" if animated else ""}')
    ok = 0
    for sid in ids:
        dest = os.path.join(out, f'{pkg}_{sid}.png')
        if os.path.exists(dest):
            ok += 1
            continue
        kind = 'sticker_animation@2x.png' if animated else 'sticker@2x.png'
        try:
            data = get(f'{CDN}/stickershop/v1/sticker/{sid}/iPhone/{kind}')
        except Exception:
            try:
                data = get(f'{CDN}/stickershop/v1/sticker/{sid}/iPhone/sticker@2x.png')
            except Exception as e:
                print(f'  {sid}: 실패 {e}')
                continue
        with open(dest, 'wb') as f:
            f.write(data)
        ok += 1
    with open(os.path.join(out, f'{pkg}_info.json'), 'w', encoding='utf-8') as f:
        json.dump({'package': pkg, 'name': name, 'animated': animated, 'stickers': ids}, f, ensure_ascii=False, indent=2)
    print(f'받음 {ok}/{len(ids)} → {out}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2])
