#!/usr/bin/env python3
"""이미 설치된 친구 팩에 상태(포즈)만 더하기 — 팩 전체를 다시 만들지 않는다.

    python3 add_states.py recipe.json PACK_DIR

recipe.json 은 build_pack 레시피와 같은 모양이지만 더할 상태만 적는다 (idle 필요 없음):
    {"states": {"bite": {"src": "src/123.png", "islands": "largest"}}}
- `area` 를 안 적으면 팩의 idle 첫 프레임 불투명 면적에 맞춘다 (원래 친구들과 같은 크기).
- 같은 상태 키가 있으면 바꾼다. 처음 한 번 character.json 을 character.json.bak 으로 백업한다.
"""
import json
import os
import shutil
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_pack import FRAME, STATES, opaque_area, render_state  # noqa: E402


def idle_area(pack_dir, pack):
    idle = pack['states']['idle']
    sheet = Image.open(os.path.join(pack_dir, idle['file'])).convert('RGBA')
    return opaque_area(sheet.crop((0, 0, pack['frameWidth'], pack['frameHeight'])))


def main(recipe_path, pack_dir):
    with open(recipe_path, encoding='utf-8') as f:
        r = json.load(f)
    json_path = os.path.join(pack_dir, 'character.json')
    with open(json_path, encoding='utf-8') as f:
        pack = json.load(f)
    if pack.get('frameWidth') != FRAME or pack.get('frameHeight') != FRAME:
        raise SystemExit(f'프레임 크기가 {FRAME} 이 아닌 팩은 지원하지 않아요')
    base = os.path.dirname(os.path.abspath(recipe_path))
    area = r.get('area') or idle_area(pack_dir, pack)
    print(f'면적 기준 {area}')
    if not os.path.exists(json_path + '.bak'):
        shutil.copy2(json_path, json_path + '.bak')
    for key, spec in r['states'].items():
        if key.split('.')[0] not in STATES:
            raise SystemExit(f'모르는 상태: {key} (가능: {sorted(STATES)})')
        sheet, n, fps, pose = render_state(key, spec, base, area)
        file = key.replace('.', '-') + '.png'
        sheet.save(os.path.join(pack_dir, file))
        entry = {'file': file, 'frames': n, 'fps': fps, 'loop': True}
        if 'facing' in spec:
            entry['facing'] = spec['facing']
        pack['states'][key] = entry
        print(f'  {key:10s} {n:2d}프레임 {fps}fps  {pose.size[0]}x{pose.size[1]}')
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(pack, f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f'완료: {pack_dir}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2])
