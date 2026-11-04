# 背景音乐曲库（自动生成，别手改）

> 由 `tools/music_catalog.py` 从 `assets/music/catalog.json` 生成，最后更新：2026-11-04。
> 要加歌/换歌/补缺口，改 JSON 再跑一次脚本，**不要直接改这个文件**。

**统计**：在用 9 首 · 备用 5 首 · 待补 5 条

## 一、在用曲目

| ID | 曲名 | 情绪 | 强度 | 状态 | 槽位 | 层角色 | 楼层 | 声音元素 | 授权 |
|---|---|---|---|---|---|---|---|---|---|
| `happy_loop` | Happy Loop | 欢乐 | 1 | menu、explore_calm、cleared | happy | base | all | 轻快鼓点、校园、明亮钢琴 | CC0 / wipics |
| `chase_pursuit` | Vicegrip of Pursuit | 紧张 | 3 | explore_alert | tension | base | all | 低频脉动、金属敲击、弦乐持续音 | CC0 / Sudocolon |
| `chase_electro` | Chase! | 追逐 | 4 | chase | chase | base | all | 电子琶音、急促鼓组、警报音色 | CC0 / Wolfgang_ |
| `goofy_attitude` | Goofy Attitude! | 荒诞 | 2 | quiz | absurd | base | all | 滑稽管乐、口哨、弹簧音效 | CC0 / SkyleTheFrench |
| `tyrant_dread` | Tyrant Dread | 恐怖 | 4 | tyrant | tyrant | base | 1、2、3、4 | 低频轰鸣、不谐和音簇、压迫感 | CC0 / in-project |
| `tyrant_dread_l5` | Tyrant Dread L5 | 恐怖 | 5 | tyrant | tyrant_l5 | base | 5 | 低频轰鸣、加速鼓点、不谐和音簇 | CC0 / in-project |
| `cutscene_dread` | The Childrens Room | 恐怖 | 3 | cutscene | cutscene | base | all | 稀疏钢琴、弦乐长音、走廊回响 | CC BY 4.0 / Jason Shaw (Audionautix) / 需署名 |
| `clear_victory` | Big Intro #2 | 胜利 | 3 | cleared | cleared | base | all | 铜管齐奏、上升音阶、明亮和弦 | CC BY 4.0 / Jason Shaw (Audionautix) / 需署名 |
| `gameover_somber` | Somber | 悲壮 | 2 | gameover | gameover | base | all | 下沉低音、低沉弦乐、空洞回响 | CC BY 4.0 / Jason Shaw (Audionautix) / 需署名 |

## 二、备用曲目（已入库，未接入）

| ID | 曲名 | 情绪 | 强度 | 建议用途 | 声音元素 | 授权 |
|---|---|---|---|---|---|---|
| `chase_assault` | Assault | 追逐 | 5 | 已入库未接入。建议留给 L4/L5 的高强度追逐（比 chase_electro 更硬）。 | 重鼓、失真贝斯、工业噪音 | CC0 / bambootracker |
| `fridge_hungry` | The Fridge is Hungry | 诡异 | 2 | 已入库未接入。适合做低警告时的诡异环境层，或暴君靠近 200px 的压迫层。 | 冰箱嗡鸣、怪异采样、不安持续音 | CC0 / congusbongus |
| `wacky_wobblings` | Wacky Wobblings | 荒诞 | 2 | 已入库未接入。可做连错/被罚站时的荒诞插曲。 | 滑音、玩具音色、摇摆节奏 | CC0 / Fupi |
| `tension_mid` | Night Runner | 紧张 | 3 | 给「按楼层递进」准备的中段紧张曲。现在方案还是 A（全关共用 chase_pursuit），所以先 standby；要开启 B：把本首改 active，并把 chase_pursuit 的 level_scope 改成 [1]。 | 持续低音、时钟滴答、渐强弦乐 | CC BY 4.0 / Jason Shaw (Audionautix) / 需署名 |
| `amb_tyrant_drone` | Horror Drone #1 | 压迫 | 3 | 暴君压迫层的临时替代素材：不是分轨，是独立整轨，只能低音量垫在 tyrant_dread 下面。接入前必须试听调性冲突；真要分层还是得做同 BPM 分轨。 | 低频轰鸣、嗡鸣、不安持续音 | CC BY 4.0 / Jason Shaw (Audionautix) / 需署名 |

## 三、待补曲目清单

| 缺口 | 目标状态 | 情绪 | 强度 | 层角色 | 楼层 | 期望的声音元素 | 建议来源 |
|---|---|---|---|---|---|---|---|
| 暴君压迫层（低频轰鸣 + 心跳） | tyrant | 压迫 | 5 | pressure | all | 低频轰鸣、心跳、喘息 | 真正的分轨缺口。`amb_tyrant_drone` 只能临时顶替，缺的仍然是「与 tyrant_dread 同 BPM 的压迫 stem + 心跳采样」。Freesound 补心跳，其余程序合成。 |
| 追逐节奏层（加鼓点） | chase | 追逐 | 4 | rhythm | all | 军鼓、底鼓、踩镲 | 警告 ≥2 时叠在追逐底曲上。必须与 chase_electro 同 BPM，且能独立循环。 |
| 走廊喘息/呼吸环境层 | explore_calm、explore_alert、tyrant | 恐怖 | 2 | ambience | all | 喘息、呼吸、极轻的风声 | 很轻、非旋律、可长时间循环。Freesound 找单声道采样自己拼，注意授权逐条查（避开 CC BY-NC）。 |
| 钟声 / 下课铃环境层 | menu、explore_calm、cleared | 诡异 | 2 | ambience | all | 钟声、下课铃、远处回响 | 校舍氛围点题用。可做成几十秒一次的点缀（accent），不必整段循环。 |
| L5 灯管闪烁 / 电流嗡鸣层 | tyrant | 压迫 | 3 | ambience | 5 | 电流嗡鸣、灯管爆闪、高频颤动 | 配合 L5 的灯光闪烁机制，随机触发短段比长循环更自然。Freesound 找 electrical hum / fluorescent buzz。 |

## 四、按状态索引

- **chase**：Chase!（active）、Assault（standby）、追逐节奏层（加鼓点）（missing）
- **cleared**：Happy Loop（active）、Big Intro #2（active）、钟声 / 下课铃环境层（missing）
- **cutscene**：The Childrens Room（active）
- **explore_alert**：Vicegrip of Pursuit（active）、The Fridge is Hungry（standby）、Night Runner（standby）、走廊喘息/呼吸环境层（missing）
- **explore_calm**：Happy Loop（active）、走廊喘息/呼吸环境层（missing）、钟声 / 下课铃环境层（missing）
- **gameover**：Somber（active）
- **menu**：Happy Loop（active）、钟声 / 下课铃环境层（missing）
- **quiz**：Goofy Attitude!（active）、Wacky Wobblings（standby）
- **tyrant**：Tyrant Dread（active）、Tyrant Dread L5（active）、Horror Drone #1（standby）、暴君压迫层（低频轰鸣 + 心跳）（missing）、走廊喘息/呼吸环境层（missing）、L5 灯管闪烁 / 电流嗡鸣层（missing）

## 五、按声音元素索引

- **上升音阶**：Big Intro #2
- **下沉低音**：Somber
- **下课铃**：钟声 / 下课铃环境层
- **不安持续音**：The Fridge is Hungry、Horror Drone #1
- **不谐和音簇**：Tyrant Dread、Tyrant Dread L5
- **低沉弦乐**：Somber
- **低频脉动**：Vicegrip of Pursuit
- **低频轰鸣**：Tyrant Dread、Tyrant Dread L5、Horror Drone #1、暴君压迫层（低频轰鸣 + 心跳）
- **军鼓**：追逐节奏层（加鼓点）
- **冰箱嗡鸣**：The Fridge is Hungry
- **加速鼓点**：Tyrant Dread L5
- **压迫感**：Tyrant Dread
- **口哨**：Goofy Attitude!
- **呼吸**：走廊喘息/呼吸环境层
- **喘息**：暴君压迫层（低频轰鸣 + 心跳）、走廊喘息/呼吸环境层
- **嗡鸣**：Horror Drone #1
- **失真贝斯**：Assault
- **工业噪音**：Assault
- **底鼓**：追逐节奏层（加鼓点）
- **弦乐持续音**：Vicegrip of Pursuit
- **弦乐长音**：The Childrens Room
- **弹簧音效**：Goofy Attitude!
- **心跳**：暴君压迫层（低频轰鸣 + 心跳）
- **急促鼓组**：Chase!
- **怪异采样**：The Fridge is Hungry
- **持续低音**：Night Runner
- **摇摆节奏**：Wacky Wobblings
- **时钟滴答**：Night Runner
- **明亮和弦**：Big Intro #2
- **明亮钢琴**：Happy Loop
- **极轻的风声**：走廊喘息/呼吸环境层
- **校园**：Happy Loop
- **渐强弦乐**：Night Runner
- **滑稽管乐**：Goofy Attitude!
- **滑音**：Wacky Wobblings
- **灯管爆闪**：L5 灯管闪烁 / 电流嗡鸣层
- **玩具音色**：Wacky Wobblings
- **电子琶音**：Chase!
- **电流嗡鸣**：L5 灯管闪烁 / 电流嗡鸣层
- **稀疏钢琴**：The Childrens Room
- **空洞回响**：Somber
- **警报音色**：Chase!
- **走廊回响**：The Childrens Room
- **踩镲**：追逐节奏层（加鼓点）
- **轻快鼓点**：Happy Loop
- **远处回响**：钟声 / 下课铃环境层
- **重鼓**：Assault
- **金属敲击**：Vicegrip of Pursuit
- **钟声**：钟声 / 下课铃环境层
- **铜管齐奏**：Big Intro #2
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
| `cutscene_dread` | CC BY 4.0 | 是 | 是 | Jason Shaw (Audionautix) | https://audionautix.com/free-music/soundtrack |
| `clear_victory` | CC BY 4.0 | 是 | 是 | Jason Shaw (Audionautix) | https://audionautix.com/free-music/other |
| `gameover_somber` | CC BY 4.0 | 是 | 是 | Jason Shaw (Audionautix) | https://audionautix.com/free-music/soundtrack |
| `tension_mid` | CC BY 4.0 | 是 | 是 | Jason Shaw (Audionautix) | https://audionautix.com/free-music/soundtrack |
| `amb_tyrant_drone` | CC BY 4.0 | 是 | 是 | Jason Shaw (Audionautix) | https://audionautix.com/free-music/soundtrack |
| `gap_pressure_layer` | — | — | — | — | — |
| `gap_rhythm_layer` | — | — | — | — | — |
| `gap_breath_ambience` | — | — | — | — | — |
| `gap_bell_ambience` | — | — | — | — | — |
| `gap_l5_flicker_ambience` | — | — | — | — | — |

> 补素材站点：Audionautix（CC BY 4.0，**必须署名**）、Freesound（逐条看授权，避开 CC BY-NC）。新增曲目一律先确认 `commercial_ok` 再入库。
