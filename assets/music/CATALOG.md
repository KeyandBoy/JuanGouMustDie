# 背景音乐曲库（自动生成，别手改）

> 由 `tools/music_catalog.py` 从 `assets/music/catalog.json` 生成，最后更新：2026-11-04。
> 要加歌/换歌/补缺口，改 JSON 再跑一次脚本，**不要直接改这个文件**。

**统计**：在用 6 首 · 备用 3 首 · 待补 9 条

## 一、在用曲目

| ID | 曲名 | 情绪 | 强度 | 状态 | 槽位 | 层角色 | 楼层 | 声音元素 | 授权 |
|---|---|---|---|---|---|---|---|---|---|
| `happy_loop` | Happy Loop | 欢乐 | 1 | menu、explore_calm、cleared | happy | base | all | 轻快鼓点、校园、明亮钢琴 | CC0 / wipics |
| `chase_pursuit` | Vicegrip of Pursuit | 紧张 | 3 | explore_alert | tension | base | all | 低频脉动、金属敲击、弦乐持续音 | CC0 / Sudocolon |
| `chase_electro` | Chase! | 追逐 | 4 | chase | chase | base | all | 电子琶音、急促鼓组、警报音色 | CC0 / Wolfgang_ |
| `goofy_attitude` | Goofy Attitude! | 荒诞 | 2 | quiz | absurd | base | all | 滑稽管乐、口哨、弹簧音效 | CC0 / SkyleTheFrench |
| `tyrant_dread` | Tyrant Dread | 恐怖 | 4 | tyrant | tyrant | base | 1、2、3、4 | 低频轰鸣、不谐和音簇、压迫感 | CC0 / in-project |
| `tyrant_dread_l5` | Tyrant Dread L5 | 恐怖 | 5 | tyrant | tyrant_l5 | base | 5 | 低频轰鸣、加速鼓点、不谐和音簇 | CC0 / in-project |

## 二、备用曲目（已入库，未接入）

| ID | 曲名 | 情绪 | 强度 | 建议用途 | 声音元素 | 授权 |
|---|---|---|---|---|---|---|
| `chase_assault` | Assault | 追逐 | 5 | 已入库未接入。建议留给 L4/L5 的高强度追逐（比 chase_electro 更硬）。 | 重鼓、失真贝斯、工业噪音 | CC0 / bambootracker |
| `fridge_hungry` | The Fridge is Hungry | 诡异 | 2 | 已入库未接入。适合做低警告时的诡异环境层，或暴君靠近 200px 的压迫层。 | 冰箱嗡鸣、怪异采样、不安持续音 | CC0 / congusbongus |
| `wacky_wobblings` | Wacky Wobblings | 荒诞 | 2 | 已入库未接入。可做连错/被罚站时的荒诞插曲。 | 滑音、玩具音色、摇摆节奏 | CC0 / Fupi |

## 三、待补曲目清单

| 缺口 | 目标状态 | 情绪 | 强度 | 层角色 | 楼层 | 期望的声音元素 | 建议来源 |
|---|---|---|---|---|---|---|---|
| 暴君压迫层（低频轰鸣 + 心跳） | tyrant | 压迫 | 5 | pressure | all | 低频轰鸣、心跳、喘息 | 暴君进入 200px 时叠加，离开淡出。必须与 tyrant_dread 同 BPM 同调性，否则会打架。优先程序合成（最稳），Freesound 只补心跳采样。 |
| 追逐节奏层（加鼓点） | chase | 追逐 | 4 | rhythm | all | 军鼓、底鼓、踩镲 | 警告 ≥2 时叠在追逐底曲上。必须与 chase_electro 同 BPM，且能独立循环。 |
| 走廊喘息/呼吸环境层 | explore_calm、explore_alert、tyrant | 恐怖 | 2 | ambience | all | 喘息、呼吸、极轻的风声 | 很轻、非旋律、可长时间循环。Freesound 找单声道采样自己拼，注意授权逐条查（避开 CC BY-NC）。 |
| 钟声 / 下课铃环境层 | menu、explore_calm、cleared | 诡异 | 2 | ambience | all | 钟声、下课铃、远处回响 | 校舍氛围点题用。可做成几十秒一次的点缀（accent），不必整段循环。 |
| 过场剧情 BGM | cutscene | 恐怖 | 3 | base | all | 弦乐长音、低音合成器、稀疏钢琴 | 现在过场是静音（AudioManager 在 cutscene 时返回空）。需要一首 30~60 秒、不循环、结尾能淡出的曲子。Audionautix 找 Cinematic/Ambient 分类。 |
| 通关结算 BGM | cleared | 胜利 | 3 | base | all | 上升音阶、明亮和弦、释然 | 现在通关直接复用 happy_loop，情绪不够。需要 10~20 秒的不循环胜利短曲。 |
| 失败 / 被抓 BGM | gameover | 悲壮 | 2 | base | all | 下沉低音、断裂音效、空洞回响 | 现在失败是直接淡出静音。需要 6~12 秒的下坠短句 + 尾部留白。 |
| 中段紧张曲（L2~L4 递进用） | explore_alert | 紧张 | 3 | base | 2、3、4 | 持续低音、时钟滴答、渐强弦乐 | 为将来「按楼层递进」准备：L1 用 chase_pursuit 的轻量版，L2~L4 用这首，L5 直接上 chase。 |
| L5 灯管闪烁 / 电流嗡鸣层 | tyrant | 压迫 | 3 | ambience | 5 | 电流嗡鸣、灯管爆闪、高频颤动 | 配合 L5 的灯光闪烁机制，随机触发短段比长循环更自然。Freesound 找 electrical hum / fluorescent buzz。 |

## 四、按状态索引

- **chase**：Chase!（active）、Assault（standby）、追逐节奏层（加鼓点）（missing）
- **cleared**：Happy Loop（active）、钟声 / 下课铃环境层（missing）、通关结算 BGM（missing）
- **cutscene**：过场剧情 BGM（missing）
- **explore_alert**：Vicegrip of Pursuit（active）、The Fridge is Hungry（standby）、走廊喘息/呼吸环境层（missing）、中段紧张曲（L2~L4 递进用）（missing）
- **explore_calm**：Happy Loop（active）、走廊喘息/呼吸环境层（missing）、钟声 / 下课铃环境层（missing）
- **gameover**：失败 / 被抓 BGM（missing）
- **menu**：Happy Loop（active）、钟声 / 下课铃环境层（missing）
- **quiz**：Goofy Attitude!（active）、Wacky Wobblings（standby）
- **tyrant**：Tyrant Dread（active）、Tyrant Dread L5（active）、暴君压迫层（低频轰鸣 + 心跳）（missing）、走廊喘息/呼吸环境层（missing）、L5 灯管闪烁 / 电流嗡鸣层（missing）

## 五、按声音元素索引

- **上升音阶**：通关结算 BGM
- **下沉低音**：失败 / 被抓 BGM
- **下课铃**：钟声 / 下课铃环境层
- **不安持续音**：The Fridge is Hungry
- **不谐和音簇**：Tyrant Dread、Tyrant Dread L5
- **低音合成器**：过场剧情 BGM
- **低频脉动**：Vicegrip of Pursuit
- **低频轰鸣**：Tyrant Dread、Tyrant Dread L5、暴君压迫层（低频轰鸣 + 心跳）
- **军鼓**：追逐节奏层（加鼓点）
- **冰箱嗡鸣**：The Fridge is Hungry
- **加速鼓点**：Tyrant Dread L5
- **压迫感**：Tyrant Dread
- **口哨**：Goofy Attitude!
- **呼吸**：走廊喘息/呼吸环境层
- **喘息**：暴君压迫层（低频轰鸣 + 心跳）、走廊喘息/呼吸环境层
- **失真贝斯**：Assault
- **工业噪音**：Assault
- **底鼓**：追逐节奏层（加鼓点）
- **弦乐持续音**：Vicegrip of Pursuit
- **弦乐长音**：过场剧情 BGM
- **弹簧音效**：Goofy Attitude!
- **心跳**：暴君压迫层（低频轰鸣 + 心跳）
- **急促鼓组**：Chase!
- **怪异采样**：The Fridge is Hungry
- **持续低音**：中段紧张曲（L2~L4 递进用）
- **摇摆节奏**：Wacky Wobblings
- **断裂音效**：失败 / 被抓 BGM
- **时钟滴答**：中段紧张曲（L2~L4 递进用）
- **明亮和弦**：通关结算 BGM
- **明亮钢琴**：Happy Loop
- **极轻的风声**：走廊喘息/呼吸环境层
- **校园**：Happy Loop
- **渐强弦乐**：中段紧张曲（L2~L4 递进用）
- **滑稽管乐**：Goofy Attitude!
- **滑音**：Wacky Wobblings
- **灯管爆闪**：L5 灯管闪烁 / 电流嗡鸣层
- **玩具音色**：Wacky Wobblings
- **电子琶音**：Chase!
- **电流嗡鸣**：L5 灯管闪烁 / 电流嗡鸣层
- **稀疏钢琴**：过场剧情 BGM
- **空洞回响**：失败 / 被抓 BGM
- **警报音色**：Chase!
- **踩镲**：追逐节奏层（加鼓点）
- **轻快鼓点**：Happy Loop
- **远处回响**：钟声 / 下课铃环境层
- **释然**：通关结算 BGM
- **重鼓**：Assault
- **金属敲击**：Vicegrip of Pursuit
- **钟声**：钟声 / 下课铃环境层
- **高频颤动**：L5 灯管闪烁 / 电流嗡鸣层

## 六、授权审计

| ID | 授权 | 可商用 | 需署名 | 作者 | 来源 |
|---|---|---|---|---|---|
| `happy_loop` | CC0 | 是 | 否 | wipics | https://opengameart.org/content/happy-loop |
| `chase_pursuit` | CC0 | 是 | 否 | Sudocolon | https://opengameart.org/content/pursuit |
| `chase_electro` | CC0 | 是 | 否 | Wolfgang_ | https://opengameart.org/content/chase |
| `goofy_attitude` | CC0 | 是 | 否 | SkyleTheFrench | https://opengameart.org/content/goofy-attitude |
| `tyrant_dread` | CC0 | 是 | 否 | in-project | generated in-project |
| `tyrant_dread_l5` | CC0 | 是 | 否 | in-project | generated in-project |
| `chase_assault` | CC0 | 是 | 否 | bambootracker | https://opengameart.org/content/assault |
| `fridge_hungry` | CC0 | 是 | 否 | congusbongus | https://opengameart.org/content/the-fridge-is-hungry |
| `wacky_wobblings` | CC0 | 是 | 否 | Fupi | https://opengameart.org/content/wacky-wobblings |
| `gap_pressure_layer` | — | — | — | — | — |
| `gap_rhythm_layer` | — | — | — | — | — |
| `gap_breath_ambience` | — | — | — | — | — |
| `gap_bell_ambience` | — | — | — | — | — |
| `gap_cutscene_theme` | — | — | — | — | — |
| `gap_clear_theme` | — | — | — | — | — |
| `gap_gameover_theme` | — | — | — | — | — |
| `gap_tension_mid` | — | — | — | — | — |
| `gap_l5_flicker_ambience` | — | — | — | — | — |

> 补素材站点：Audionautix（CC BY 4.0，**必须署名**）、Freesound（逐条看授权，避开 CC BY-NC）。新增曲目一律先确认 `commercial_ok` 再入库。
