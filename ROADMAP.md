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
| **P1-3** | 全部字号写死为 `.system(size:)`，不支持 Dynamic Type，颜色承担了唯一语义 | Apple HIG：正文需可放大 ≥200%，不能只靠颜色 | 现在是无障碍不合格，而不是「体验稍差」 | 下一轮 |
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
