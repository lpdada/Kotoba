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
| [KANJIDIC2](https://www.edrdg.org/wiki/index.php/KANJIDIC_Project)（EDRDG） | 汉字信息（本数据集只用于校验读音） | CC BY-SA 4.0 |

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
