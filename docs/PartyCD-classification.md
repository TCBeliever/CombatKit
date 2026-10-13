# Party CD：技能分類設計

> 已實作（commit 0767dfc 起）；第 4 節是目前 Spells.lua 的分類。

> 只用本插件自己的偵測後端與遊戲行為推出；不參照其他插件的分類。
> 由審查 session 撰寫，實作交給 clean session。

## 1. 兩件事分開

| | 決定什麼 | 誰用 | 一個技能有幾個 |
|---|---|---|---|
| **偵測方式**（`seen`） | 去哪裡找光環、怎麼判斷是誰放的 | Backend、Tracker | 剛好一個 |
| **用途標籤**（`tags`） | 設定頁分組、預設、光暈顏色 | Options、UI | 一個或多個，第一個是主標籤 |

程式碼依偵測方式寫，用途只是標籤。

## 2. 偵測方式（取代 `kind` + `area`/`lasts` + `delayed` + `notOnSelf`）

| `seen` | 建構函式 | 光環在哪 | 歸屬規則 | 參數 |
|---|---|---|---|---|
| `caster` | `Caster` | 施法的隊友自己（HELPFUL） | 持有者就是施法者 | |
| `ally` | `Ally` | 某一個隊友（HELPFUL），可以是自己 | 候選人含持有者 | |
| `otherAlly` | `OtherAlly` | 某一個隊友，不可能是施法者 | 候選人排除持有者 | |
| `allies` | `Allies` | 一次使用落在好幾個隊友身上 | `window` 秒內的出現都算同一次，不拿來修正冷卻 | `window` |
| `enemy` | `Enemy` | 對手（HARMFUL，arena1-3），施放當下出現 | 候選人；自己的施法優先 | |
| `enemies` | `Enemies` | 對手陸續走進的區域 | 同 `allies` | `window` |
| `enemyLater` | `EnemyLater` | 對手，施放後一段時間才出現（陷阱、圖騰、印記） | 自己的施法在 `fuse` 秒內都算自己的 | `fuse` |

保留不變的欄位：`aura`/`auras`、`casts`、`specs`、`charges`、`extraCharge`、`noLearn`。

## 3. 用途標籤

| 標籤 | 定義 |
|---|---|
| `defense` | 讓人不死：減傷、免疫、治療冷卻、解除或擋下讓人無法行動的控制（暈、恐懼、變形、沉默；**不含**定身與緩速） |
| `burst` | 提高自己或隊友的傷害 |
| `control` | 讓對手無法行動或無法出手（暈、恐懼、變形、沉默、繳械） |
| `other` | **剩下的**：不屬於以上三種就是 other，不另外挑 |

- 主標籤看「這個技能主要拿來幹嘛」；有第二用途才加第二個標籤。
- 另有布林 `big`：免疫和大型外部減傷，取代 `glow = "major"`。
- 光暈顏色由標籤推出，`glow` 欄位刪掉：有 `big` 是黃色，否則依主標籤：defense 綠、burst 紅、control 紫、other 藍。
- 設定頁依主標籤分組，順序 defense → burst → control → other；名稱「減傷／爆發／控場／其他」。
- 預設勾選規則不變：基礎冷卻 ≥ 60 秒。
- 帶 burst 標籤的自動 `noLearn`（爆發冷卻常被玩家的動作縮短或重置）。原本是爆發、改成 defense 的治療冷卻（Apotheosis、Invoke Chi-Ji、恢復的 Ascendance）手動保留 `noLearn`。

寫法示意：`Caster(48792, 120, "defense")`、`Allies(51052, 240, 8, "defense", { aura = 145629 })`、`EnemyLater(1122, 120, 2, "burst control", { aura = 22703 })`。

## 4. 這次分類的結果

原本標 `?` 的項目已依遊戲資料定案（見各條說明）；還要進遊戲確認的放在 `docs/park_lot.md`。粗體 = 主標籤和舊版不同。

**死亡騎士**
- caster：Icebound Fortitude、Lichborne、Vampiric Blood（defense）；Dancing Rune Weapon（burst defense）；Pillar of Frost、Army of the Dead（burst）
- ally：Anti-Magic Shell（defense；PvP 天賦 Spellwarden 讓它以 410358 落在隊友身上；`external = false`：主要是自己的，外部開關不隱藏它）
- allies 8：Anti-Magic Zone（defense）
- enemy：Asphyxiate、Strangulate、Blinding Sleet、Monstrous Blow（control）

**惡魔獵人**
- caster：Blur、Metamorphosis 復仇（defense）；Spectral Sight（other）；Metamorphosis 浩劫、The Hunt（burst）
- allies 8：Darkness（defense）
- enemy：Chaos Nova、Imprison、Illidan's Grasp、Void Nova（control）；Fiery Brand（defense；光環 ID 待遊戲內確認，見 park_lot）
- enemyLater 3：Sigil of Misery（control）

**德魯伊**
- caster：Barkskin、Survival Instincts、Tranquility、Ancient of Lore（defense）；Celestial Alignment、Berserk 野性、Tiger's Fury、Berserk 守護（burst）
- ally：Ironbark（defense）；Innervate（other）
- enemy：Mighty Bash、Incapacitating Roar、Maim、Faerie Swarm（control）
- enemies 8：Solar Beam（control）

**喚能師**
- caster：Obsidian Scales、Emerald Communion（defense）；Dragonrage、Deep Breath（burst）
- ally：Time Dilation、Time Stop（defense；資料沒有「排除施法者」屬性，可對自己放，遊戲內確認見 park_lot）
- allies 1：Rewind（defense；資料目標是範圍內所有隊友，同時落下）
- allies 8：Zephyr（defense）

**獵人**
- caster：Aspect of the Turtle（defense big）、Survival of the Fittest（defense）；Bestial Wrath、Trueshot、Takedown（burst）
- ally：Roar of Sacrifice（defense；資料沒有「排除施法者」屬性，遊戲內確認見 park_lot）
- enemy：Intimidation、Scatter Shot、Sticky Tar Bomb（control）
- enemyLater：Freezing Trap 60、Binding Shot 10（control；冰凍陷阱另含 PvP 天賦 Diamond Ice 的 203337）

**法師**
- caster：Ice Block（defense big）、Alter Time、Greater Invisibility、Mirror Image、三種護盾（defense）；Arcane Surge、Combustion（burst）
- allies 1：Mass Invisibility（other；資料目標是範圍內所有隊友，同時落下）
- enemy：Dragon's Breath（control）
- enemies 10：Ring of Frost（control）
- enemyLater 6：Snowdrift（control）

**武僧**
- caster：Fortifying Brew、Touch of Karma、Nimble Brew、Invoke Niuzao、Invoke Yu'lon（defense）；**Invoke Chi-Ji（defense）**：治療冷卻；Zenith（burst）
- ally：Life Cocoon（defense big）；Tiger's Lust（other）：只解定身與緩速
- enemy：Leg Sweep、Paralysis、Song of Chi-Ji、Grapple Weapon（control）

**聖騎士**
- caster：Divine Shield（defense big）、Divine Protection、Ardent Defender、Guardian of Ancient Kings、Aura Mastery、Sentinel、Guardian of the Forgotten Queen（defense big）；Avenging Wrath（burst）；**Avenging Crusader（defense burst）**：神聖專精的治療冷卻
- ally：Blessing of Protection（defense big）、Blessing of Sanctuary（defense）：解除控制
- otherAlly：Blessing of Sacrifice（defense；PvP 天賦 Ultimate Sacrifice 換成 199448，列在 auras 與 casts）
- enemy：Hammer of Justice、Blinding Light（control）

**牧師**
- caster：Dispersion（defense big）、Desperate Prayer、Divine Hymn、Ultimate Penitence（defense）；Voidform（burst）；**Apotheosis（defense）**：治療冷卻
- ally：Pain Suppression、Guardian Spirit（defense big）；Power Infusion（burst）
- allies 10：Power Word: Barrier（defense）
- enemy：Psychic Scream、Silence、Holy Word: Chastise（control）

**盜賊**
- caster：Cloak of Shadows（defense big）、Evasion（defense）；Adrenaline Rush、Shadow Blades（burst）
- enemy：Kidney Shot、Blind、Dismantle（control）；Deathmark、Kingsbane（burst）

**薩滿**
- caster：Astral Shift、Healing Tide Totem、Burrow（defense）；**Spiritwalker's Grace（other）**：移動施法；Ascendance 元素、增強、Stormkeeper（burst）；**Ascendance 恢復（defense）**：治療冷卻
- allies 6：Spirit Link Totem（defense）
- enemy：Hex、Pulverize、Lightning Lasso（control）
- enemyLater 3：Capacitor Totem（control）

**術士**
- caster：Unending Resolve、Dark Pact、Nether Ward（defense）；Summon Darkglare、Summon Demonic Tyrant、Malevolence（burst）
- enemy：Mortal Coil、Shadowfury、Howl of Terror、Seduction、Axe Toss（control）
- enemyLater 2：**Summon Infernal（burst control）**：主要用途是傷害，落地的暈眩只是偵測的訊號

**戰士**
- caster：Die by the Sword、Enraged Regeneration、Shield Wall、Last Stand、Berserker Shout（defense）：解除恐懼；Avatar、Recklessness、Bladestorm（burst）
- otherAlly：Intervene（defense）
- allies 10：Rallying Cry（defense）
- enemy：Storm Bolt、Shockwave、Intimidating Shout、Disarm（control）

**主標籤有變的：** 原本的 utility 4 個改成 other，另有 Spiritwalker's Grace、Invoke Chi-Ji、Avenging Crusader、Apotheosis、Ascendance 恢復、Summon Infernal。其餘照舊。

## 5. 實作順序（clean session）

1. Spells.lua 改用新的建構函式和 `tags`。在正規化的迴圈裡從 `seen` 推出舊欄位（`kind`、`area`、`lasts`、`delayed`、`notOnSelf`、`role`、`glow`），讓 Tracker、Backend、UI 先不用改，測試全過。
2. Options 頁改成依主標籤分組，新增 Locale「Other／其他」。`picked` 以法術 ID 存，不用轉換。
3. Tracker、Backend 直接讀 `seen`，再刪掉第 1 步推出來的舊欄位。
4. `tools/talentdata.py` 的 `watched_defs()`（以及 `tools/auradata.py`，如果它也解析 Spells.lua）改認新的建構函式名稱。
5. 進遊戲確認：已移到 `docs/park_lot.md`。

## 6. 名單來源（另一件事，之後做）

`tools/candidates.py` 只從 DB2 列出候選：各職業、專精、天賦、PvP 天賦中，有冷卻（≥ 20 秒）又會在某個單位身上留下光環的技能。依第 3 節的定義和預設規則挑選，在 Spells.lua 裡記下每一筆的取捨理由。其他插件的清單不進 repo。
