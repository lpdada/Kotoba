# 数据来源与署名

本项目内含的 `Kotoba/Resources/Dictionary.json` 是由开放数据构建的**衍生数据集**，按上游许可证要求以 **CC BY-SA 4.0** 发布。

> Contains data from [OpenJLPT](https://github.com/evanclan/OpenJLPT) (CC BY-SA 4.0), which uses
> JMdict and KANJIDIC2 (EDRDG), Jonathan Waller's JLPT lists, and Tatoeba.

## 上游来源

| 来源 | 用途 | 许可 |
| --- | --- | --- |
| [OpenJLPT](https://github.com/evanclan/OpenJLPT) | JLPT N5–N1 分级、罗马字、例句（含振假名标注） | CC BY-SA 4.0 |
| [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html)（EDRDG） | 英文释义、词性、频率带（`nfXX` / `ichi1` / `news1`） | CC BY-SA 4.0 |
| [Tatoeba](https://tatoeba.org)（经 OpenJLPT） | 例句原文与英文译文 | CC BY 2.0 FR |
| [Jonathan Waller's JLPT Resources](https://www.tanos.co.uk/jlpt/)（经 OpenJLPT） | JLPT 等级划分与释义 | CC BY |
| [KANJIDIC2](https://www.edrdg.org/wiki/index.php/KANJIDIC_Project)（EDRDG） | 汉字信息：读音、笔画、部首、学年、JLPT、拼音、英文释义 | CC BY-SA 4.0 |

## 数据集构建

`Dictionary.json` 由 `../build_dictionary.py`（在项目外的一次性脚本，逻辑同上表）生成：

1. 读取 OpenJLPT 的 N5–N1 词表（7,811 条），保留 `word / reading / romaji / level / pos / meanings / examples`；
2. 从 JMdict `common` 词集补齐助词、助动词、接续词、感叹词等**功能词**（JLPT 词表未收录），共 249 条；
3. 从 JMdict common 补齐 **片假名外来语**（ラーメン、コンビニ、スープ…）3,728 条；
4. 由 JMdict 的 `nfXX / ichi1 / news1` 标签计算 1–5 频率带，供分词打分使用；
5. 按（词形, 读音）去重，同一词条取等级最低（最基础）的一条，例句最多保留 2 条；同一表面同时是助词与名词时合并词性（で = conj + prt）。

最终 11,794 条、约 4.1 MB，随应用打包，运行时只读。

## 未包含的内容

- 不含任何影视、动画、音乐素材、字幕文件或其衍生截图。
- 不含 Kiku（kikulang.com）或任何其他产品的品牌名、图标、文案、配色或界面资产。
- `SampleClips.json` 中的 10 条示例台词为本项目原创的日语对话与中文翻译，仅用于演示交互，随代码以 MIT 发布。

## 语法数据（Grammar.json）

`Kotoba/Resources/Grammar.json` 由 `Tools/build_grammar.py` 从 **OpenJLPT** 生成，共 **526 条分级语法点**。

- **上游来源**：[`evanclan/OpenJLPT`](https://github.com/evanclan/OpenJLPT) 的 `data/json/grammar/n1.json` `n2.json` `n3.json` `n4.json` `n5.json`。
- **固定版本**：commit `bf4e1eecd5d11406aaecdee910464507aef7fcdc`（`n5.json` 于 2026-09-30 提交），构建脚本从该 commit 取原始文件，保证可复现。
- **上游许可证**：**CC BY-SA 4.0**（仓库 LICENSE 即 CC BY-SA 4.0 全文，与本项目 `Dictionary.json` 的发布方式一致）。`Grammar.json` 作为衍生数据集同样以 **CC BY-SA 4.0** 发布；代码本体仍是 MIT。

| 等级 | N5 | N4 | N3 | N2 | N1 | 合计 |
| --- | --- | --- | --- | --- | --- | --- |
| 条数 | 81 | 98 | 101 | 123 | 123 | **526** |

- **做了哪些变换**：只做字段选取与改名（`meaning` → `meaning_en`、`notes` → `notes_en`），保留 `pattern` / `romaji` / `formation` / `tags` / `examples`（每条最多 3 个例句），去重，并附加 `counts` 汇总。**没有改写任何英文释义，没有增删语法点，没有改动等级标注。**

### 中文释义的处理（诚实说明）

- OpenJLPT 只提供**英文释义与英文例句翻译**，没有中文原文；词表侧（OpenJLPT / JMdict 体系）同样只有英文。
- 因此按「能拿到可靠原文就用原文，不确定就保留英文并标注」的原则：**526 条全部 `meaning_zh = null`、`zh_status = "en-fallback"`**，界面应显示英文原文并标注「英文原文」。**不机翻、不猜译。**
- 需要中文时逐条人工核对后写入 `meaning_zh` 并把 `zh_status` 改为 `checked`；本仓库目前 **0 条** 完成该步骤。
- 这与汉字数据里「中文只覆盖人工核对的 284 字（N5 103/103、N4 181/181）」是同一套原则。

### 尚未接入的部分

- `Grammar.json` 目前**只是数据文件**：本轮没有改 `Kotoba.xcodeproj`（资源清单未更新）、没有改任何 Swift 代码，应用暂不会加载它。接入需要重新生成工程并新增 `GrammarStore` + 界面。

## 汉字数据（Kanji.json）

`Kotoba/Resources/Kanji.json` 由 `Tools/build_kanji.py` 从 KANJIDIC2 生成，覆盖**常用漢字（学年 1–6、8）∪ 带 JLPT 标记**的 2,387 字，字段为：

`k` 字 · `s` 笔画 · `r` 部首编号 · `rg` 部首字形 · `on` 音读 · `kun` 训读 · `py` 拼音 · `m` 英文释义 · `zh` 中文释义 · `g` 学年 · `j` JLPT 等级 · `f` 频率排名

- 部首字形由 Unicode「Kangxi Radicals」区（U+2F00 起）经 NFKC 归一化得到，不做 OCR 或猜测。
- **中文释义的实情**：KANJIDIC2 只提供英/西/法/葡释义，没有中文。为避免机器翻译出错，`zh` 字段是一份**人工核对的小表，仅覆盖 JLPT N5 + N4 共 284 字**（N5 103/103、N4 181/181）；其余字在界面上显示带标注的英文原义，并在详情页说明原因。这一取舍写在 README 的已知限制里。
- **笔顺：本轮未接入 KanjiVG**。KanjiVG 全量 SVG 体积过大（2,000+ 文件、约 10MB 级），本轮不做抽样或半成品渲染，界面不显示任何未经验证的笔顺；README 明确标注「笔顺展示留待下一轮」。
- 例词不引入新数据集：全部来自应用自带的 `Dictionary.json`（11,794 条），按「包含该汉字」筛选后按 JLPT 等级 → 词长 → 字典序排序，优先多字词。
