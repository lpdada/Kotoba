# Kotoba 路线图（第一轮改进）

> 目标：把「个人可用的原型」提升到「专业级学习工具」的水准——不是功能堆叠，而是把每一个环节做到可信、可验证、可维护。
> 约束：保持免费自用、无付费墙、零第三方依赖、iOS 17+、离线优先；不复制任何产品的品牌、文案、视觉素材或受版权保护的内容。

## 1. 调研来源（本次实际打开并阅读的页面）

| 来源 | 取到的可复用方法 | 链接 |
| --- | --- | --- |
| Anki 文档 · Deck Options | 每日新卡上限、每日复习上限、学习阶梯、到期负载才是真正的调节旋钮 | https://docs.ankiweb.net/manual/deck-options.html |
| AnkiDroid（官方开源客户端） | FSRS 属于「算法可替换」的工程分层；统计、TTS、夜间模式是长期基线功能 | https://github.com/ankidroid/Anki-Android |
| WaniKani API v2 文档 | SRS 的「阶段」建模：解锁 0 → 开始 1 → 通过 → 烧尽 N；答错按下调阶段计算；间隔按小时/天分段 | https://docs.api.wanikani.com/20170710/ |
| jpdb FAQ | 卡片状态的含义、复习按钮的语义、「积压几百张到期卡该怎么办」的实操建议、难度分级列表 | https://jpdb.io/faq |
| Tofugu · Spaced Repetition 指南 | 间隔随表现伸缩；主动回忆（输入答案）优于选择题；复习时机应卡在「将要忘记之前」 | https://www.tofugu.com/japanese/spaced-repetition/ |
| jidoujisho（Android 沉浸学习套件，开源） | 视频/音频 + 字幕（SRT/ASS/SSA）+ 点选查词 + 一键导出带图卡到 Anki；句子挖掘（sentence mining）闭环 | https://github.com/arianneorpilla/jidoujisho |
| asbplayer（浏览器字幕播放器，开源） | 播放模式：跳过无字幕段、快进无字幕段、句首/句尾自动暂停、按次数重复；按掌握状态给词着色；阅读/词频/释义注释 | https://github.com/killergerbah/asbplayer |
| Yomitan（前 Yomichan，开源词典扩展） | 弹窗式查词、真人发音、笔顺图、自动建 Anki 卡、支持多种词典格式 | https://github.com/yomidevs/yomitan |
| LingoDeer 官网 | 由教师编写的语法主线课程；真人录音而非合成音；用故事练口语 | https://www.lingodeer.com/ |
| Apple HIG · Accessibility | 支持 Dynamic Type（正文至少可放大 200%）、不能只靠颜色传达信息、为辅助技术提供语义标签 | https://developer.apple.com/design/human-interface-guidelines/accessibility |

> 说明：Bunpro、Duolingo、Memrise、Busuu 的页面为 JS 渲染，本次只确认了站点存在与产品定位，没有取到可引用的正文，因此下文不把它们的细节当作依据。所有实现均为独立设计，未复制上述任一产品的界面或文案。

## 2. 现状盘点（Kotoba 已经具备）

片段流（本地视频 / YouTube 内嵌 / 无画面朗读）、词典驱动分词、点词查词与变形还原、离线语法解释 + 可选在线 AI 解释、生词本与分组、SM-2 变体调度与四档评分、整句卡片、难度估算与推荐排序、每日目标/连续天数/热力图/记忆率、成就、JSON 清单导入、本地媒体导入、YouTube 链接导入、设备内自检。

**结论**：作为「沉浸式学习器」，输入（素材）与输出（卡片）已经打通，但三处缺口使它停在原型层：素材入口不接受真实字幕、学习记录无法迁移、复习负载不可预测。

## 3. 差距表（按优先级）

| 优先级 | 差距 | 依据 | 为什么重要 | 状态 |
| --- | --- | --- | --- | --- |
| **P0-1** | 只能导入 JSON 清单，不能直接吃 `.srt` / `.vtt`；真实素材（影视、动画）几乎都只有字幕文件 | jidoujisho 支持 SRT/ASS/SSA；asbplayer 以字幕文件为一等公民 | 手工把字幕抄成 JSON 是最大的使用摩擦；不解决就没有真实语料 | ✅ 本轮完成 |
| **P0-2** | 只能导出 JSON，不能恢复；也没有和其他 SRS 互通的方式 | Anki 文档专设「Backups」章节；jidoujisho/Yomitan 都以导出到 Anki 为闭环 | 学习记录是唯一不可再生的资产；换机/误删即归零 | ✅ 本轮完成 |
| **P0-3** | 只有「现在到期多少」，看不到未来负载，容易堆积成几百张 | Anki 的每日上限设计、jpdb 的积压处理建议 | 间隔重复最常见的失败模式是负载失控；需要提前看见并调节 | ✅ 本轮完成 |
| **P1-1** | 只有整段循环，没有逐句精听/跟读 | asbplayer 的 auto-pause / repeat / condensed 模式 | 听力与口语是当前完全缺失的训练维度 | ✅ 第二轮完成 |
| **P1-2** | 没有任何汉字层（部首、音训读、笔画、例词） | WaniKani 的科目模型、Yomitan 的笔顺与汉字页 | 日语学习中汉字是独立知识体系，词汇卡片无法替代 | ✅ 第三轮完成（笔顺未接入，见 P2-7） |
| **P1-3** | 全部字号写死为 `.system(size:)`，不支持 Dynamic Type，颜色承担了唯一语义 | Apple HIG：正文需可放大 ≥200%，不能只靠颜色 | 现在是无障碍不合格，而不是「体验稍差」 | ✅ 第四轮完成（设备验证待 CI/真机） |
| **P1-4** | 没有语法点条目与语法复习（只有逐句语法分析） | LingoDeer 的语法主线课程；Anki 的 cloze 卡片形态 | 语法知识点的复现频率远低于词汇，需要独立队列 | 下一轮 |
| **P2-1** | 复习只做「看→评」，没有输入式回忆（听写、打字） | Tofugu：输入答案 > 选择题 | 主动回忆强度直接决定记忆效率 | 待排期 |
| **P2-2** | 动机设计只有连续天数 + 成就，没有周目标/断签保护 | Anki 的负载上限、WaniKani 的等级推进 | 长期坚持靠的是「可控的每日目标」而非奖励徽章 | 待排期 |
| **P2-3** | 词频/难度只有 1–5 频率带，没有「这篇素材里我不认识多少」的可读性评分 | asbplayer 的 comprehension 统计、jpdb 的难度分级 | 选素材时最需要的是「我现在看懂多少」 | 待排期 |
| **P2-4** | 字幕格式只到 SRT/VTT，没有 ASS/SSA 与双语对字幕 | jidoujisho 支持 ASS/SSA | 动漫字幕多为 ASS，双语字幕需要按语言拆行 | 待排期 |
| **P2-5** | 词典 4.1 MB JSON 启动时全量解码 | — | 冷启动与内存占用会随词典扩充线性恶化 | 待排期 |
| **P2-6** | `AppSnapshot` / `UserProfile` 的合成解码要求每个键都存在；新增非可选字段会让旧备份整体解码失败 | 本轮写兼容性断言时暴露 | 备份是唯一不可再生资产，字段演进必须能读旧文件 | 待排期（需自定义 `init(from:)`） |

## 4. 第一轮实现范围

1. **字幕导入**：`SubtitleParser` 解析 SRT/VTT（BOM、CRLF、序号行、`-->` 后的位置参数、`<i>`/`{\an8}` 标签、HTML 实体、重复滚动字幕），`SubtitleClipBuilder` 按「每段句数 / 最长秒数」切片生成片段，媒体文件名自动匹配，并为每条片段记录 `start_seconds`（播放从该句起循环），写入 `customClips`。
2. **备份与互通**：`BackupService` 解码备份（ISO8601 与旧格式双兼容）、生成 Anki 兼容 TSV；`AppModel.restore` 做校验并整体替换状态；设置页新增「从备份恢复」「导出 Anki 卡片」。
3. **复习负载预测**：`AppModel.reviewForecast(days:)` 输出未来 7 天到期分布与逾期数，复习页用柱状条呈现。

三项都属于「纯逻辑 + 少量视图接线」，因此可以在本机用 `Tools/verify_logic.sh` 做行为断言，而不是只靠肉眼。

## 5. 第二轮实现范围（P1-1）

1. **逐句精听引擎**（`IntensiveListening.swift`，纯值类型，可在 Linux 上断言）：
   - `IntensiveSentenceBuilder` 把片段切句：优先使用字幕导入时记录的 `line_timings`（真实 cue 窗口），没有则按字符数在片段窗口内均分；一行里含多个 `。！？` 会继续拆开。
   - `IntensiveEngine` 管理播放顺序：上一句 / 下一句 / 跳句、A-B 循环（本句无限重复）、句末暂停（开关）、重复 1–3 次、末句 `finished`，所有状态都是可打印、可断言的值。
2. **跟读**：`ShadowingRecorder`（AVAudioRecorder / AVAudioPlayer，iOS 专用）录音、回放、与原句对比播放；`ShadowingRecord` 通过既有 `PersistenceStore` 的 `Documents/Shadowing` 目录保存，每个句子只保留最近 3 条；评分（跟上了 / 再来一次）随记录落盘。
3. **界面**：片段页新增「精听」入口，打开时暂停并记住原播放状态，退出后恢复原来的区间、循环与倍速；精听页显示当前句（振假名 + 罗马字 + 中文翻译）、句表高亮、循环/句末暂停/重复次数/倍速的实时状态。
4. **兼容性**：`Clip` 新增可选的 `line_timings`，`AppSnapshot` 新增可选的 `shadowingRecords`，旧片段 JSON 与旧状态文件仍可解码（已有断言覆盖）。

## 6. 下一轮候选（按上面的 P1 顺序）

- 精听/跟读模式（逐句 A-B、自动暂停、变速、重复 N 次）
- 汉字层（KANJIDIC2 子集 + 汉字详情页 + 汉字卡）
- Dynamic Type 与 VoiceOver 全量接入（Theme 字体助手 + 语义标签 + 不依赖颜色的状态）
- 语法点库与语法复习队列（JLPT 分级）

## 7. 第三轮实现范围（P1-2）

1. **数据**：`Tools/build_kanji.py` 从 KANJIDIC2 生成 `Kanji.json`，覆盖常用漢字 ∪ 带 JLPT 标记的 2,387 字；字段含笔画、部首（Unicode Kangxi Radicals 区经 NFKC 归一化，不猜测）、音读、训读、拼音（声调符号由数字标记转换）、英文释义、学年、JLPT、频率。
2. **中文释义的取舍**：KANJIDIC2 无中文，`zh` 为人工核对的 N5+N4 小表（284 字，覆盖率 N5 100% / N4 100%）；其余字显示带标注的英文原义，宁缺不假译。
3. **界面**：汉字详情页（读音、意思、例词、加入复习、笔记）、汉字列表页（按等级/部首、搜索拼音/读音/意思）、生词页与词条页与点词卡片的汉字入口。
4. **复习**：汉字卡复用 `SpacedRepetition` 与四档评分，与生词、整句同队列；复习页用标签区分卡种。
5. **统计**：进步页新增按 JLPT 分档的汉字进度条；生词页显示已熟悉/复习中的汉字数。
6. **未做**：KanjiVG 笔顺（体积过大，不做半成品）——记为 P2-7。

## 8. 第四轮实现范围（P1-3）

1. **Dynamic Type**：`Model/AccessibilityMetrics.swift` 定义 `FontScale`（尺寸 → 系统文字样式映射，单调不减；>26 pt 走 `@ScaledMetric` 保留设计尺寸）。`Theme.font(size:weight:design:)` 与 `View.scaledFont(...)` 成为唯一入口，**343 处** `.system(size:)` 全部改为可缩放写法，视图层零硬编码字号（由 `Tools/check_accessibility.py` 强制）。
2. **VoiceOver**：80 个 `Button` 逐一检查，纯图标按钮全部补 `accessibilityLabel` + hint；卡片/行用 `.combine` 合成整句；进度环、热力图、复习预测柱、熟悉度分布补 `accessibilityValue`；SectionHeader 标记 `.isHeader`；装饰性画面 `.accessibilityHidden(true)`；Chip 与句子列表在选中时带 `.isSelected`。
3. **非颜色第二通道**：字幕词按熟悉度加**下划线**（生疏=实线、眼熟=点线、熟悉无标记）；等级、熟悉度、评分、难度一律有文字；图表数字始终可见。
4. **Reduce Motion**：生成画面（TimelineView 停止推进）、复习卡翻面动画、进度环动画三处尊重系统设置。
5. **大字号布局**：字幕区最大高度、汉字网格列数（改自适应）、生词释义行数随 `dynamicTypeSize` 变化。
6. **未做/未验证**：VoiceOver 实际朗读、200% 字号下的真机布局、Voice Control/Switch Control 均未在设备上验证（本机无 Xcode），只做代码层检查与结构性断言。

## 9. Miraa 调研与移植（第五轮）

### 9.1 公开资料（网站 + Google Play）

- 定位：把「你喜欢的视频/播客」变成学习材料——AI 生成双字幕、实时翻译、AI 讲解、Echo 四步法（Listen / Understand / Imitate / Compare）。
- 免费版有限额，主力是订阅（RevenueCat）；素材以 YouTube / 播客为主。

### 9.2 APK 静态分析（仅在本机，未安装、未登录、未调用其服务）

- 包体 83 MB，**Flutter**（`libapp.so` 19.3 MB Dart AOT + `flutter_assets`，`classes.dex` 只是壳）。依赖可从字符串确认：`youtube_player_flutter`（WebView 内嵌官方播放器，`playsinline` / `enablejsapi` / `modestbranding`）、`audio_service` / `audioplayers`、`dio`、`hive`、`sqflite`、`flutter_secure_storage`、`firebase_remote_config`、RevenueCat、`flutter_charset_detector_web`。
- YouTube 接入：解析 `ytInitialPlayerResponse` → `playerCaptionsTracklistRenderer.captionTracks[].baseUrl`（另有 `visitorData`、`timedText` 字样），即**从 YouTube 取字幕轨**；播放用官方内嵌播放器。
- 服务端：`api/myoland`（账号、配额）、`aiflow2`（`mjd_transcribe_task` / `transcribeTaskID` / `transcribeStatus` / `transcribedFileURL`，转写任务）、`analyzer(2)`（`/analyze`、`demo/proto`，AI 讲解）、`pay`（订阅）、CloudFront（媒体 CDN）。字符串里还有 `domain/podcast_index/rss_podcast_index_transcript`，说明播客 RSS 也是一等输入。
- 数据模型（从符号推断）：媒体来源（YouTube / 播客 RSS / 本地）→ `yt_parsed_response`（videoId、captionTracks）→ 转写任务 → 字幕段落 → 翻译 / AI 分析 → Echo 学习 → 单词状态（known / learning / unknown）。

### 9.3 结论：能搬什么、不能搬什么

| Miraa 的做法 | Kotoba 的取舍 | 原因 |
| --- | --- | --- |
| 服务端转写（无字幕的音视频也生成字幕） | **不做** | Kotoba 没有服务器，也不调用付费转写 API |
| 服务端 AI 双字幕翻译 | **不做** | 同上；离线/免费约束下无法诚实实现 |
| 从 YouTube 取字幕轨 | **做**：客户端解析 watch 页 → `baseUrl` → `timedtext`（json3/XML），仅当轨道公开时 | 纯客户端、无服务端、可失败可回退 |
| Echo 四步 | **做**：`EchoSession` + `EchoPracticeView`，复用逐句播放与录音 | 只是流程编排，不依赖后端 |
| KNOWN / LEARNING 词状态 | **做**：显式三态（未收录 / 学习中 / 已认识），与既有熟悉度、复习调度对齐 | 状态是本地数据 |
| 分级视频库 | **做**（限定）：只整理**你自己导入**的片段，按估算等级/来源筛选 | 不能打包第三方视频目录（版权），也没有服务端目录 |
| 品牌、文案、视觉、字幕内容 | **不碰** | 只学方法 |

### 9.4 本轮实现

1. `YouTubeCaptions.swift`：watch 页解析 + json3/XML 解析 + 轨道优选（日语人工轨 > 日语自动轨 > 其他），网络层可注入（测试离线跑）；失败时给出明确原因并保留手动粘贴路径。
2. `EchoSession.swift` + `EchoPracticeView.swift`：四步状态机与界面（听→懂→模仿→对比），对比阶段复用 `ShadowingRecord` 自评落盘。
3. `WordState` + `AppModel.setWordState`：未收录/学习中/已认识三态，点词卡片上可一键切换；复习调度保持原样。
4. `ClipLibraryView` + `AppModel.libraryClips`：按估算等级、来源、文本筛选自己的素材库。
5. `ClipImporterView`：YouTube 卡片新增「抓取日语字幕」，抓到的字幕带逐行时间轴写入片段（`line_timings`），精听与回声可直接逐句跳转。

### 9.5 本轮承认做不到的

- **自动中文翻译**：没有服务端、没有可用的离线 ja→zh 模型，抓到的只有日语原文；中文仍由用户手填或点词看解释。
- **无字幕视频的转写**：需要 ASR 服务，Kotoba 不做；只在视频自带（或 YouTube 已有）字幕时可用。
- **YouTube 字幕可能被拒**：无登录请求自动字幕时常被 403/429 挡住，界面会明确提示并引导手动粘贴，不假装成功。
- **打包的分级视频目录**：涉及第三方版权，Kotoba 只整理用户自己的素材。

## 10. 自建转写服务（第六轮：约束变更）

用户确认拥有自己的服务器（新加坡机器上跑着 sherpa-onnx），因此 §9.3/§9.5 里「服务端转写不做」的前提**改变了**。本轮只做客户端与契约，不在 peng 上实现服务端。

### 10.1 变更后的取舍

| 能力 | 之前 | 现在 |
| --- | --- | --- |
| 无字幕视频的转写 | 不做（无服务端） | **可选**：由用户自建服务提供，默认关闭 |
| 中文翻译 | 不做（无离线模型） | 由该服务顺带返回；服务端用用户已有的模型配置 |
| 公开字幕轨 | 做 | 保留，作为首选/回退之一 |
| 离线可用性 | 必须 | 必须：不配置服务时全部功能照旧 |

### 10.2 实现（客户端）

- `TranscriptionClient.swift`：`TranscriptionSettings`（默认关闭、地址为空、超时 90 秒可调、可选翻译）+ 请求构造 + 容错解析 + 重试策略（5xx/429/网络：共 3 次尝试，退避 1s/3s；4xx 不重试）+ 错误分类（未配置 / 地址无效 / HTTP / 解析 / 空结果 / 网络 / 取消）。传输与 sleep 均可注入，便于离线断言。
- `AppModel`：`transcription` 状态、`transcribeYouTube`、`importTranscribedClip`、`pingTranscriptionServer`（`GET /health`）；状态以**可选字段** `transcription` 存入快照，旧备份仍可解码。
- UI：`设置 › 云端转写（可选）`；`内容管理 › 导入 YouTube 片段` 在已配置时多出「服务器转写」按钮，抓到的时间轴写入 `line_timings`，精听/回声可逐句跳转。

### 10.3 接口契约

见 README §5：`POST {base}/transcribe`（`video_id` / `format` / `translate_to`）→ `{language, provider, lines:[{start,end,japanese,chinese}]}`；失败语义、重试、超时、`/health`、以及**仅契约未实现**的音频上传变体都在那里。

### 10.4 明确不做 / 不在本仓库

- 服务端实现（下载音频、调用 sherpa-onnx、翻译编排、限流、缓存）——由 Hermes 在用户服务器上部署，不在 peng 上做。
- 客户端音频上传（`/transcribe-audio`）：只有契约。
- 任何真实服务器地址、令牌、密钥：仓库里一律没有；鉴权由用户在自己的服务器/反代上做。
- 不复制 Miraa 的服务端转写/AI 翻译实现，也不复制其品牌、文案与视觉。

## 11. Edge TTS 朗读（第七轮）

### 11.1 为什么改

系统 `AVSpeechSynthesizer` 的日语合成音质生硬、断句机械；「听」是本应用的主线（点词朗读、精听、回声），音质直接影响跟读意愿。Microsoft Edge 的 read-aloud 是免费、免密钥的在线语音，日语 Neural 音色明显更自然。

### 11.2 实际发生了什么（协议验证）

- Edge 端点可达、语音列表可取（日语仅 Nanami / Keita 两个）。
- 用 `edge-tts 7.3.1` 成功合成 3.43 秒、48 kbps 的 MP3，文件有效。
- 但**按公开文档的裸 WebSocket 握手一律 403**：服务端要求 `Sec-MS-GEC` v2 令牌（`<16 hex CS64>-<64 hex SHA256>` + 匹配的 UA/版本），只有带有效令牌才 200；只给 SHA-256 半段仍 403。
- 该令牌的 CS64 部分在开源实现里是混淆代码（GPL-3.0），属于对方的反滥用机制。**决定不移植**：许可冲突 + 脆弱 + 与「不绕过对方保护」的原则冲突。

### 11.3 因此实现的形态

- 完整客户端（`EdgeTTSProtocol` 纯逻辑 + `EdgeTTSService` WebSocket/缓存），按公开协议：`speech.config` → `ssml` → 二进制音频帧 → `turn.end`。
- 默认开启，但**任何失败静默回落到系统语音**；离线、关闭、10 分钟内失败过都直接走系统，不等待网络超时。
- 缓存：`Library/Caches/EdgeTTS`，键 `SHA256(voice|rate|text)`，50 MB LRU。
- 语音：Nanami / Keita（服务端仅这两个）+ 自定义语音 ID 输入（未来新增音色可直接用）。
- 语速：复用应用已有的朗读速度，映射到 SSML `prosody rate`（±50% 截断）。

### 11.4 未做 / 待条件成熟

- 不实现 `Sec-MS-GEC`（见 11.2）。若 Microsoft 放开，或用户用自建代理补上握手，客户端无需改动即可工作。
- 未做流式播放（当前整段合成后播放，缓存命中即刻播放）。
- 未在真机验证音色与延迟（本机无 Xcode，也无有效令牌可测真实合成路径）。

## 12. 服务器合成朗读（第八轮）

### 12.1 为什么

第 11 轮把 Edge TTS 客户端做完了，但直连被 Microsoft 的 `Sec-MS-GEC` 反滥用校验挡住（公开握手 403），真机上大概率只能听到系统语音。既然用户有新加坡服务器（Hermes 负责部署 edge-tts 代理），把合成放到服务器上即可绕开这个死结：客户端只发一条 HTTPS POST，拿回 MP3。

### 12.2 实现形态

- 新增 `ServerTTSService`：`POST {base}/tts`，body `{text, voice, rate_percent}`，返回 `audio/mpeg`；地址自动补 `/tts`，无鉴权头，超时沿用 15 秒夹取；4xx/5xx、空 body、非 MP3、传输错误都归类为可回落错误。
- `SpeechService` 变成三模式路由：`server` / `edgeDirect` / `systemOnly`，共用同一条回落链（离线、10 分钟冷却、失败即系统语音），成功音频写入既有的 `EdgeTTSCache`（键与来源无关）。
- 默认规则：地址为空 → 实际走 `edgeDirect`（等价于旧行为）；`云端转写` 或朗读服务器填了地址 → 自动 `server`。
- 设置页：三选一 Picker + 朗读服务器地址（留空复用转写地址）+ 试听 + 「上次：Edge 直连 / 服务器合成 / 系统语音」。
- 兼容：`VoiceOptions.mode` 是可选字段，旧备份里只有 `preferEdge`；`preferEdge=false` 迁移为「仅系统语音」。

### 12.3 验证策略

服务器未部署，所以本轮**不做**端到端验证，只做客户端逻辑断言：模式选择矩阵、地址解析/默认、请求构造（方法/路径/头/JSON 字段/超时/无鉴权）、响应处理（200+MP3、非 MP3、空、5xx、传输异常）、缓存落盘与键稳定性、AppModel 向 SpeechService 的配置传递。全部使用可注入传输与固定 fixture。

### 12.4 服务器上线后怎么验

1. `curl -sS https://<host>/health` → 200。
2. `curl -sS -X POST https://<host>/tts -H 'Content-Type: application/json' -d '{"text":"こんにちは","voice":"ja-JP-NanamiNeural","rate_percent":0}' -o t.mp3` → `file t.mp3` 应显示 MPEG ADTS；用音频工具确认 2–4 秒、可播放。
3. 应用内：设置 → 朗读方式选「服务器合成」，点「试听」，指示器应显示「上次：服务器合成」；把服务器停掉再试听，应静默退回「上次：系统语音」，无弹窗。
4. 断网试听 → 立即系统语音（不等待超时）。

### 12.5 未做

- 真实服务器联调（等 Hermes 部署）。
- 服务器侧实现（不在本仓库）。
- 流式/分句并行合成（当前整段合成后播放，命中缓存即刻出声）。

### 12.6 服务器上线后的实测（2026-11-06）

- `POST https://asr.ysloving.com/tts`（应用同款 body，Nanami）→ **200**、20,592 字节、`audio/mpeg`、`X-Voice: ja-JP-NanamiNeural`、`Cache-Control: no-store`、MPEG ADTS 48 kbps / 24 kHz / mono、3.43 秒、1.65 秒返回。
- Keita 同句 → 200、19,008 字节、3.17 秒。**与 Hermes 记录的 11,232 字节不一致**：他们用的是更短文本，这里以本机实测为准。
- 参数校验：空文本 → 400 `at least 1 character`；6000 字 → 400 `at most 1000 characters`；都不回显原文。非法音色 → **502**（上游 `No audio was received`）。
- 契约修正：README 曾写 400，FastAPI 默认 422 且会回显原文；Hermes 已改为统一 400 且不回显。客户端本来就没有 422 分支（所有非 2xx 一律静默回落），本轮只加了两条断言固化这个行为。

### 12.7 本轮新增（配合实测）

- **1000 字上限**：`TextChunker` 按句读把长文本切成 ≤1000 字的段，`SpeechService` 逐段合成后顺序播放（缓存键按段计算）；单段仍超限时 `ServerTTSService` 在发请求前就拦截。
- **默认地址**：`ServerDefaults.baseURL = https://asr.ysloving.com` 作为「云端转写」地址的默认值，朗读模式因此默认解析为「服务器合成」；清空即退回 Edge 直连。地址只是主机名，无令牌。
- **禁用语义收紧**：`TranscriptionClient` 现在先看 `isEnabled`，关闭时不会发出任何请求（地址预填也不会）。

### 12.8 v0.8.0 真机问题修复（同轮）

- **选择框卡在第一项**：`SettingsView` 的 Picker 之前绑定的是归一化后的 `effectiveMode`；没有地址时 `.server` 被归一成 `.edgeDirect`，于是勾选回到「Edge 直连」，点「服务器合成」看起来没反应，试听走系统语音。改为新增 `selectedMode`（有存储值就用存储值，否则用 `effectiveMode`），Picker 的 get 与地址输入框的显示条件都用它；set 仍然写回 `voiceOptions.mode`。引擎内部（`reconfigureSpeech`）继续用 `effectiveMode` 做归一化，不变。
- **老用户拿不到预填地址**：v0.7.0 存档里没有 `voiceOptions` 且转写地址为空字符串，导致预填的默认地址从未生效。`AppModel.apply` 中新增一次性迁移：仅当「存档无 `voiceOptions`」且「转写地址为空」时填入 `ServerDefaults.baseURL`，并在 bootstrap 末尾持久化一次；0.8.0 之后用户主动清空的地址不受影响（那时存档已有 `voiceOptions`）。判定逻辑抽成可测的 `AppModel.shouldMigrateServerAddress(archivedVoiceOptions:transcriptionURL:)`，由 4 条断言覆盖。

### 12.9 验证轮（断言发现的问题）

- 新增断言覆盖：语法分析（`LocalContextExplainer` 的助词/词形/敬体输出）、汉字等级分组与搜索、复习调度上下界、v0.7 形态存档解码与迁移、以及 §12.8 的两个修复。
- **发现并修复**：拼音搜索此前区分声调（数据是 `rì`，用户输入 `ri` 搜不到）。`KanjiStore.search` 现在对查询与拼音都做去声调/忽略大小写折叠；断言同时覆盖 `ri`、`rì`、`RI`。
- 新增 `Tools/check_source_invariants.py`：在没有 Xcode 的机器上结构化确认「Picker 绑定 selectedMode」「迁移已接入 apply」「网络客户端不含鉴权头/密钥」，由 `verify_logic.sh` 调用。

## 13. 语法说明（本地规则引擎）

> 更正（后续轮次）：项目里现在**已有**语法数据集 `Grammar.json`（526 条，OpenJLPT，CC BY-SA 4.0），见 §14。本节描述的是**点词时的上下文解释**，两者并存：数据集负责「有哪些句型、属于哪一级」，规则引擎负责「这句话里的这个词为什么这样变」。

### 13.1 上下文解释来自规则引擎，不是查表

点开一个词时看到的「语法」段落由 `LocalContextExplainer` 在本地实时生成（不查句型表），输入只有三样：

| 输入 | 来源 |
| --- | --- |
| 分词与词形（lemma / formation / 助词） | `Tokenizer` + `Deinflector`（60+ 条活用规则，带词典校验） |
| 词义、词性、JLPT 等级、例句 | 打包的 `Dictionary.json`（11,794 条：OpenJLPT + JMdict 常用词 + 片假名外来语） |
| 汉字音训、释义、中文注解 | 打包的 `Kanji.json`（KANJIDIC2 子集，2,387 字） |

所以「语法解析」在本项目里 = **对一句真实字幕做形态与句法角色的现场判断**，而不是查表。

### 13.2 它实际会说什么

`WordExplanation.grammar` 的组成（按出现顺序，条件触发）：

1. `原形是「見る」，这里用了敬体・过去。` —— 词形还原 + 活用形名称；
2. `后面跟着助词「を」，把「映画」标记为宾语。` —— 后置助词及其格角色；
3. `它接在助词「に」之后，和前面的成分构成地点关系。` —— 前置助词的角色；
4. `整句是敬体（です・ます），适合对不熟的人说。` / `整句是常体（だ・である）…` —— 句子语体判断；
5. 动词额外提示「和助词的搭配会改变意思」。

`source` 字段标明引擎：本地引擎返回「本地语法分析」；填了 AI 配置时由远端模型返回（`source` 为模型名）。

### 13.3 等级分组与搜索（现有数据）

| 分组 | N5 | N4 | N3 | N2/N1 | 其他已标注 | 未分级 |
| --- | --- | --- | --- | --- | --- | --- |
| 汉字（2,387） | 80 | 160 | 200 | 202 | 193 + 191 + 1,110 | 251 |
| 词条（11,794） | 674 | 630 | 1,659 | 1,778 | — | 3,983（N1 3,070 另计） |

汉字搜索支持：字面、音读、训读（平假名归一）、中文释义、英文释义、**拼音（去声调、忽略大小写）**。

### 13.4 覆盖不到的（诚实说明）

- **没有语法点库**：被动、使役、条件形、授受等「句型」不会被单独列为条目并标注等级；`Deinflector` 只能识别活用形态并给出原形与形名。
- **依赖分词质量**：分词错了，助词角色也会错；规则引擎不认识省略、倒装、方言。
- **没有分级语法大纲**：无法回答「N4 该学哪些语法点」。
- **展望**：若要真正的语法层，需要引入带许可的语法点数据（如 JLPT 语法表），并为每点写判定规则/例句；本轮只做验证与文档，不引入第三方数据。

### 13.5 本轮验证覆盖

- 语法引擎：有解释、点名助词角色（`助词「を」` + `宾语`）、判断敬体/常体、对活用词给出「原形是…」、`source` 为「本地语法分析」。
- 分组与搜索：分组计数之和等于 2,387；字面优先；训读/释义/拼音（`ri`、`rì`、`RI`）都能命中「日」；素材库按等级筛选。
- 复习调度：间隔上限、ease 上下界、新卡 1 分钟阶梯。
- 老存档：v0.7 形态存档可解码、无 `voiceOptions`、触发地址迁移。
- 两个 v0.8.0 修复：`Tools/check_source_invariants.py` 结构化确认（见 §12.8/§12.9）。

## 14. 语法层：数据集、浏览与状态（本轮）

### 14.1 已实现

| 部分 | 内容 |
| --- | --- |
| 数据 | `Kotoba/Resources/Grammar.json`：**526 条**（N5 81 / N4 98 / N3 101 / N2 123 / N1 123），来自 OpenJLPT `data/json/grammar/n1..n5.json`，commit `bf4e1eec…`，CC BY-SA 4.0；中文策略为 `meaning_zh = null`、`zh_status = en-fallback`（英文原文照录，不机翻） |
| 构建 | `Tools/build_grammar.py`：固定 commit 拉取 → 字段改名 → 去重 → 写 `counts`/`total`；幂等（除 `generatedAt` 外重跑完全一致） |
| 模型 | `GrammarModels.swift`：`GrammarEntry` / `GrammarExample` / `GrammarFile` / `GrammarStatus` / `GrammarProgress` |
| 存储 | `GrammarStore`：载入、按等级分组与计数、搜索（句型/罗马字/接续/英文/标签）、`related(to:)`、状态与 `install(progress:)`（纠正失效 id） |
| 界面 | 个人页「语法」→ `GrammarBrowseView`（等级筛选 + 搜索 + 详情 sheet：接续、说明、例句、相关语法、朗读、学习状态切换）；`ProgressScreen` 新增「语法」统计卡（已学会 / 学习中 / 未标记） |
| 持久化 | `AppSnapshot.grammarProgress`（可选字段，旧存档仍可解码，缺失即视为空进度） |

### 14.2 未实现，以及原因

- **语法 SM-2 复习调度：没有做。** 没有间隔/到期日计算，也没有把语法加入复习队列。原因：现有 `ReviewSession` 的记录模型是**按单词/汉字 id 键控**的（`savedWord` / `sentenceCards` / `kanjiCards`），`SchedulingState` 通过它们间接挂载；本会话**没有实现 GrammarCard 类型**，也没有给 `ReviewSession.Item` 加 `kind: .grammar`。硬塞进现有队列会破坏「复习记录 ↔ 卡片」的一一对应，所以留到有明确卡片模型时再做。
- **词典/字幕跳转到语法详情：没有做。** 这是**下一步**：在点词卡片里按句型匹配（例如看到「〜ている」就链接到对应语法条目），需要先做句型到文本的匹配规则，避免误命中。
- **中文释义：不做机翻。** 上游只有英文，`meaning_zh` 保持 null 并在界面标注「英文原文」。

### 14.3 文档中的版本修复记录

- **v0.8.0 修复（已在 §12.8 记录）**：朗读方式选择框改为绑定「用户实际选中的模式」（此前用归一化后的 `effectiveMode`，未填地址时 `.server` 被归一成 `.edgeDirect`，勾选卡在第一行）；新增一次性升级迁移，为无 `voiceOptions` 且转写地址为空的旧存档补上默认地址。
- **v0.8.1 修复（本轮一并记录，版本号尚未 bump）**：
  - 转写地址输入改为**直接绑定** `app.transcription.serverURL`，setter 内清空「测试连接」结果；朗读服务器、自定义语音 ID 同样改为直接绑定，删掉 `commit*` 辅助函数与「保存」按钮。
  - `ServerTTSService.endpointURL` 与 `TranscriptionSettings.normalizedServerURL` 在去空白/去尾斜杠后，若地址不含 `://` 则补 `https://`（显式 `http://` 保留）。
  - 语法进度恢复时按当前数据集**剔除失效 id**（595 → 526 的换源遗留），但数据集未载入时不剔除，避免误清空。
