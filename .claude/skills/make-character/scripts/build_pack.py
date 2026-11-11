#!/usr/bin/env python3
"""TermPet 친구 팩 빌더: 레시피(recipe.json) + 원본 그림 → Friends/<id>/ 팩 폴더.

    python3 build_pack.py recipe.json OUT_DIR        # OUT_DIR/<id>/ 에 팩 생성

레시피 (경로는 레시피 파일 기준 상대 경로 가능):
{
  "id": "nameko", "name": "나메코", "order": 8, "walkSpeed": 40, "facing": "front",
  "area": 9800,                      # 모든 포즈의 '불투명 면적'을 이 값(px², 220 프레임 기준)에 맞춤 → 크기 통일
  "messages": {"done": [...], "error": [...], "ask": [...]},
  "states": {
    "idle":   {"src": "src/123.png", "motion": "breathe"},
    "walk":   {"src": "src/456.png", "motion": "hop", "facing": "right"},
    "happy":  {"src": "src/anim.png"},             # APNG/GIF 면 원본 프레임을 그대로 사용 (최대 20장)
    "happy.2": {"src": "src/789.png", "crop": [x, y, w, h], "erase": [[x, y, w, h]], "flip": true, "size": 1.1}
  }
}
상태별 옵션: src, crop, erase(지울 사각형들, crop 전 원본 좌표), flip(좌우 반전), size(면적 배율),
            motion(still/breathe/hop/hopfwd/sway/shake/wobble/float/lean/sleepy), fps, frames(정지 그림 프레임 수, 기본 8),
            bg("auto" 기본: 투명도가 없으면 가장자리 배경색을 지움 / "keep": 그대로 / "white": 흰 배경 지움),
            tolerance(배경 지우기 색 허용치, 기본 28),
            islands("largest": 가장 큰 덩어리만 남김 — 스티커 글씨·효과 조각 제거 / 숫자 N: N px² 보다 작은 조각만 지움.
                    기본 120 = 자잘한 점만 지움. 컵·부채처럼 몸에서 떨어진 소품이 있으면 "largest" 쓰지 말 것)
"""
import json
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageSequence

FRAME = 220          # 프레임 크기 (character.json frameWidth/Height)
SCALE = 0.42         # 화면 표시 배율 → 220 × 0.42 ≈ 92pt
MAX_H = 150          # 포즈 높이 상한 (머리 위 배지·말풍선 자리)
MAX_W = 196
BOTTOM_MARGIN = 3
MAX_ANIM_FRAMES = 20

DEFAULT_MOTION = {
    'idle': 'breathe', 'walk': 'hop', 'talk': 'sway', 'happy': 'hop', 'angry': 'shake', 'ask': 'sway',
    'sleep': 'sleepy', 'dragged': 'float', 'fall': 'wobble', 'climb': 'lean',
}
DEFAULT_FPS = {
    'idle': 6, 'walk': 10, 'talk': 8, 'happy': 12, 'angry': 12, 'ask': 8, 'sleep': 3, 'dragged': 8, 'fall': 6, 'climb': 8,
}
STATES = set(DEFAULT_MOTION)


# MARK: - 원본 읽기 · 배경 지우기

def load_frames(path):
    """정지 그림이면 [1장], APNG/GIF 면 합성된 프레임들(최대 20장, 고르게 뽑기)."""
    im = Image.open(path)
    frames = [f.convert('RGBA') for f in ImageSequence.Iterator(im)]
    if len(frames) > MAX_ANIM_FRAMES:
        step = len(frames) / MAX_ANIM_FRAMES
        frames = [frames[int(i * step)] for i in range(MAX_ANIM_FRAMES)]
    return frames


def has_alpha(im):
    a = im.getchannel('A')
    return a.getextrema()[0] < 250


def remove_background(im, mode, tolerance):
    """가장자리에서 이어진 배경색 영역만 투명하게 (캐릭터 안쪽 흰색은 지키기 위해 flood fill)."""
    if mode == 'keep' or (mode == 'auto' and has_alpha(im)):
        return im
    rgb = im.convert('RGB')
    w, h = rgb.size
    mask = Image.new('L', (w, h), 0)
    corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    seeds = [(x, 0) for x in range(0, w, max(1, w // 40))] + [(x, h - 1) for x in range(0, w, max(1, w // 40))] + \
            [(0, y) for y in range(0, h, max(1, h // 40))] + [(w - 1, y) for y in range(0, h, max(1, h // 40))] + corners
    target = (255, 255, 255) if mode == 'white' else None
    work = rgb.copy()
    marker = (255, 0, 255)
    for s in seeds:
        c = work.getpixel(s)
        if c == marker:
            continue
        if target and max(abs(c[i] - target[i]) for i in range(3)) > tolerance:
            continue
        ImageDraw.floodfill(work, s, marker, thresh=tolerance)
    diff = ImageChops.difference(work, Image.new('RGB', (w, h), marker)).convert('L')
    mask = diff.point(lambda v: 255 if v > 0 else 0)  # 마커가 아닌 곳 = 남길 부분
    out = im.copy()
    out.putalpha(ImageChops.multiply(im.getchannel('A'), mask))
    return out


def drop_islands(im, rule):
    """떨어져 있는 불투명 조각 지우기 (스티커 글씨·효과선). rule: "largest" 또는 최소 면적(px²)."""
    if rule in (None, 0, False):
        return im
    w, h = im.size
    alpha = im.getchannel('A')
    solid = bytearray(1 if a > 16 else 0 for a in alpha.getdata())
    label = [0] * (w * h)
    sizes = [0]
    for start in range(w * h):
        if not solid[start] or label[start]:
            continue
        n = len(sizes)
        sizes.append(0)
        stack = [start]
        label[start] = n
        while stack:
            i = stack.pop()
            sizes[n] += 1
            x, y = i % w, i // w
            for j in (i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w if y > 0 else -1, i + w if y < h - 1 else -1):
                if j >= 0 and solid[j] and not label[j]:
                    label[j] = n
                    stack.append(j)
    if len(sizes) <= 2:
        return im
    if rule == 'largest':
        keep_id = max(range(1, len(sizes)), key=lambda k: sizes[k])
        keep = {keep_id}
    else:
        keep = {k for k in range(1, len(sizes)) if sizes[k] >= int(rule)}
    mask = Image.new('L', (w, h))
    mask.putdata([255 if l in keep else 0 for l in label])
    out = im.copy()
    out.putalpha(ImageChops.multiply(alpha, mask))
    return out


def prepare(spec, base):
    path = spec['src'] if os.path.isabs(spec['src']) else os.path.join(base, spec['src'])
    frames = load_frames(path)
    out = []
    warned = False
    for f in frames:
        for box in spec.get('erase', []):
            x, y, w, h = box
            ImageDraw.Draw(f).rectangle([x, y, x + w - 1, y + h - 1], fill=(0, 0, 0, 0))
        if 'crop' in spec:
            x, y, w, h = spec['crop']
            f = f.crop((x, y, x + w, y + h))
        f = remove_background(f, spec.get('bg', 'auto'), spec.get('tolerance', 28))
        f = drop_islands(f, spec.get('islands', 120))
        b = f.getchannel('A').point(lambda v: 255 if v > 16 else 0).getbbox()
        if b and not warned and (b[3] >= f.height - 1 or b[0] <= 0 or b[2] >= f.width - 1):
            print(f'  ⚠ {os.path.basename(path)}: 그림이 원본 가장자리에 닿아요 (잘린 포즈일 수 있음 — 시트로 확인)')
            warned = True
        if spec.get('flip'):
            f = f.transpose(Image.FLIP_LEFT_RIGHT)
        out.append(f)
    return out


# MARK: - 크기 맞추기

def opaque_area(im):
    return sum(1 for a in im.getchannel('A').getdata() if a > 128)


def fit(frames, area, size_mul):
    """모든 프레임의 합집합 영역으로 잘라내고, 첫 프레임의 불투명 면적이 area×size 가 되도록 축소/확대."""
    bbox = None
    for f in frames:
        b = f.getchannel('A').point(lambda v: 255 if v > 16 else 0).getbbox()
        if b:
            bbox = b if bbox is None else (min(bbox[0], b[0]), min(bbox[1], b[1]), max(bbox[2], b[2]), max(bbox[3], b[3]))
    if bbox is None:
        raise SystemExit('그림이 전부 투명해요 (배경 지우기가 너무 셌거나 crop 이 잘못됨)')
    cropped = [f.crop(bbox) for f in frames]
    a = max(1, opaque_area(cropped[0]))
    k = math.sqrt(area * size_mul / a)
    w, h = cropped[0].size
    k = min(k, MAX_H / h, MAX_W / w)
    size = (max(1, round(w * k)), max(1, round(h * k)))
    return [c.resize(size, Image.LANCZOS) for c in cropped]


# MARK: - 움직임 (정지 그림 → 8프레임)

def transform(im, motion, t):
    """t: 0..1. (이미지, dx, dy) — dy<0 이면 위로."""
    s = math.sin(2 * math.pi * t)
    w, h = im.size
    if motion == 'breathe':
        sy, sx = 1 + 0.025 * s, 1 - 0.012 * s
        return im.resize((max(1, round(w * sx)), max(1, round(h * sy))), Image.LANCZOS), 0, 0
    if motion == 'sleepy':
        sy = 1 + 0.035 * s
        return im.resize((w, max(1, round(h * sy))), Image.LANCZOS), 0, 0
    if motion == 'hop':
        return im, 0, -round(abs(s) * 9)
    if motion == 'hopfwd':
        return im.rotate(-4 * s, resample=Image.BICUBIC, expand=True), round(2 * s), -round(abs(s) * 8)
    if motion == 'sway':
        return im.rotate(4 * s, resample=Image.BICUBIC, expand=True), 0, 0
    if motion == 'shake':
        return im, (3 if int(t * 8) % 2 == 0 else -3), 0
    if motion == 'wobble':
        return im.rotate(9 * s, resample=Image.BICUBIC, expand=True), 0, 0
    if motion == 'float':
        return im.rotate(5 * s, resample=Image.BICUBIC, expand=True), 0, -round(3 + 3 * s)
    if motion == 'lean':
        return im.rotate(-6 + 2 * s, resample=Image.BICUBIC, expand=True), round(4 + 2 * s), -round(2 * abs(s))
    return im, 0, 0  # still


def place(im, dx=0, dy=0):
    """프레임 가운데 아래(발이 바닥)에 놓기. 위로 튀어나가면 잘리지 않게 내린다."""
    frame = Image.new('RGBA', (FRAME, FRAME), (0, 0, 0, 0))
    w, h = im.size
    x = (FRAME - w) // 2 + dx
    y = FRAME - BOTTOM_MARGIN - h + dy
    y = max(0, y)
    x = min(max(0, x), FRAME - w)
    frame.alpha_composite(im, (x, y))
    return frame


def render_state(key, spec, base, area):
    action = key.split('.')[0]
    frames = fit(prepare(spec, base), area, spec.get('size', 1.0))
    if len(frames) > 1:  # 움직이는 원본: 프레임 그대로
        out = [place(f) for f in frames]
        fps = spec.get('fps', 12)
    else:
        n = spec.get('frames', 8)
        motion = spec.get('motion', DEFAULT_MOTION[action])
        out = [place(*transform(frames[0], motion, i / n)) for i in range(n)]
        fps = spec.get('fps', DEFAULT_FPS[action])
    sheet = Image.new('RGBA', (FRAME * len(out), FRAME), (0, 0, 0, 0))
    for i, f in enumerate(out):
        sheet.alpha_composite(f, (FRAME * i, 0))
    return sheet, len(out), fps, frames[0]


# MARK: - 메인

def build(recipe_path, out_root):
    with open(recipe_path, encoding='utf-8') as f:
        r = json.load(f)
    base = os.path.dirname(os.path.abspath(recipe_path))
    pid = r['id']
    if not pid.replace('-', '').replace('_', '').isalnum() or not pid.isascii():
        raise SystemExit('id 는 영문/숫자/-/_ 만')
    if 'idle' not in r['states']:
        raise SystemExit('states 에 idle 이 꼭 있어야 해요')
    out = os.path.join(out_root, pid)
    os.makedirs(out, exist_ok=True)
    for name in os.listdir(out):  # 예전 빌드 그림 정리
        if name.endswith('.png'):
            os.remove(os.path.join(out, name))

    states = {}
    idle_pose = None
    for key, spec in r['states'].items():
        action = key.split('.')[0]
        if action not in STATES:
            raise SystemExit(f'모르는 상태: {key} (가능: {sorted(STATES)})')
        sheet, n, fps, pose = render_state(key, spec, base, r.get('area', 9800))
        file = key.replace('.', '-') + '.png'
        sheet.save(os.path.join(out, file))
        entry = {'file': file, 'frames': n, 'fps': fps, 'loop': True}
        if 'facing' in spec:
            entry['facing'] = spec['facing']
        states[key] = entry
        if key == 'idle':
            idle_pose = pose
        print(f'  {key:10s} {n:2d}프레임 {fps}fps  {pose.size[0]}x{pose.size[1]}')

    # 목록 썸네일 (패널 동그라미)
    thumb = idle_pose.copy()
    thumb.thumbnail((128, 128), Image.LANCZOS)
    thumb.save(os.path.join(out, 'source.png'))

    pack = {
        'id': pid, 'name': r.get('name', pid), 'order': r.get('order', 50),
        'frameWidth': FRAME, 'frameHeight': FRAME, 'scale': SCALE, 'pixelArt': False,
        'facing': r.get('facing', 'front'), 'walkSpeed': r.get('walkSpeed', 40),
        'states': states,
    }
    if 'messages' in r:
        pack['messages'] = r['messages']
    with open(os.path.join(out, 'character.json'), 'w', encoding='utf-8') as f:
        json.dump(pack, f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f'완료: {out}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    build(sys.argv[1], sys.argv[2])
