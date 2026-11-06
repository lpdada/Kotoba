#!/usr/bin/env python3
"""Build Kotoba/Resources/Kanji.json from KANJIDIC2 (EDRDG, CC BY-SA 4.0).

Bundled set: Jōyō kanji (grade 1-6, 8) plus anything KANJIDIC2 tags with a JLPT
level — 2,387 characters.

Fields per entry:
  k  literal          s  stroke count        r  classical radical number
  rg radical glyph    on on'yomi             kun kun'yomi
  py pinyin           m  English meanings    zh hand-checked Chinese gloss (N5/N4 only)
  g  grade            j  JLPT level (KANJIDIC2 numbering 1-4)   f  frequency rank

KANJIDIC2 ships meanings in en/es/fr/pt — there is no Chinese gloss anywhere in
it, so the `zh` layer below is a small hand-written table covering the 284 N5/N4
characters. Characters outside that table show their English glosses, which the
UI labels as such; nothing is machine-translated into Chinese.

Usage: python3 build_kanji.py <kanjidic2.json> <output.json>
"""
import json
import sys
import unicodedata

# --- hand-checked Chinese glosses for JLPT N5 (kanjidic level 4) + N4 (level 3) ---
ZH = {
    # N5
    "一": "一；一个", "七": "七", "万": "万；一万", "三": "三", "上": "上；上面", "下": "下；下面",
    "中": "中；中间", "九": "九", "二": "二", "五": "五", "人": "人", "今": "现在", "休": "休息",
    "会": "会；见面；团体", "何": "什么；几个", "先": "先；以前", "入": "进入", "八": "八", "六": "六",
    "円": "圆；日元", "出": "出去；出来", "分": "分；分开；理解", "前": "前；前面", "北": "北", "十": "十",
    "千": "千", "午": "中午", "半": "半", "南": "南", "友": "朋友", "口": "口；嘴", "古": "旧；古老",
    "右": "右", "名": "名字", "四": "四", "国": "国；国家", "土": "土；土地", "外": "外；外面", "多": "多",
    "大": "大", "天": "天；天空", "女": "女", "子": "孩子；子", "学": "学；学习", "安": "便宜；安心",
    "小": "小", "少": "少", "山": "山", "川": "河", "左": "左", "年": "年", "店": "店", "後": "后；之后",
    "手": "手", "新": "新", "日": "日；太阳", "時": "时；时间", "書": "书；写", "月": "月", "木": "树；木",
    "本": "书；本", "来": "来", "東": "东", "校": "学校", "母": "母亲", "毎": "每", "気": "气；心情",
    "水": "水", "火": "火", "父": "父亲", "生": "生；出生；活的", "男": "男", "白": "白", "百": "百",
    "目": "眼", "社": "公司；神社", "空": "天空；空", "立": "站；立", "耳": "耳", "聞": "听；问", "花": "花",
    "行": "去", "西": "西", "見": "看；见", "言": "说；言语", "話": "说话；故事", "語": "语言", "読": "读",
    "買": "买", "足": "脚；足", "車": "车", "週": "周；星期", "道": "道；道路", "金": "金；钱", "長": "长",
    "間": "间；之间", "雨": "雨", "電": "电", "食": "吃；食物", "飲": "喝", "駅": "车站", "高": "高；贵",
    "魚": "鱼",
    # N4
    "不": "不；否定", "世": "世；社会", "主": "主；主人", "乗": "乘；乘坐", "事": "事情", "京": "京；东京",
    "仕": "做事；服侍", "代": "代；代替", "以": "以", "低": "低", "住": "住；居住", "体": "身体",
    "作": "做；制作", "使": "使用", "便": "方便；便", "借": "借", "働": "工作（日本汉字）", "元": "元；原来",
    "兄": "哥哥", "光": "光", "写": "写；复制", "冬": "冬", "切": "切；切断", "別": "别；分别", "力": "力；力气",
    "勉": "勉；努力", "動": "动", "区": "区", "医": "医", "去": "去；过去", "台": "台；台子", "合": "合；合适",
    "同": "同；相同", "味": "味；味道", "品": "品；物品", "員": "员；成员", "問": "问；询问", "回": "回；次",
    "図": "图；地图", "地": "地；地面", "堂": "堂；厅堂", "場": "场；场所", "声": "声音", "売": "卖", "夏": "夏",
    "夕": "傍晚", "夜": "夜", "太": "太；粗", "好": "好；喜欢", "妹": "妹妹", "姉": "姐姐", "始": "开始",
    "字": "字", "室": "室；房间", "家": "家；房子", "寒": "冷", "屋": "屋；房子", "工": "工；工艺", "市": "市",
    "帰": "回；归", "広": "宽；广", "度": "度；次", "建": "建", "引": "拉；引", "弟": "弟弟", "弱": "弱",
    "強": "强", "待": "等；等待", "心": "心", "思": "想；思考", "急": "急；突然", "悪": "坏", "意": "意；意思",
    "所": "所；地方", "持": "拿；持有", "教": "教", "文": "文；文章", "料": "料；材料", "方": "方；方向；方法",
    "旅": "旅行", "族": "族；家族", "早": "早", "明": "明；明亮", "映": "映；映照", "春": "春", "昼": "白天；中午",
    "暑": "热", "暗": "暗", "曜": "星期（曜日）", "有": "有", "服": "衣服", "朝": "早上", "村": "村", "林": "林",
    "森": "森林", "業": "业；行业", "楽": "快乐；轻松", "歌": "歌", "止": "停；止", "正": "正；正确", "歩": "走；步行",
    "死": "死", "民": "民；人民", "池": "池；池塘", "注": "注；注入", "洋": "洋；西洋", "洗": "洗", "海": "海",
    "漢": "汉", "牛": "牛", "物": "物；东西", "特": "特；特别", "犬": "狗", "理": "理；道理", "産": "产；生产",
    "用": "用", "田": "田；田地", "町": "町；城镇", "画": "画；图画", "界": "界；世界", "病": "病", "発": "发；出发",
    "県": "县", "真": "真；真实", "着": "穿；到达", "知": "知道", "短": "短", "研": "研；研究", "私": "我", "秋": "秋",
    "究": "究；研究", "答": "回答", "紙": "纸", "終": "结束", "習": "学；练习", "考": "想；考虑", "者": "者；人",
    "肉": "肉", "自": "自；自己", "色": "颜色", "英": "英；英国", "茶": "茶", "菜": "菜", "薬": "药", "親": "父母；亲",
    "計": "计；计量", "試": "试", "説": "说；说明", "貸": "借出", "質": "质；质量", "赤": "红", "走": "跑",
    "起": "起；起来", "転": "转", "軽": "轻", "近": "近", "送": "送", "通": "通；通过", "進": "进", "運": "运；运送",
    "遠": "远", "都": "都；都市", "重": "重", "野": "野；田野", "銀": "银", "門": "门", "開": "开", "院": "院；医院",
    "集": "集；收集", "青": "蓝；青", "音": "声音", "頭": "头", "題": "题", "顔": "脸", "風": "风", "飯": "饭",
    "館": "馆", "首": "脖子；首", "験": "验；考试", "黒": "黑", "鳥": "鸟",
}

TONE_MARKS = {
    "a": "āáǎà", "e": "ēéěè", "i": "īíǐì", "o": "ōóǒò", "u": "ūúǔù", "ü": "ǖǘǚǜ",
}


def pinyin_with_marks(raw: str) -> str:
    """'ya4' -> 'yà'; leaves already-marked or unparsable input alone."""
    if not raw:
        return ""
    text_in = raw.strip().lower()
    tone = 0
    body = text_in
    if text_in and text_in[-1].isdigit():
        tone = int(text_in[-1])
        body = text_in[:-1]
    elif " " in text_in:
        head, _, tail = text_in.rpartition(" ")
        if tail.isdigit():
            body, tone = head, int(tail)
    text = body.strip()
    if tone not in (1, 2, 3, 4) or not text:
        return text
    # Tone mark goes on the first a/e/ou vowel group, else the last vowel.
    target = -1
    for index, char in enumerate(text):
        if char in "ae" or (char == "o" and index + 1 < len(text) and text[index + 1] == "u"):
            target = index
            break
    if target < 0:
        for index in range(len(text) - 1, -1, -1):
            if text[index] in "iouü":
                target = index
                break
    if target < 0:
        return text
    vowel = text[target]
    if vowel not in TONE_MARKS:
        return text
    marked = TONE_MARKS[vowel][tone - 1]
    return text[:target] + marked + text[target + 1:]


def radical_glyph(number: int) -> str:
    if not 1 <= number <= 214:
        return ""
    try:
        char = chr(0x2F00 + number - 1)
        return unicodedata.normalize("NFKC", char)
    except ValueError:
        return ""


def main() -> int:
    source = sys.argv[1] if len(sys.argv) > 1 else "kanjidic2-all-3.6.2.json"
    target = sys.argv[2] if len(sys.argv) > 2 else "../kiku-ios/Kotoba/Resources/Kanji.json"

    data = json.load(open(source, encoding="utf-8"))
    entries = []
    for character in data["characters"]:
        misc = character.get("misc") or {}
        grade = misc.get("grade") or 0
        jlpt = misc.get("jlptLevel") or 0
        if grade not in (1, 2, 3, 4, 5, 6, 8) and not jlpt:
            continue

        literal = character["literal"]
        strokes = (misc.get("strokeCounts") or [0])[0]
        radical_numbers = [r["value"] for r in character.get("radicals", []) if r.get("type") == "classical"]
        radical = radical_numbers[0] if radical_numbers else 0

        reading_meaning = character.get("readingMeaning") or {}
        on, kun, pinyin, meanings = [], [], "", []
        for group in reading_meaning.get("groups", []):
            for reading in group.get("readings", []):
                kind = reading.get("type")
                value = (reading.get("value") or "").strip()
                if not value:
                    continue
                if kind == "ja_on":
                    on.append(value)
                elif kind == "ja_kun":
                    kun.append(value)
                elif kind == "pinyin" and not pinyin:
                    pinyin = pinyin_with_marks(value)
            for meaning in group.get("meanings", []):
                if meaning.get("lang") == "en":
                    text = (meaning.get("value") or "").strip()
                    if text and text not in meanings:
                        meanings.append(text)

        entries.append({
            "k": literal,
            "s": strokes,
            "r": radical,
            "rg": radical_glyph(radical),
            "on": on[:4],
            "kun": kun[:5],
            "py": pinyin,
            "m": meanings[:5],
            "zh": ZH.get(literal, ""),
            "g": grade,
            "j": jlpt,
            "f": misc.get("frequency") or 0,
        })

    entries.sort(key=lambda e: (e["j"] or 9, e["f"] or 99999, e["k"]))
    payload = {
        "version": 1,
        "generatedAt": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "license": "CC BY-SA 4.0",
        "sources": [
            "KANJIDIC2 (EDRDG) — readings, meanings, grade, radical, stroke count, pinyin",
        ],
        "entries": entries,
    }
    with open(target, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))

    total = len(entries)
    with_zh = sum(1 for e in entries if e["zh"])
    by_level = {}
    for entry in entries:
        key = entry["j"] or 0
        bucket = by_level.setdefault(key, {"total": 0, "zh": 0})
        bucket["total"] += 1
        bucket["zh"] += 1 if entry["zh"] else 0
    print(f"kanji bundled: {total}, with Chinese gloss: {with_zh} ({with_zh / total:.1%})")
    for level in sorted(by_level, reverse=True):
        stats = by_level[level]
        label = {4: "N5", 3: "N4", 2: "N3", 1: "N2/N1", 0: "no JLPT"}[level]
        print(f"  {label:<7} {stats['total']:>5} kanji, zh {stats['zh']:>4} ({stats['zh'] / max(stats['total'], 1):.0%})")
    print(f"wrote {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
