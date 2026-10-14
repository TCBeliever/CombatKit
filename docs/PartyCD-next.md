# Party CD：下一輪工作

> 1.1.0 之後的工作說明，給實作的 session 用。只含我們自己的設計、遊戲事實與 Blizzard API／材質事實；不參照、不打開其他競技場冷卻插件的程式碼。
> 規則照舊：不打開 `AsIntendedCDs`、`KiraUI-Plugin*`、`../PartyCD-compare-archive`；技能清單只從 DB2 來（`tools/candidates.py`）。

## A. 光環還在時的高亮：改用 Blizzard 內建的動畫材質

**現況：** UI.lua 的 `icon.halo` 是四條邊框，依標籤上色、呼吸閃爍（`GLOW`、`UI.GlowOf`）。

**要的：** 換成 Blizzard 內建的動畫邊框，**顏色分類維持不變**（defense 綠、burst 紅、control 紫、other 藍、`big` 黃），這是第一優先。

**可用的材質**（客戶端內建，12.x 的插件都在用；使用者決定：外形和別的插件相似沒關係，用 Blizzard 材質就好）：

| 材質 | 樣子 | 逐格動畫 |
|---|---|---|
| `Interface\SpellActivationOverlay\IconAlertAnts`（材質檔） | 經典黃色螞蟻線 | 5×5 格，只播前 22 格（後 3 格是空的，播到會閃） |
| `RotationHelper_Ants_Flipbook`（圖集） | 新版細螞蟻線 | 格數在遊戲裡確認 |
| `UI-HUD-ActionBar-Proc-Loop-Flipbook`（圖集） | 新版較長、會轉動的光帶 | 格數在遊戲裡確認 |

**做法：**
1. 預設用經典螞蟻線，另外兩種可以做成設定裡的選項（主頁「高亮樣式」下拉選單），不急。
2. 上色：先 `SetDesaturated(true)` 把材質轉成灰階，再 `SetVertexColor` 用 `GLOW` 的顏色。直接染原色會讓藍、紫變暗。
3. 動畫：在圖示上方加一層 Texture，用 `AnimationGroup` 的 `FlipBook` 動畫，設好 rows／columns／frames，`SetLooping("REPEAT")`。材質比圖示略大一圈，大約多 20–40%，進遊戲調整。
4. **不呼叫** Blizzard 動作條的發光函式（那些是給動作條按鈕用的），**不引入** 其他人的發光函式庫，自己寫。
5. 退路：材質或圖集讀不到時（`SetAtlas` 回傳 false、`GetTexture` 為空），退回現在的四條呼吸邊框。
6. 開關照舊：由 Tracker 的狀態決定（`SetActive`），範例圖示列（`DrawSample`）也要用新的樣式。
7. 測試：tests 裡驗證顏色依標籤、退路生效、動畫隨狀態開關。

**要進遊戲確認：** 三種材質在 12.1 都還在；紫和藍在螞蟻線上看不看得清楚；大小和不透明度。

## B. 種族技能

**狀態：** 設定頁已經有（9cb853f）：職業選單最後的「種族」列出下表 10 個，可以勾選，爆發類用 `defaultOff` 預設關閉；資料在 Spells.lua 的 `ns.RACIALS` / `ns.RACIAL_LIST`（每筆帶 `race`、`raceID`，光環 ID 已從 DB2 查過）。**還沒接上追蹤**：隊友的種族沒讀，勾選目前不影響隊友那一列。建議放在 1.1.0 之後的版本，1.1.0 上架前設定頁的「種族」先隱藏（待使用者決定）。

DB2（12.1.0.69933）查到的事實：

| 技能（種族） | 施放 ID | 冷卻 | 冷卻分類 | 建議標籤 |
|---|---|---|---|---|
| Stoneform（矮人） | 20594 | 120 s | 1166（分類冷卻 30 s） | defense |
| Fireblood（黑鐵矮人） | 265221 | 120 s | 1166（30 s） | defense |
| Shadowmeld（夜精靈） | 58984 | 120 s | — | defense 或 other（待定） |
| Quaking Palm（熊貓人） | 107079 | 120 s | — | control |
| War Stomp（牛頭人） | 20549 | 90 s | — | control |
| Haymaker（庫爾提拉斯人） | 287712 | 150 s | — | control |
| Bull Rush（高嶺牛頭人） | 255654 | 120 s | — | control |
| Blood Fury（獸人） | 33697 | 120 s | — | burst，建議預設關閉 |
| Berserking（食人妖） | 26297 | 180 s | — | burst，建議預設關閉 |
| Ancestral Call（瑪格哈獸人） | 274738 | 120 s | — | burst，建議預設關閉 |

不加：Will to Survive（人類，59752，分類 1166、90 s）、Will of the Forsaken（不死族，7744，1166、30 s），這兩個由 PvP 飾品那一格處理；純位移類（Escape Artist、Darkflight、Rocket Jump、Spatial Rift）；沒有值得追蹤的光環的（Light's Judgment、Bag of Tricks、Arcane Pulse、Arcane Torrent、Wing Buffet、Tail Swipe）；小治療（Gift of the Naaru、Regeneratin'）。

**要做的：**
1. **讀隊友的種族。** `PartyCD.lua` 的 `Roster()` 為每個單位多讀 `UnitRace(unit)` 的第二個值（raceFile，例如 `Dwarf`；熊貓人三個 race ID 都是 `Pandaren`），用 pcall 包起來、確認是一般值（`plain`），和 `class` 一起放進名單。不需要 inspect。
2. **併進那一列。** Tracker 的隊友紀錄存 `race`；`Fit` 改呼叫 `ns.SpellsFor(class, sel, race)`，回傳職業技能加上該種族的技能，合併後照現有規則穩定排序（主標籤 defense → burst → control → other，再依偵測方式），同類保持原順序。名單更新時 GUID 沒變就沿用原紀錄（種族不會變）。
3. **註冊。** 種族技能也進 `ns.SPELL_BY_ID`、`ns.SPELL_BY_CAST`（偵測到光環、玩家自己施法都查這兩張表）；不進 `CLASSES_WITH`，改加 `ns.RACES_WITH[spellID] = { [race] = true }`，給需要知道「誰可能有」的地方用。
4. **不用改、但要確認的：**
   - Backend 照技能清單開槽位：種族技能是一般的友方（Caster）或敵方（Enemy）光環。
   - 歸屬：控場算給「有這個技能」的隊友（`Candidates` 看 `t.spells[def.id]`），戰爭踐踏自然只算給牛頭人。
   - 自我檢查：自己放 Stoneform，自己那一列要亮。
   - Inspect：種族技能沒有 `specs`、不在天賦樹裡，確認 inspect 不會把它們標成沒點而移出那一列（`SetAvailable`）。
5. **冷卻分類 1166。** Stoneform、Fireblood 和人類、不死族的解控技能同屬 1166（分類冷卻 30 s），很可能就是「隊友用了飾品，這些也一起進 30 秒冷卻」。做法：飾品的資料更新（`ARENA_COOLDOWNS_UPDATE`、`C_PvP.GetArenaCrowdControlDuration`）顯示某隊友剛用了飾品時，他的 Stoneform／Fireblood 若顯示可用，補上 30 秒冷卻。反方向（用 Stoneform 讓飾品進冷卻）不用處理：飾品那一格本來就由遊戲的資料畫。**先在遊戲裡量**：隊友用飾品後 Stoneform 是否進 30 秒冷卻；確認前照自己的 120 秒計，並在 park lot 記一筆。
6. **範例圖示列。** 測試模式（`DrawSample`）依玩家自己的種族一起顯示種族技能。
7. **出處。** `tools/candidates.py` 的全集加入種族技能（種族的 skill line，`SkillLineAbility` 依 RaceMask），每一筆寫進 `tools/candidates_decisions.tsv`；12.1 的新種族也由工具列出，不手寫。`tools/talentdata.py` 的 `watched_defs` 也會讀到 `ns.RACIALS` 裡的建構函式，確認它把種族技能的基礎冷卻寫進 TalentData 的 `base`。光環 ID 用 `tools/auradata.py` 再確認一次。
8. **設定頁。** 種族頁已經有；如果 1.1.0 先藏起來了，接上追蹤後再打開。
9. **測試**（假的後端與名單）：矮人隊友那一列有 Stoneform；`defaultOff` 的爆發類不出現、勾了才出現；牛頭人隊友的 War Stomp 被算到他頭上；兩個隊友都不是牛頭人時不出現；隊友用飾品後 Stoneform 被補上 30 秒冷卻（等第 5 點量完再定）；同一個隊友換位置（party1 → party2）時種族技能跟著走。

**待使用者決定：** Shadowmeld 的標籤（目前 defense）；1.1.0 是否先隱藏種族頁。

## C. 候選清單的 24 筆建議新增

`docs/PartyCD-candidates.md` 的清單 (b)，加上 Incarnation: Tree of Life 33891。**待使用者挑選**；挑好的加進 Spells.lua（照分類設計的建構函式和標籤），光環 ID 用 `tools/auradata.py` 確認，進遊戲看得到再上。

## D. 小項

- 範例替身框：DandersFrames 從中間成長時，目前隊友 1 放右邊、隊友 2 放左邊；要進遊戲對照實際的隊伍排法，相反就對調 `SLOT_CENTERED`（UI.lua）。
- `tools/talentdata.py` 每跑一次都會改 TalentData.lua 的日期，資料沒變也一樣；改成內容有變才更新日期。
