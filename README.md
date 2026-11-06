# Kotoba — 刷短视频学日语（个人自用 iOS 原型）

一个完全原创实现的「短视频 + 点词查词 + 间隔复习」日语学习应用。交互灵感来自同类产品的功能形态（滚动看片段、点词看解释、把词存成闪卡），但代码、界面、文案、配色、图标全部为本项目原创，不包含任何第三方的品牌、文案或视觉资产。

> 仅供个人在本地学习使用。仓库不含任何影视素材，片段由使用者自行导入并在本机播放。

---

> 改进路线与优先级见 [ROADMAP.md](ROADMAP.md)（调研来源、差距分析、本轮范围）。

## 1. 现在就能用的功能

| 模块 | 实现 |
| --- | --- |
| 纵向滚动片段流 | `ScrollView` + `.scrollTargetLayout()` + `.scrollTargetBehavior(.paging)`，整屏分页、进入即播、离开即停并记录学习时长 |
| 视频播放 | `AVPlayer` 封装（`ClipPlayer`）：片段区间循环、倍速、进度、失败回退；本地文件 / 网络 URL 均可 |
| YouTube 片段 | `WKWebView` 内嵌官方播放器 + `start/end/loop` 参数，视频仍由平台托管，不下载、不重编码 |
| 无画面片段 | SwiftUI 动态场景（`GeneratedSceneView`）+ 本地日语 TTS，开箱即可演示滚动与点词 |
| 字幕分词 | 自研 DP 分词器（`Tokenizer`）：词典驱动的总代价最小化 + 变形还原 + 未知段/片假名整体保留 |
| 点词查词 | 命中词典 → 读音、罗马字、词性、JLPT 等级、英文释义、例句；未命中 → 仍可看 AI/本地解释 |
| 变形还原 | 反向活用引擎（`Deinflector`）：て形 / た形 / ます / ない / 可能・被动・使役 / 假定 / 意志 / たい / ている 等 50+ 规则，候选交由词典验证 |
| 语境解释（离线） | `LocalContextExplainer`：重新分词定位该词位置 → 看后面接哪个助词判断成分（主语/宾语/主题…）→ 报告变形与敬体/常体 → 生成中文说明 |
| 语境解释（在线） | `RemoteLLMExplainer`：任意 OpenAI 兼容 `/chat/completions`，要求返回 JSON（headline/grammar/nuance），失败自动回落到离线解释；密钥存钥匙串 |
| 生词本 | 保存/搜索/筛选（新词、学习中、熟悉、掌握）、按熟悉度着色、笔记、忽略、手动标记已掌握、分组 |
| 间隔复习 | `SpacedRepetition`：学习阶梯 1 分 → 10 分 → 毕业 1 天；复习阶段按 ease 放大间隔，`hard` 1.2x / `good` ease / `easy` ease×1.35；`again` 回到学习阶段并降 ease；间隔 ±5% 浮动、上限 730 天。队列同时受「全局每日上限」与「分组每日新词/复习上限」约束 |
| 闪卡会话 | 队列 = 到期复习 + 每日新词 + 整句卡片；翻面、四档评分（带下次间隔预览）、撤销、进度、结算（记忆率/用时） |
| 整句卡片 | 从片段保存整句 + 翻译，作为独立卡种参与复习 |
| 难度分级 | 片段等级由词表估算（平均 JLPT 排名 + 生词占比），与手写等级并存；推荐器按等级距离、兴趣、是否看过、生词比例打分 |
| 学习数据 | 每日时长/复习数/遗忘数、连续天数、30–90 天热力图、熟悉度分布、记忆率、观看历史、词典覆盖统计 |
| 成就 | 6 个本地计算成就（首个生词、25 词、100 次复习、连续 7 天、10 个片段、20 词熟悉） |
| 内容导入 | 文件导入片段清单 JSON、导入视频/音频到 `Documents/Media`，可在「文件」App 直接拖放（`UIFileSharingEnabled`） |
| YouTube 导入 | 粘贴链接或 11 位 ID（watch / youtu.be / shorts / embed / live），自动解析 `t=`、`start=`、`#t=` 起点；标题、日文字幕、中文翻译、等级、区间一并入库 |
| 字幕导入 | `SubtitleParser` 解析 SRT / VTT（BOM、CRLF、序号行、`-->` 后位置参数、`<i>` 标签、ASS 覆盖标记、HTML 实体、重复滚动字幕），`SubtitleClipBuilder` 按「每段句数 / 最长秒数」切片；视频文件名留空自动匹配同名媒体，否则用朗读演示 |
| 备份与互通 | `BackupService`：一键导出/恢复完整 JSON 备份（ISO8601 与旧格式双兼容，空备份与更高版本会被拒绝），以及导出 Anki 兼容 TSV（5 列：词形、读音、释义、原句、标签） |
| 复习负载预测 | `reviewForecast(days:)` 输出未来 7 天到期分布（逾期并入今天），复习页用柱状条呈现，配合分组上限调节压力 |
| 逐句精听 | 片段页「精听」入口：按 `line_timings` 或字符数切句，逐句播放、上/下一句、点句跳转、A-B 循环、句末暂停、重复 1–3 次、倍速 0.5–1.5x；退出后恢复原区间与循环 |
| 汉字层 | 内置 2,387 个常用漢字/JLPT 汉字（KANJIDIC2）：读音、笔画、部首、学年、拼音、英文释义、N5+N4 中文释义；详情页列出例词（从词典自动筛选）。可在「生词 › 汉字」按等级/部首浏览与搜索，也可从点词卡片或词条页的汉字入口直接打开 |
| 汉字复习 | 汉字卡与生词卡共用同一套 `SpacedRepetition` 与四档评分；复习队列里与生词、整句混合出现，卡片正面是汉字、背面是读音+意思+例词 |
| 跟读与自评 | `ShadowingRecorder` 录音/回放/与原句对比，每句自评「跟上了 / 再来一次」，记录存到 `Documents/Shadowing`（每句保留最近 3 条），需要麦克风权限 |
| 自检 | `Diagnostics` 在设备上跑 10 项真实检查：词典载入、精确查词、变形还原、断词完整性、调度阶梯、遗忘回退、间隔增长、状态往返、存储可写、素材库 |

## 2. 工程结构

```
kiku-ios/
├─ Kotoba.xcodeproj/          # 纯手写工程（objectVersion 56，Xcode 14+ 可开）
│  ├─ project.pbxproj         # 由 Tools/generate_project.py 生成
│  └─ xcshareddata/xcschemes/Kotoba.xcscheme
├─ Kotoba/
│  ├─ App/                    # 入口、RootView、AppModel（状态中枢）、引导页
│  ├─ Model/                  # 语言模型、片段、词汇、调度、画像与快照
│  ├─ Services/               # 词典、分词、变形、调度、复习会话、解释、播放、TTS、导入、字幕、备份、自检
│  ├─ Views/                  # Feed / Vocabulary / Review / Progress / Settings / Components
│  ├─ Resources/              # Dictionary.json、SampleClips.json、Assets.xcassets
│  └─ Info.plist
├─ Tools/
│  ├─ generate_project.py     # 扫描源码目录重新生成 pbxproj + scheme
│  ├─ lint_swift.py           # 括号平衡 / 重复类型 / AppModel 引用一致性检查
│  ├─ check_initializers.py   # 自建结构体构造标签与顺序检查
│  ├─ verify_core.swift       # 四大引擎的命令行输出（词典/分词/变形/调度）
│  ├─ verify_logic.sh         # Linux 上编译并真跑决策层断言
│  ├─ HarnessLogic.swift      # 那些断言的正文
│  └─ stubs/PlatformShim.swift# SwiftUI/AVFoundation/Security 的最小替身
├─ .github/workflows/ios.yml  # macOS 模拟器无签名构建 + 产物校验
└─ ATTRIBUTION.md             # 词典数据来源与许可
```

约 8,299 行 Swift，无任何第三方依赖（只用 SwiftUI / AVFoundation / WebKit / Security / UniformTypeIdentifiers）。

## 3. 构建

### 本机 Xcode
```bash
open Kotoba.xcodeproj      # 选任意 iOS 17+ 模拟器，⌘R
```

### 命令行（模拟器、免签名）
```bash
xcodebuild -project Kotoba.xcodeproj -scheme Kotoba \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

### GitHub Actions
推到 `main` 或手动触发 `iOS Build` 工作流即可；它会在 `macos-15` 上选最新稳定 Xcode，先跑 `Tools/lint_swift.py`，再做模拟器构建，最后校验 `Kotoba.app` 里是否打进了 `Dictionary.json` 与 `SampleClips.json`。
真机安装需要你自己的 `DEVELOPMENT_TEAM`（在 Xcode 的 Signing & Capabilities 里选一次即可）。

### 改了文件以后
新增/删除 Swift 或资源文件后重新生成工程：
```bash
python3 Tools/generate_project.py
```

## 4. 导入自己的片段

应用不附带影视素材。要播放真实视频：

1. 把 mp4/m4a 放进 **文件 App › 我的 iPhone › Kotoba › Media**（或在应用内「我的 › 内容管理 › 导入视频」）。
2. 导入一份清单 JSON（「内容管理 › 导入片段清单」）：

```json
{
  "version": 1,
  "clips": [
    {
      "id": "my-clip-001",
      "title": "便利店点单",
      "series": "我自己的素材",
      "episode": "第 1 话",
      "transcript": "すみません、これください。\nおいくらですか。",
      "translation": "不好意思，我要这个。\n多少钱？",
      "level": "n5",
      "topics": ["日常会话"],
      "duration_seconds": 8,
      "media": { "kind": "localFile", "value": "clip01.mp4" },
      "attribution": "个人收藏，仅供自己学习",
      "custom": true
    }
  ]
}
```

`media` 的三种写法：

| 写法 | 用途 |
| --- | --- |
| `{"kind":"localFile","value":"clip01.mp4"}` | 本地视频/音频，从 0 秒循环播放 `duration_seconds` |
| `{"kind":"youtube","id":"VIDEO_ID","start":12,"end":24}` | 用官方内嵌播放器循环 12–24 秒；视频仍由平台托管 |
| `{"kind":"generated"}` | 无画面模式：动态背景 + 本地日语朗读（内置示例都用这个） |

字幕一行一句（`\n` 分隔），`translation` 行数与之一一对应；分词、读音、词性全部运行时自动生成，不需要手工标注。

### 直接用字幕文件（推荐）

「内容管理 › 导入字幕（SRT / VTT）」：选一个字幕文件即可，按每段句数（1–6）与最长时长（4–40 秒）自动切片，媒体文件名留空时会自动找同名视频（`ep01.srt` → `ep01.mp4`），找不到就用朗读模式。每条片段会记住自己在该视频里的起始秒数（`start_seconds`），播放时从这句台词开始循环，而不是从视频 0 秒开始。重复导入同一文件不会产生重复片段。

### 备份、恢复与 Anki

「设置 › 数据」：`导出备份 (JSON)` 保存全部学习记录；`从备份恢复 (JSON)` 会在确认后用备份整体替换本地状态（媒体文件不动）；`导出 Anki 卡片 (TSV)` 生成 5 列制表符文件，可直接在 Anki 里以「制表符分隔」导入。

## 5. 核心算法说明

**分词**：对字幕做动态规划，最小化整句总代价，而不是最大化得分——后者会让「一个真实词」输给「五个看起来像词的假字」。每个 token 的代价：

| 情况 | 代价 |
| --- | --- |
| 精确命中词典 | `4.2 - 1.15×长度 - 0.35×(6-频率带)` |
| 变形还原后命中 | `5.0 - 0.95×长度 - 0.25×(6-频率带)` |
| 单个假名词（非助词/助动词） | 额外 `+4.0`（避免 す/み/ま 式的碎片化） |
| 假名写法却命中汉字词条 | 额外 `+3.0`（がい 不是「害」，いと 不是「糸」） |
| 未知字符 | 每字 `3.2` |
| 未知连续段 | `2.0 + 1.0×长度`（整体更划算，所以 すみません 不会被切碎） |
| 连续片假名 | `2.0 + 0.45×长度`（外来语整体保留：ラーメン） |

DP 结束后把相邻的未知 token 合并成一个可点击单元；单个汉字词干若不在词典里会尝试补 `る/い/う/く/…` 找到原形（見 → 見る）。实测效果：

```
昨日友達と映画を見に行きました
→ 昨日 | 友達 | と | 映画 | を | 見(見る) | に | 行きました(行く)

最近、時間が足りない気がする。
→ 最近 | 、 | 時間 | が | 足りない(足りる) | 気 | が | する | 。
```

**变形还原**：`Deinflector` 用「后缀 → 词干行变换」的规则表生成候选原形（`って` → う/つ/る/く，`ます` → 词干末假名转ウ段或加 `る`，`なかった` → ア段转ウ段…），再由词典确认候选是否真实存在，最多递归两层（`てください` → `て形` → 原形）。同一表面能还原出多个原形时（`行って` → 行く / 行う），按频率带 → 是否功能词 → JLPT 等级排序取最优，所以结果是 行く 而不是 行う。

**调度**：`learningStep` 记录「已完成的阶梯段数」。新卡：`记得` → 1 分钟后 → 10 分钟后 → 毕业 1 天；之后按 ease（初始 2.5）放大间隔，`困难` 1.2x 且 ease −0.12，`记得` ease +0.08，`简单` ease×1.35 且 ease +0.14；`忘记` 回到学习阶段、ease −0.22 并把旧间隔存进 `preLapseInterval` 供重新毕业时使用。间隔 ±5% 浮动、上限 730 天。熟悉度 1–5 由当前间隔反推（<1 天=生疏、<3 天=眼熟、<7 天=有印象、<21 天=熟悉、≥21 天=掌握），避免「手动打勾」和真实记忆脱节。

**难度估算**：片段等级 = 字幕中命中词的 JLPT 排名均值（四舍五入到最近等级），未知词计入「生词占比」。推荐排序综合等级距离、兴趣标签、是否看过、生词占比，并加 ±0.35 随机抖动。

`Tools/verify_logic.sh` 把「模型 + 服务 + AppModel」用一个最小平台桩编译并在 Linux 上**真跑**断言（分组限额、学习阶梯、评分、撤销、日统计都覆盖）。`Tools/verify_core.swift` 则单独打印四个引擎的原始输出：

```bash
swiftc -swift-version 5 -Onone Kotoba/Model/*.swift Tools/verify_core.swift \
  Kotoba/Services/{Deinflector,DictionaryStore,Tokenizer,ContextExplainer}.swift \
  -o /tmp/verify_core && /tmp/verify_core Kotoba/Resources/Dictionary.json
```

## 6. 已知限制

- 没有词形标注的训练数据，分词是「词典 + DP」而非形态素分析器；人名、专有名词会切成单字（表现为多个未知词），这时点词会走 AI/本地解释而不是词典释义。
- 词典释义为英文（JMdict 原始数据），界面与语境解释是中文。个人使用时通常配合 AI 解释看中文。
- 未做后台播放、锁屏控制、通知提醒。
- 精听模式对 YouTube 片段用本地朗读演示（内嵌播放器无法逐句 seek），只有本地/网络视频文件走真实音轨。
- 汉字笔顺**尚未实现**：KanjiVG 全量数据体积过大，本轮不做半成品渲染，界面上不显示任何未经验证的笔顺，留待下一轮。
- 汉字中文释义只覆盖 N5+N4（284 字，人工核对）：KANJIDIC2 本身只有英/西/法/葡释义，其余字显示带标注的英文原义，不做机器翻译。
- 跟读录音需要麦克风权限；录音文件只在本机 `Documents/Shadowing`，不会随备份导出（备份只含文字记录与文件名）。
- 视频只支持单文件本地播放或 YouTube 内嵌；不做离线下载。
- 真机安装需自行配置签名团队；仓库不含描述文件。


## 7. 验证记录

这台构建机是 Linux（没有 Xcode），所以工程用三层手段自证：

1. **语法**：`swiftc -parse` 全部 38 个 Swift 文件，0 报错。
2. **逻辑类型检查**：把 Model + Services（词典、分词、变形、调度、解释、复习会话、AppModel）复制到临时目录，用最小 `ObservableObject/Published` 桩替代 SwiftUI，在 Linux 上用 Swift 6.0.3 跑 `-typecheck`，**0 错误 0 警告**。
3. **真实运行**：`Tools/verify_core.swift` 把四个引擎编译成命令行程序并跑真实数据，输出（节选）：

```
=== dictionary ===
entries: 11794
  N5: 674  N4: 630  N3: 1659  N2: 1778  N1: 3070  (—: 3983)

=== deinflection ===
食べました -> 食べる 敬体・过去     書いて -> 書く て形
高かった  -> 高い 过去式            行って -> 行く て形
読まなかった -> 読む 过去否定       起きられる -> 起きる 可能・被动形

=== tokenizer ===
昨日友達と映画を見に行きました → 昨日|友達|と|映画|を|見|に|行きました
カードで払えますか。            → カード|で|払えます|か|。
この店のラーメン、すごくおいしいよ。 → この|店|の|ラーメン|、|すごく|おいしい|よ|。

=== scheduler ===
新卡：good → 1 分钟 → 10 分钟 → 1 天 → 2.5 天（ease 2.5 → 2.58）
遗忘：间隔归零、ease 2.5 → 2.28、1 分钟后重学
```

4. **行为断言**：`./Tools/verify_logic.sh` 在 Linux 上用平台桩编译并运行决策层，输出：

```
== deck budgets ==
  PASS  new cards respect per-deck budget  — 3 cards
  PASS  deck A contributed its 2  — 2 from d1
== due reviews ==
  PASS  due reviews capped by deck limit  — 3 cards
== scheduler through the model ==
  PASS  first good ≈ 1 minute  — 1.0 min
  PASS  second good ≈ 10 minutes  — 10.0 min
  PASS  graduation to 1 day / again resets interval / again lowers ease
== session + undo ==
  PASS  rating moved the card forward / undo restored the card / undo rewound the index
== subtitle import ==
  PASS  srt parsed  — 3 cues（重复滚动字幕已去重）
  PASS  tags stripped / override blocks stripped / vtt cue settings ignored
  PASS  builder groups cues  — 1 clips；builder id is stable — sub-ep01-mp4-1
  PASS  builder records the cue offset — 1.0 s；clip json without start_seconds still decodes
  PASS  importSubtitleCues adds clips — 1 added；repeat import is idempotent — 0 added
== backup and interoperability ==
  PASS  tsv has five columns；tsv sanitizes tabs and newlines — 1 row(s), 5 column(s)
  PASS  backup round trip / empty backup rejected / newer schema rejected
== review load forecast ==
  PASS  today folds overdue cards — 2 today；day after tomorrow counted — 1 on day 3
== intensive listening: sentences ==
  PASS  sentences split by punctuation — 3 sentences；split helper keeps punctuation
  PASS  first sentence keeps cue start — 1.0；second cue starts the split line — s1 3.00 → s2 end 5.00
  PASS  untimed clip divides the window
== intensive listening: state machine ==
  PASS  repeat 1/3 replays → repeat 2/2 advances；A-B loop keeps the sentence
  PASS  auto-pause pauses / auto-pause marks waiting / resume clears waiting
  PASS  last sentence finishes；auto-pause toggle stores state；repeat count is clamped
  PASS  next respects the end；previous respects the start
== intensive listening: shadowing records ==
  PASS  shadowing keeps the newest three — 3 kept；keeps the latest take；keeps the rating
  PASS  records are scoped per sentence；latest lookup works
  PASS  shadowing survives a backup round trip；state file without the new key still decodes
== kanji layer ==
  PASS  kanji data parses — 2387 kanji；every entry has strokes, radical and meaning
  PASS  every entry has Japanese readings；levels cover N5-N1
  PASS  detail fields for 日 — 4画 rì 日；太阳；Chinese gloss covers N5+N4
  PASS  example words picked — 4 words；contain the kanji；carry reading and meaning
  PASS  example words prefer compounds；ordered by level
  PASS  kanji card reuses the 1-minute step — 1.0 min；graduates to a day
  PASS  kanji cards join the review queue；kanji stats per level；learned kanji counted
  PASS  kanji cards survive a backup round trip
ALL CHECKS PASSED
```

5. **结构自检**：`Tools/lint_swift.py` 检查括号平衡、重复类型声明、`app.xxx` 与 AppModel 成员的一致性；`Tools/check_initializers.py` 检查所有 `Struct(...)` 调用的标签名与顺序。
6. **构建自检**：`.github/workflows/ios.yml` 在 macOS 上构建后校验 `Kotoba.app` 里确实打进了 `Dictionary.json`、`SampleClips.json` 与可执行文件。

仍然需要 Xcode 才能确认的部分：SwiftUI 视图层的类型检查与真机布局。视图层全部使用 iOS 17 的稳定 API（`scrollTargetBehavior`、`containerRelativeFrame`、`.onChange(of:_:)` 双参闭包、`MainActor.assumeIsolated`），没有使用 iOS 18 才有的接口。

## 8. 许可

代码：MIT（见 `LICENSE`）。
词典数据：CC BY-SA 4.0，来源与署名见 `ATTRIBUTION.md`。
内置示例台词（`SampleClips.json`）为本项目原创文本，随代码一同以 MIT 发布。
