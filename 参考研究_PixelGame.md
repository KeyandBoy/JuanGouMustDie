# 参考项目拆解：《PixelGame / Legendarist》 → 对《卷狗必须死》的移植清单

> 分析对象：`D:\下载\谷歌下载\PixelGame-Public-master`（Unity 2019 + URP 2D，Rogue-Lite + MOBA 手感，商业 Demo 级别）
> 规模：9931 个文件 / 652 MB / 319 个 C# 脚本
> 分析日期：2026-11-04
> **本文只记录「学到什么」和「可以怎么用」，不改动本仓库任何游戏代码。**

---

## 0. 结论摘要（先看这段）

这个项目**好看、好玩，但代码是半成品**。它真正值得抄的不是"代码有多好"，而是：

1. **美术规范写得极死**（16×16 tile、实体描边色 `RGB(24,20,37)`、角色描边纯黑、命名规则、图层定义），所以整体观感统一。我们项目现在缺的正是这种"硬规范"。
2. **反馈密度极高**：伤害数字、震屏、顿帧、闪白、受击音、掉落音、BGM 信息条——每个动作都有 3~4 层反馈。这是我们最该补的差距。
3. **背包/物品/技能是"数据 + 通用 UI"**，虽然插件部分很重，但交互流（拖拽、堆叠、排序、Tooltip、快捷栏）是完整的，可以照着做轻量版。
4. **地牢生成算法有真东西**（模板插门 + 最远房对定入口出口 + 支路放宝箱），但他**没在用**（在 `Unused` 命名空间里），属于"可白拿的算法资料"。
5. **它的难度曲线、稀有度、升级、符文、存档全是 TODO**——所以这些别学它，反而要做得比它好。

**授权红线**：仓库是 **AGPL-3.0**。

- **代码**：一行都不能直接抄进闭源/非 AGPL 项目。只能"读懂思路、用 Godot 重写"。
- **素材**：仓库里混了大量第三方素材（Porforever、DANKIE、Hawk Quan 插件、Joystick Pack、TextMesh Pro 等），**不能直接用**。
- 能安全直接用的只有：**算法思路**、**数值/参数**、**规范**、**设计模式**。这份文档也只记录这些。

---

## 1. 架构拆解

### 1.1 分层与调度

- **常驻单例**（`DontDestroyOnLoad`）：`GameManager`、`AudioManager`、`ScoreManager`、`ExpManager`、`NotificationManager`、`CameraShaker`、`RenderManager`、`FadeTransition`。
- **调度核心是 `GameManager`**：
  - `OnSceneLoaded()`（GameManager.cs:120）是唯一的场景钩子——显示/隐藏玩家、切相机目标。
  - `LoadPlayerInfo()`（:153）造玩家、注入技能包、异步加载武器；`SavePlayerInfo()`（:244）存档。
- **事件总线**：静态 `Dictionary<EventType, Delegate>` + `Broadcast` 1~5 参重载（EventCenter.cs:136-195）。
  - 参数类型只在运行期校验；没有作用域、没有取消订阅保护；全项目 35 处调用。
  - 另外 `ScoreManager` 又搞了一套 C# `static event`，**两套事件系统并存**。

> **可借鉴**：Godot 里用 autoload `EventBus` + 强类型 signal（`signal enemy_died(kind: String, pos: Vector2)`）代替。比它的字典总线安全得多。
> **别学**：两套事件系统并存、无取消订阅——我们项目如果加事件总线，必须统一成一个。

### 1.2 Actor / 控制器（它想解耦，但没做到）

继承链：
```
AttackAbleActor (Attack / TryUseSkill 两个抽象)
  └ Actor (阵营、Facing、allowMove、Die)
      └ BaseController
          └ PhysicalObject2DController (Rigidbody2D 配置 + 切向投影滑墙 MovementX:70-140)
              └ BasePlayer (Health、WeaponBag、IInputManager、StopControl)
                  └ CommonPlayer / PlayerSword
敌人：EnemiesController → Enemies (头顶 InfoBar/HpBar) → Skeleton / Slime / Boss
```

**问题**：`Controller` 只管移动；输入、瞄准、开火、技能全塞在 `CommonPlayer.Normal_Update()`（:141-279），AI 塞在敌人 `Normal_Update() + Behaviour()`（:205）。所以"控制器解耦"只是名义上的。

> **可借鉴的正确形态**（我们要做的）：
> ```
> Actor（数据：血量/阵营/状态）
>   + Mover（CharacterBody2D + move_and_slide）
>   + Brain（Intent 输出：方向/朝向/是否交互/是否冲刺）
>       ├ PlayerBrain（读输入）
>       └ AIBrain（读感知）
> ```
> `Intent` 用一个 `Resource` 或小 `RefCounted`，玩家和 AI 可以互换，潜行/追击只换 Brain。

### 1.3 技能 / 武器

- `SkillDetail`（可序列化：冷却、tips、maxTimes）← `CommonSkillDetail.Builder` 链式构造。
- `SkillPack`：固定三槽（dodge / wp / displacement）+ 技能明细列表。
- `SkillManager`：每个 Actor 一个，`Init()` 建 `Dictionary<SkillDetail, float>` 冷却表，`UseSkill()` 校验 → 广播 → UI 遮罩 → 释放 → 写冷却。
- **技能行为全在 `DebugSkillImp` 里**（`ISkill` 只有一个 `Init`）——典型的"接口写了但没用"。
- 武器：`Weapon`（冷却、随机散射角、后坐力）→ `Gun`（弹夹/换弹/空仓音）→ Bow/Shotgun/Rifle；`Melee` + 动画事件开关碰撞体。
- `Rareness` 枚举只有 `Normal` 一个值，`WeaponData.level` 没人用 → **稀有度系统是 TODO**。

> **可借鉴**：
> - 每个技能一个 `Resource`（冷却、耗蓝、前摇、后摇、效果 id），运行时用一个 `Dictionary[String, float]` 记冷却。
> - 冷却 UI 不要像它那样直接摸 UI 节点（SkillManager.cs:196 写 `SkillBox.fillAmount`），改成 **signal 广播 → UI 自己更新**。
> - 武器/道具全部走 `Resource` + `.tres`，掉落用权重表 Resource。

### 1.4 血量 / 伤害 / 反馈

- `Health.TakeDamage()`（Health.cs:63）：无敌帧判定 → 扣血 → `MakeDamageNumber()`（:112）→ `Actor.SetTakeHit` → ≤0 时冻结 0.1s 再 `Die()`。
- `DamageOnTouch`：靠 tag + `GetComponent<Health>()`，Trigger Enter/Stay 都算伤害。
- `DamageNumber`：每帧 +75px 上浮、alpha −1.5/帧，位移满 100px 就销毁。
- `SpriteFlasher`（受击闪白）**写完了但全项目没有调用者**——受击实际只有震屏 + 动画。
- `CameraShaker`：圆内随机偏移，`InitShake` 取"更大者"而不是叠加。

> **可借鉴（这是差距最大的一块）**：
> 一个"命中"至少要给 4 层反馈：
> 1. 受击闪白（`ShaderMaterial` 的 `flash` uniform + Tween，0.08s）
> 2. 伤害数字（对象池 + 上浮淡出，我们已有 HUD 可复用）
> 3. 震屏（`Camera2D.offset` 噪声 Tween，按伤害分级）
> 4. 顿帧（`Engine.time_scale` 0.05，持续 2~3 帧）
> 再加一层音效 + 一层粒子，就是它那种"打起来很爽"的来源。

### 1.5 音频

- 1 个 BGM 源 + shoot/hit/ambient/npc 各 1 个 + **20 个随机池**（`InitRandomSource`）。
- `LoadAudio()` 用 `Resources.LoadAll` 按目录建 3 个字典。
- 音量存 `PlayerPrefs`，`SetUpFxVolume` 批量写。
- 播 BGM 时广播 `SetUpMusicInfo` → UI 显示曲名（`UiManager` 里那根"音乐信息条"）。

> **可借鉴**：
> - BGM 交叉淡入淡出（Tween 两条 `AudioStreamPlayer` 的 `volume_db`）。
> - SFX 用 `AudioStreamPolyphonic` 或 12 个 `AudioStreamPlayer` 池。
> - **"播放时把曲名/作者推到 UI"这个细节很提质感**，我们可以在标题画面加一条滚动曲名。
> - 总线音量存 `ConfigFile`，不要散落在各处。

### 1.6 场景切换

- `SceneUtil.LoadSceneWithLoading()` → `LoadAsyncScene`（`allowSceneActivation=false`，进度卡 0.9 等按键再激活，可以借机做"按任意键继续"）。
- 随机图在加载期 `Task.Run` 造数据、主线程实例化，`loadMapDataDone` 才放行。
- `FadeTransition`：代码生成 Canvas + Image，`pow` 曲线淡入淡出，完成时 `Destroy(this)`（和单例冲突，是个 bug）。

> **可借鉴**：Godot 用 `ResourceLoader.load_threaded_request/get_status` 做加载进度；淡入淡出用 autoload `CanvasLayer + ColorRect + Tween`，**不要自毁**。

### 1.7 它的"反面教材"清单（我们要避开的）

| 问题 | 位置 | 我们的对策 |
|---|---|---|
| 两套事件系统并存 | `EventCenter` vs `ScoreManager` static event | 只留一套强类型 signal |
| 接口写了没人实现 | `ISkill` 只有 `Init`；`SpriteFlasher` 无调用者 | 写接口就写实现，不留死代码 |
| 状态机靠反射 + 方法名约定 | MonsterLove `State_Enter/Update/Exit` | Godot 用 `enum State` + `match`，显式 enter/exit |
| UI 直接被逻辑层改 | `SkillManager` 写 `fillAmount` | signal 单向流：逻辑 → 信号 → UI |
| 存档用 `BinaryFormatter` | `GameManager.SavePlayerInfo` | JSON（`user://save.json`），字段显式版本号 |
| `if (false)` 导致只写不读 | `LoadPlayerInfo` | 存档必须有"写入→重启→读回"的回归测试 |
| 稀有度/等级/符文全是 TODO | `Rareness`/`WeaponData.level`/`RuneSystem` | 要么不做，要么真做完 |

---

## 2. 关卡 / 地图 / 难度

### 2.1 地牢生成（文档级参考，代码在 `Unused` 命名空间）

**核心算法：模板插门生长（比 BSP 更好控制观感）**

1. 房间是**位图模板**：白=地板、黑=墙、绿=门、红=刷怪点（`ParseTexture:1791`）。
2. 只认 **2 格宽**的门（`GenerateDoorList:1853`）。
3. 取已放房间的"未使用门"当插座，找同向同长的门插接（`TryToPlaceRoom:657`），`offX/offY` 由门位反推（:763）。
4. 碰撞规则：双方至少一方是 `None` 才允许重叠，墙可以融合（:780）。
5. 门立即雕成 `Tile.Door`，并写双向 `Edge`；房内门与门之间用八向距离建边（`CreateDoorEdgesWithinRoom:1065`）。
6. `FindPath:1092` 是门图 Dijkstra；`FindMostDistantRooms:959` 枚举房对取最长路 → 打标签：
   - `Entrance` / `Exit` / `Mandatory`（主路）/ `Sidetrack`（支路）。
7. **连通性由"插门生长"天然保证**，不需要事后连通性检查。
8. 默认参数：80×50、最少 11 房、`roomTries=250`、房间 8~18 格、重试预算 10/10/10（:145-149）。

另外还移植了 Hauberk 的迷宫生成（`_addRooms` / `_growMaze` / `_connectRegions` / `_removeDeadEnds` / `_streamLineCorridors`）和 Cave-Perlin（`CloseCellProb=45`），可作备选。

> **可借鉴到我们的随机校园**：
> - 我们现在的随机房间是"房间矩形 + 走廊"拼的，没有"房间类型"和"主路/支路"概念。
> - **最值得抄的是第 6 步**：用最远房对定"入口房间 / 出口房间"，再沿主路标 `Mandatory`，支路标 `Sidetrack`。
>   然后在 Sidetrack 上放保险丝/钥匙/宝箱，Mandatory 中点放安全屋，Exit 前 1 间放 Boss——**动线立刻有节奏**。
> - 门图 Dijkstra 可以直接换成 Godot 的 `AStar2D`。

### 2.2 它实际在跑的三张图

只有 3 个场景：`Town`（枢纽）、`Forest`（手摆的精英关）、`Random`（醉汉游走 + 三层墙自动拼）。

- `MapBuilder`：敌人数 = 步数/100 → 约 50 只；障碍 = /40 → 125 个；交互物 = /2000 → 2 个。
- 敌人表 6 种等概率，**含 Boss 预制体**。
- 无层数、无难度递增、无传送门；只能从暂停菜单离开。

> **别学**：敌人 1/100 格对"潜行"来说太密（我们建议 1/200），交互物 1/2000 太稀（每房间 0~1 个）。

### 2.3 敌人 AI

- Skeleton（持枪）：`alarm` 计数器驱动决策 tick（20~30 帧一次，低频决策，开销低）；`LineOfSight` 对 solid/pit 双 Linecast；远距离 45% 点射、否则 ±90° 游走；近距离后退并开火。
- Slime：`Normal/Attack/OnHit/Dead`；攻击期间无敌；视线内直线冲 40 帧。
- Boss：状态机**和普通骷髅完全一样**，只是 `while(Random.value>0.5)` 连发、移速 1950。**没有阶段**。
- Portal：刷怪门，2.1s 激活后每 1.1s 生 1 只。

> **可借鉴**：
> - **低频决策 tick（20~30 帧）**这个思路很好：潜行 AI 不需要每帧判断，省性能也更有"人在思考"的感觉。
> - 感知用两层射线（视线 + 遮挡），比 Godot 里直接算距离好。
> - 我们已有 `stalker`/`student`，可以把"巡逻→怀疑→追击→丢失"四段做成显式状态，替换现在的"纯距离追击"。
> - **Boss 一定要做阶段**（它没做，正是我们可以超过它的地方）：70% 血换招、40% 血狂暴、20% 血处决。

### 2.4 小地图 / 相机

- 不用 UI 画，而是**第二台正交相机**渲染到 200×200 的 `RenderTexture`（Point 过滤）。
- 相机位置 `Lerp` 后 **`Floor()` 取整**，抖动按 0.04s 量化并加方向性——专门避免 tilemap 接缝白线。
- 鼠标偏移 `offsetDir * amount`。

> **可借鉴**：Godot 用 `SubViewport(200×200)` + 第二个 `Camera2D` + `texture_filter=Nearest`；位置 `floor()` 对齐。
> **顺带**：主相机也应该 `position = position.round()`，这是像素游戏防抖动的标准做法（我们现在似乎没有）。

### 2.5 难度设计（它基本没做）

- 唯一成长：`ExpManager` 阶梯 400/700/1100/1700/2500/3600，6 级封顶，而且**百分比算错**（第 2 级起进度条不归零）。
- 经验只来自击杀：Slime +2、Skeleton +50（又 +2，重复）、Boss +3。
- `HardCoreDifficulty` 只写 `PlayerPrefs`，没人读——难度选项是假的。

> **别学**。我们的"答题正确率"天然就是难度旋钮，比它强。

---

## 3. 背包 / 装备 / 技能 / 成长 / 经济

### 3.1 它有什么

- `Q_Inventory`（第三方插件 "Hawk Quan Q Inventory System"）：
  - 18 格；`List<Item>` 下标即格子，空位用 `ID=-1` 的占位对象。
  - 堆叠（`maxStackNumber`，药水 99）、排序（按 `Variety` 顺序重排）、拖拽（`ItemDrag` + `Slot.OnDrop` 处理同包交换/跨包合并，**连冷却一起换**）。
  - 冷却中禁止排序/拖动。
- 物品数据：`Item : ScriptableObject`（ID、名称、图标、可堆叠、`Variety`、`Rarity`、买卖价、冷却、消耗/装备属性）。
- 装备：4 个部位（右手…左脚），游戏里只开放 1 个右手槽，**不支持拖拽装备**。
- 快捷栏：5 格，`GetKeyDown` 直接 `UseItem()`。
- 存档：`BinaryFormatter` 写 `Data.bin`，但读取分支 `if (false)` → **只写不读**。
- 商店/合成/宝箱：`WeaponChest`（数组随机）、`ChestLoot`（dropChance + min/max）、`Vendor.BuyItem`、`Crafting`（成功率掷骰）。**但正式场景里根本没有 Vendor/CraftTrigger**，闭环只活在插件示例场景。

### 3.2 关键判断

它是"**插件能跑，但游戏没接完**"。所以：
- **数据结构可以学**（格子、堆叠、排序、状态位）。
- **UI 交互流可以学**（Tooltip 悬停延迟、拖拽交换、右键使用）。
- **不要学它把存档做成二进制黑盒**。
- **不要学它的多币种 + exchangeRate**（我们一个"学分"足够）。

### 3.3 对《卷狗必须死》的具体转化（建议）

| 它的东西 | 我们的版本 |
|---|---|
| Exp（击杀获得） | **知识值**：答对 +10、答错 +2（保底，不惩罚到卡关）；连对 3/5/8 题 ×1.2/1.5/2.0 |
| 等级阈值 400/700/… | 100 / 150 / 220 / 330（×1.5 递增），6 级封顶 |
| Rune（符文，未实现） | **错题本/护符**：3 个槽，`activate()/deactivate()` 对称接口；例："错题本：每答对 3 题回 1 点理智" |
| 18 格背包 + 拖拽 | 先做 **12 格、点选→点放**（不做拖拽），堆叠 99，快捷栏 3 |
| 多币种 | **单一"学分"**；商店 3 件/章，20/30/50 定价，回收价 20% |
| 稀有度（TODO） | 我们做真的：正确率 ≥80% 稀有率 +15%，≥95% 必出 1 件 |
| 商店 | 每层结束开一次，只卖 3 件（回理智、提示符、护符） |
| 存档 | `user://save.json`，显式 `version` 字段，JSON 可读可改 |

**闭环**：答题 → 知识值/学分 → 买护符/道具 → 潜行更容易 → 活到下一层 → 更多题。
**把"答错"变成资源**：答错生成"残页"，5 张残页换 1 个"提示符"（下一题排除一个错误项）——惩罚变成可消耗的资源，玩家不会因为答错而挫败。

---

## 4. 值得抄的"手感清单"（按性价比排序）

1. **相机像素对齐 + 震屏曲线**（半天，立竿见影）
2. **受击四层反馈**（闪白/数字/震屏/顿帧）（1 天）
3. **伤害数字对象池**（已有 HUD，改成复用）
4. **BGM 交叉淡入 + 曲名 UI**（半天）
5. **小地图用 SubViewport 而非手绘**（1 天）
6. **房间类型标签 + 最远房对定入口出口**（2 天，关卡节奏提升最大）
7. **低频决策 tick 的敌人 AI**（1~2 天）
8. **背包/商店轻量版**（3 天，但要看需求优先级）

---

## 5. 美术 / UI / 音频规范

> 见下一节（资产盘点报告）。

---

## 6. 明确不做的事

- 不抄任何 C# 代码（AGPL-3.0）。
- 不抄任何美术/音频素材（第三方版权混杂）。
- 不做多币种、不做拖拽背包装备、不做 4 槽装备。
- 不学它的"稀有度/符文/难度选项只写枚举不实现"。
- 不引入第二套事件系统。

---

## 7. 关键文件索引（便于复查）

```
Assets\PixelGameAssets\Scripts\Core\GameManager.cs:120,153,244     场景钩子 / 造玩家 / 存档
Assets\PixelGameAssets\Scripts\EventManager\EventCenter.cs:136-195 事件总线
Assets\PixelGameAssets\Scripts\Damage\Health.cs:63,112             伤害与数字
Assets\PixelGameAssets\Scripts\Core\Audio\AudioManager.cs:107,146,201  音频
Assets\PixelGameAssets\Scripts\Actor\CommonPlayer.cs:141-279       输入/瞄准/技能全在这
Assets\PixelGameAssets\Scripts\Map\NewMap\DungeonGenerator.cs:657,959,1065,1092,1791,1853
Assets\PixelGameAssets\Scripts\Map\MapBuilder.cs:175,223,478,604   随机图与已知 bug
Assets\PixelGameAssets\Scripts\Camera\MinimapPixelCameraFollower.cs:83-105,155
Assets\PixelGameAssets\Scripts\Actor\Enemies\EnemySkeleton.cs:282  LineOfSight
Assets\Hawk Quan\Q Inventory System\Scripts\                      背包插件（参考交互，不抄）
Assets\PixelGameAssets\Sprites\README.md                           美术硬规范
```
