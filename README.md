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
| 无障碍 | 全量 Dynamic Type（字号→系统文字样式映射，>26 pt 用 `@ScaledMetric`；视图层零硬编码字号）、VoiceOver 标签/hint/值与 `.isHeader`/`.isSelected` 语义、非颜色第二通道（熟悉度下划线、文字化的等级与评分）、尊重「减弱动态效果」 |
| 语法（数据集） | 个人页「语法」浏览 526 条分级句型（N5 81 / N4 98 / N3 101 / N2 123 / N1 123，OpenJLPT，CC BY-SA 4.0）：等级筛选、搜索、详情（接续 / 说明 / 例句 / 相关语法）、朗读、标记「学习中 / 已学会」；中文优先显示、英文可折叠；学习数据页显示语法统计 |
| 语法说明（点词） | 点词卡片里的「语法」区由本地规则引擎实时生成：词形还原 + 活用形名、前后助词的格角色、整句敬体/常体判断（填了 AI 配置时改由模型解释） |
| 朗读语音 | 统一入口、三种方式可切换：**服务器合成（推荐）** / Edge 直连 / 仅系统语音。失败时回落系统语音**并显示原因**（toast + 设置页），冷却 60 秒且按引擎分别计算，服务器模式失败后自动重试一次；语音可选 Nanami（女）/ Keita（男）/ 自定义 ID；音频按「语音+语速+文本」缓存（Edge 与服务器共用） |
| 云端转写（可选） | 默认关闭、地址留空即禁用；填好自己的转写服务后，导入 YouTube 片段时可请求带时间轴的日文字幕（可选中文翻译）。Kotoba 不内置地址/密钥，服务不可用时自动回退到「公开字幕 → 手动粘贴 / 字幕文件」 |
| 抓取 YouTube 字幕 | 粘贴链接后可一键读取 YouTube 公开字幕轨道（日语人工轨优先，其次自动轨），自动填好日文字幕、起止时间与逐行时间轴；失败时给出原因并保留手动粘贴 |
| 回声练习 | 每句按「听 → 懂 → 模仿 → 对比」四步练习，对比阶段复用跟读录音与自评（跟上了 / 再来一次） |
| 词状态 | 未收录 / 学习中 / 已认识三态，点词卡片上直接切换，与间隔复习调度对齐 |
| 内置例句片段 | 318 条随包片段（N5 52 / N4 62 / N3 64 / N2 66 / N1 74），每句都来自 Grammar.json 或 Dictionary.json 的真实例句，由 `Tools/build_clips.py` 确定性生成（同输入同输出），带逐行时间轴，可直接用于精听/回声 |
| 素材库 | 只整理你自己导入的片段：按估算 JLPT 等级、来源（YouTube / 本地 / 朗读）与文本筛选 |
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

## 5. 自建转写服务（可选，默认关闭）

Kotoba 没有自己的服务器。如果你有一台自己的机器（例如新加坡那台跑着 sherpa-onnx 的服务器），可以让它承担**转写**，Kotoba 只负责调用与回退。**本轮只实现客户端与契约，不在 peng 上实现服务端。**

### 5.1 在应用里怎么开

`设置 › 云端转写（可选）`：

| 项 | 默认 | 说明 |
| --- | --- | --- |
| 启用服务器转写 | 关 | 关着就完全不联网，所有旧流程照常 |
| 服务器地址 | 空 | 例：`https://asr.example.com`；也接受写成完整的 `…/transcribe` |
| 超时 | 90 秒（15–300 可调） | 每次请求的 `timeoutInterval` |
| 同时请求中文翻译 | 开 | 关掉则只取日文字幕 |

**Kotoba 代码里没有任何真实服务器地址、令牌或密钥。** 地址只存在你本机的状态文件里；鉴权请放在你的服务器或反向代理（Cloudflare Access / IP 白名单 / Basic Auth）上。没有填地址时，界面显示「已关闭 / 地址无效」，功能按钮不出现。

### 5.2 服务端必须提供的接口

**`POST {base}/transcribe`** · `Content-Type: application/json`

```json
{ "video_id": "dQw4w9WgXcQ", "format": "lines-v1", "translate_to": "zh" }
```

`translate_to` 只在开启翻译时出现。没有 `video_id` 以外的必需字段。

**成功 `200`**（`lines` 是必需字段；下列别名 Kotoba 都接受，便于对接不同实现）：

```json
{
  "language": "ja",
  "provider": "sherpa-onnx",
  "lines": [
    { "start": 12.40, "end": 15.10, "japanese": "すみません、これ、ください。", "chinese": "不好意思，请给我这个。" }
  ]
}
```

- `start`/`end`：秒（浮点）；`end` 可以缺省，Kotoba 会补 `start + 2`，并保证 `end ≥ start + 0.3`。
- 文本字段接受 `japanese` / `ja` / `text`；译文接受 `chinese` / `zh` / `translation`，缺省即无中文。
- 数组名接受 `lines` 或 `segments`；空行会被丢弃；结果按 `start` 排序。
- 只有当**每一行**都有译文时，Kotoba 才把中文写进片段的翻译栏，避免半中半日的错位。

**失败**：`4xx` 返回 `{"error": "…"}`，Kotoba **不重试**，直接把信息显示给用户；`429` / `5xx` / 网络错误会**重试 2 次**（共 3 次尝试，退避 1 秒、3 秒）；单次请求超过设定超时即视为失败。

**可选** `GET {base}/health` → `200`，`设置` 里的「测试连接」用它；返回 404 表示服务在线但没有该端点，可忽略。

**音频上传变体（契约保留，客户端未实现）**：`POST {base}/transcribe-audio`，`multipart/form-data`，字段名 `audio`，返回结构同上。Kotoba 本轮只实现「按视频 ID 转写」，上传本地音频尚未接线。

### 5.3 回退顺序（没有服务时完全可用）

1. 已配置且启用 → `POST /transcribe`；
2. 否则（或服务失败）→ 尝试 YouTube 公开字幕轨（`timedtext`）；
3. 都失败 → 留在表单里手动粘贴日文，或用「导入字幕（SRT / VTT）」。

每一步失败都会在卡片里写明原因，不假装成功。

### 5.4 给服务端的实现建议（不在本仓库）

- 复用你已有的 **sherpa-onnx**：`video_id` → 用 yt-dlp 只下音频（`-f bestaudio`，限时长/体积）→ 转写 → 输出上表的 `lines`；中文翻译走**你已有的模型配置**（与 Kotoba 的 AI 解释同一套服务即可）。
- 建议加：请求上限（如单次 ≤ 10 分钟音频）、磁盘缓存（同 `video_id` 直接回放上次结果）、并发 1–2、以及把 `provider` 填成 `sherpa-onnx` 方便排查。
- 隐私：视频/音频只在你自己的服务器上处理；Kotoba 只发 `video_id`（以及可选的语言/翻译开关）。

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

## 5.5 语法：数据集浏览 + 上下文规则引擎

两条互不替代的路径：

**（a）数据集浏览** —— `Grammar.json`，**526 条**（N5 81 / N4 98 / N3 101 / N2 123 / N1 123），由 `Tools/build_grammar.py` 从 OpenJLPT 的 `data/json/grammar/n1..n5.json`（commit `bf4e1eec…`）生成，CC BY-SA 4.0。个人页「语法」进入：等级筛选、搜索、详情页（接续 / 说明 / 例句 / 相关语法 / 朗读），可标记「学习中 / 已学会」，`学习数据` 页显示已学会 / 学习中 / 未标记三项统计。

**（b）上下文解释** —— 点开一个词时，「语法」段落由 `LocalContextExplainer` 用分词结果 + 词典现场生成：

```
原形是「見る」，这里用了敬体・过去。
后面跟着助词「を」，把「映画」标记为宾语。
整句是敬体（です・ます），适合对不熟的人说。
```

- 依赖：`Tokenizer` / `Deinflector`（70 条活用规则，带词典校验）+ `Dictionary.json`。
- `source` 会写「本地语法分析」；配置了 AI 服务时由远端模型回答，并标出模型名。
- 中文：**526 条全部译完**（释义 526/526、说明 526/526、例句 1526/1526，`zh_status = checked`，`en-fallback` 0）。中文优先显示，英文用「显示英文」按钮折叠，**英文永不删除**。译文为模型批量翻译后逐条对照英文核对；未译条目一律标记，绝不用猜的译文填空。

**中文覆盖（本轮实测）**：释义 526/526 ・说明 526/526 ・例句 1526/1526；`checked` **526**（N5 81 / N4 98 / N3 101 / N2 123 / N1 123）、`en-fallback` 0。

**还没有的**（诚实说明）：语法**没有 SM-2 间隔复习**，不进复习队列（记录模型目前按单词/汉字 id 键控，语法卡片类型尚未实现）；点词卡片**还不能跳到语法详情**，这是下一步。

## 6. 朗读语音：三种方式（默认服务器合成，静默回落）

所有朗读入口（字幕整段、重播、点词与例句、汉字例词、精听/回声的模式内朗读）都走同一个 `SpeechService`。设置里是三选一：

| 方式 | 行为 | 何时用 |
| --- | --- | --- |
| **服务器合成（推荐）** | `POST {地址}/tts`（JSON）→ 取回 MP3 → 播放 | 默认使用本机预填的 `https://asr.ysloving.com`；地址清空则**复用「云端转写」的服务器地址**，两者都空则退回 Edge 直连 |
| **Edge 直连** | 本机直连 Microsoft 的免费接口（WebSocket） | 服务器不可用、或想省掉代理 |
| **仅系统语音** | 完全不联网，只用 `AVSpeechSynthesizer` | 不想让任何文本离开设备 |

**默认行为**：这个构建预填了个人服务器 `https://asr.ysloving.com`（公开主机名、无密钥，可随时清空），因此开箱即按「服务器合成」工作；两个地址都清空后 → 退回「Edge 直连」（其失败再退系统语音）。三种方式都遵守同一条回落链：

```
离线 / 无语音 ID / 10 分钟内失败过  → 系统语音（不等待网络超时）
服务器或 Edge 返回 4xx/5xx、超时、空音频、非 MP3、解码失败 → 记录失败时间 → 系统语音（不弹窗）
成功 → 写入缓存（Library/Caches/EdgeTTS，50 MB LRU）→ 立即播放
```

### 6.1 服务器合成的接口契约（由 Hermes 部署，不在本仓库）

```
POST {base}/tts
Content-Type: application/json
{ "text": "こんにちは", "voice": "ja-JP-NanamiNeural", "rate_percent": 0 }

200 → Content-Type: audio/mpeg，MP3 字节
4xx/5xx → 任意 body（Kotoba 只显示状态码，不重试，直接回落）
GET {base}/health → 200（可选，用于自检）
```

- 地址接受 `https://host`、`https://host/` 或完整的 `…/tts`（自动补 `/tts`）。
- `rate_percent` 由应用已有的朗读速度映射（0.45→0，夹在 ±50）。
- 请求**不带任何鉴权头**：Kotoba 不内置令牌；需要鉴权请在你的反代上做。
- **单段上限 1000 字**（服务端校验：`String should have at most 1000 characters`，返回 400 且不回显原文）。因此长文本会在客户端按句读切分成 ≤1000 字的若干段，逐段合成并顺序播放，不会因为超长整段退回系统语音；单段仍超限时客户端也会在发请求前拦住。
- 400（参数/长度）与 5xx（上游失败）都按「静默回落」处理，不重试、不弹窗。
- 缓存键是 `SHA256(voice|rate|text)`，与来源无关——同一条文本无论来自 Edge 还是你的服务器都命中同一份 MP3。

### 6.2 本机验证结果（如实记录）

| 检查 | 结果 |
| --- | --- |
| Edge 端点可达 | ✅ 可达；语音列表 200（322 个语音，日语仅 Nanami / Keita） |
| Edge 真实合成（edge-tts 7.3.1） | ✅ 20,592 字节 MP3，48 kbps 单声道，mutagen 测得 3.43 秒 |
| 裸握手（公开文档） | ❌ WebSocket 升级 403；带上一轮有效令牌则 200 —— 说明 Microsoft 要求未公开的 `Sec-MS-GEC` 反滥用令牌 |
| 服务器合成（已上线） | ✅ 2026-11-06 用应用同款请求体 `POST https://asr.ysloving.com/tts`：**200**，`Content-Type: audio/mpeg`，`X-Voice: ja-JP-NanamiNeural`，`Cache-Control: no-store`，**20,592 字节**，`file` 识别为 MPEG ADTS layer III / 48 kbps / 24 kHz / mono，mutagen 测得 **3.43 秒**；1.65 秒返回 |
| Keita 音色 | ✅ 同一句话 200，19,008 字节，3.17 秒，`X-Voice: ja-JP-KeitaNeural`（Hermes 记录的是 11,232 字节，说明他们用的是更短的文本；同一文本以本表为准） |
| 参数校验 | ✅ 空文本 → **400** `String should have at least 1 character`；6000 字 → **400** `String should have at most 1000 characters`；两者都不回显原文 |
| 非法音色 | ⚠️ 返回 **502**（上游 `No audio was received`），属 5xx，客户端同样静默回落 |
| `/health` | ✅ 200，返回 ASR 模型与 TTS 语音列表 |

## 6.3 已修复的问题（v0.8.0 / v0.8.1）

- **v0.8.0**：朗读方式选择框此前绑定归一化后的 `effectiveMode`，未填地址时 `.server` 被归一成 `.edgeDirect`，勾选卡在第一行 —— 改为显示用户实际选中的模式；同时新增一次性升级迁移，为「无 `voiceOptions` 且转写地址为空」的旧存档补上默认地址。
- **v0.8.1（版本号尚未 bump）**：
  - 转写地址、朗读服务器、自定义语音 ID 改为**直接绑定**，去掉 `commit*` 与「保存」按钮；转写地址的 setter 会清空「测试连接」结果。
  - 地址去空白/去尾斜杠后若无 `://` 自动补 `https://`（显式 `http://` 不变）。
  - 语法进度恢复时剔除数据集里已不存在的 id。

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
== youtube captions ==
  PASS  caption tracks parsed — 3 tracks；prefers manual japanese over ASR
  PASS  json3 captions parsed — 2 cues；json3 timing kept；json3 text joined
  PASS  legacy XML captions parsed — 2 cues；XML entities and tags stripped
== youtube import with captions ==
  PASS  caption fetch pipeline works offline；caption clip imported
  PASS  caption clip keeps timings；caption clip is a youtube clip
== self-hosted transcription settings ==
  PASS  off by default；no server address baked in；trailing slash normalised
  PASS  endpoint gets /transcribe；timeout clamped；non-http and garbage addresses rejected
== transcription request shape / decoding / retry ==
  PASS  POST + JSON + video_id + translate_to；no Authorization header
  PASS  lines/segments aliases, sorting, empty-row drop, empty/html rejected
  PASS  retries 5xx then succeeds — 3 attempts；backoff [1.0, 3.0]；4xx not retried
  PASS  network failure after retries；disabled client never hits the network
== transcription integration ==
  PASS  AppModel refuses without configuration；server transcript becomes a clip
  PASS  timings kept；provider recorded；settings survive a backup；old backups stay off
== edge tts ==
  PASS  ssml voice / prosody / xml escaping；rate mapping 0 / -30 / +34，clamps ±50
  PASS  audio & turn.end frame parsing；truncated frame rejected；mp3 sniffing
  PASS  sha256 known vectors；cache key stable & varies by voice/rate
  PASS  fallback: disabled / no voice / offline / 10-min cooldown → system
  PASS  cache eviction under 1.5 KB cap，oldest first
  PASS  voice options default Nanami + prefer Edge；custom id trimmed；survive backup
== read-aloud 3 modes (server) ==
  PASS  mode matrix: no address → edge；transcription address → server；system-only wins
  PASS  legacy preferEdge=false → system only；server without address degrades to edge
  PASS  address resolution: own wins, transcription fallback, trimming
  PASS  POST /tts body {text, voice, rate_percent}；no auth header；timeout 15
  PASS  200+mp3 accepted；non-mp3 / empty / 5xx / transport failure mapped
  PASS  server audio lands in shared cache；key is source independent
  PASS  app wiring: transcription address promotes server mode；system-only reaches service
== echo session ==
  PASS  echo starts at listen → understand → imitate → compare
  PASS  echo wraps to next sentence；echo finishes after the last sentence
== word states ==
  PASS  unseen → known → learning → unseen transitions
== accessibility: typography scale ==
  PASS  small sizes map to caption styles；body size maps to body
  PASS  large display sizes map to title styles；mapping never decreases as size grows
  PASS  display sizes use @ScaledMetric path — threshold 26.0
OK: no hardcoded font sizes; 80 buttons checked (glyph-only ones labelled); charts expose values; colour has a second channel; Reduce Motion honoured
ALL CHECKS PASSED
```

5. **结构自检**：`Tools/lint_swift.py` 检查括号平衡、重复类型声明、`app.xxx` 与 AppModel 成员的一致性；`Tools/check_initializers.py` 检查所有 `Struct(...)` 调用的标签名与顺序。
6. **构建自检**：`.github/workflows/ios.yml` 在 macOS 上构建后校验 `Kotoba.app` 里确实打进了 `Dictionary.json`、`SampleClips.json` 与可执行文件。

仍然需要 Xcode 才能确认的部分：SwiftUI 视图层的类型检查与真机布局。视图层全部使用 iOS 17 的稳定 API（`scrollTargetBehavior`、`containerRelativeFrame`、`.onChange(of:_:)` 双参闭包、`MainActor.assumeIsolated`），没有使用 iOS 18 才有的接口。

## 8. 许可

代码：MIT（见 `LICENSE`）。
词典数据：CC BY-SA 4.0，来源与署名见 `ATTRIBUTION.md`。
内置示例台词（`SampleClips.json`）为本项目原创文本，随代码一同以 MIT 发布。
