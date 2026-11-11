#!/usr/bin/env python3
"""그림 확인용 시트 만들기 (Read 도구로 열어서 눈으로 고르고 검사).

    python3 sheet.py sources OUT.png [파일 또는 폴더 ...]   # 후보 그림 격자 + 파일 이름 (포즈 고르기)
    python3 sheet.py pack OUT.png PACK_DIR                    # 만든 팩: 상태별 한 줄, 어두운 배경 (테두리 흰 얼룩 확인)

시트는 가로 1600px 이하로 줄여 저장한다 (이미지가 너무 크면 읽기 어려움).
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont, ImageSequence

DARK = (52, 54, 64, 255)      # 사용자 화면처럼 어두운 배경에서 흰 테두리(헤일로)가 잘 보인다
CHECK = (236, 236, 240, 255)


def font(size):
    for p in ['/System/Library/Fonts/AppleSDGothicNeo.ttc', '/System/Library/Fonts/Supplemental/AppleGothic.ttf']:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def save_scaled(img, out, max_w=1600):
    if img.width > max_w:
        img = img.resize((max_w, round(img.height * max_w / img.width)), Image.LANCZOS)
    img.convert('RGB').save(out)
    print(out)


def sources(out, paths):
    files = []
    for p in paths:
        if os.path.isdir(p):
            files += sorted(os.path.join(p, f) for f in os.listdir(p) if f.lower().endswith(('.png', '.jpg', '.jpeg', '.gif', '.webp')))
        else:
            files.append(p)
    cell, cols = 200, 8
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new('RGBA', (cell * cols, (cell + 22) * max(rows, 1)), CHECK)
    d = ImageDraw.Draw(sheet)
    f = font(13)
    for i, path in enumerate(files):
        im = Image.open(path)
        n = getattr(im, 'n_frames', 1)
        im = next(ImageSequence.Iterator(im)).convert('RGBA')
        im.thumbnail((cell - 12, cell - 12), Image.LANCZOS)
        x, y = (i % cols) * cell, (i // cols) * (cell + 22)
        sheet.alpha_composite(im, (x + (cell - im.width) // 2, y + (cell - im.height) // 2))
        label = os.path.splitext(os.path.basename(path))[0] + (f' ({n}f)' if n > 1 else '')
        d.text((x + 4, y + cell + 2), label, fill=(40, 40, 40, 255), font=f)
    save_scaled(sheet, out)


def pack(out, folder):
    with open(os.path.join(folder, 'character.json'), encoding='utf-8') as fp:
        p = json.load(fp)
    fw, fh = p['frameWidth'], p['frameHeight']
    keys = sorted(p['states'])
    show = 8
    sheet = Image.new('RGBA', (120 + fw * show, fh * len(keys)), DARK)
    d = ImageDraw.Draw(sheet)
    f = font(22)
    for r, key in enumerate(keys):
        st = p['states'][key]
        im = Image.open(os.path.join(folder, st['file'])).convert('RGBA')
        n = st.get('frames') or im.width // fw
        for i in range(min(n, show)):
            j = i * n // show if n > show else i
            sheet.alpha_composite(im.crop((j * fw, 0, (j + 1) * fw, fh)), (120 + i * fw, r * fh))
        d.text((8, r * fh + fh // 2 - 12), key, fill=(255, 255, 255, 255), font=f)
        d.line([(120, (r + 1) * fh - 1), (sheet.width, (r + 1) * fh - 1)], fill=(90, 90, 100, 255))
    save_scaled(sheet, out)


if __name__ == '__main__':
    if len(sys.argv) < 4 or sys.argv[1] not in ('sources', 'pack'):
        print(__doc__)
        sys.exit(2)
    if sys.argv[1] == 'sources':
        sources(sys.argv[2], sys.argv[3:])
    else:
        pack(sys.argv[2], sys.argv[3])
