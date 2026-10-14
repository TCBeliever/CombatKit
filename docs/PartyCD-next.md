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

**狀態：未定案，等使用者決定範圍；建議放在 1.1.0 之後的版本。**

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
1. `tools/candidates.py` 的全集加入種族技能（種族的 skill line，`SkillLineAbility` 依 RaceMask），每一筆寫進 `tools/candidates_decisions.tsv`。12.1 的新種族也由工具列出，不手寫。
2. Spells.lua 加一張以種族分組的表（鍵用 `UnitRace` 的第二個回傳值 raceFile），`SpellsFor` 把職業和種族的技能合併成一列，排序規則照舊（主標籤，再偵測方式）。設定頁要能看到並勾選種族技能（例如在職業選單旁加種族選單，或在每個職業頁加一個「種族」分類），由實作的 session 提出方案。
3. 光環 ID 用 `tools/auradata.py` 從資料確認（施放 ID 和身上的光環常常不同）。
4. **冷卻分類 1166：** Stoneform、Fireblood 和人類、不死族的解控技能在同一分類，很可能就是「用了飾品，這些也一起進冷卻」的機制。要在遊戲裡量：隊友用飾品後，Stoneform 是否進入 30 秒冷卻；反過來是否也成立。量清楚之前，Stoneform 和 Fireblood 照自己的 120 秒計，並在 park lot 記一筆。

**待使用者決定：** 第一批的範圍（只加 defense＋control 的 7 個，還是連 burst 一起加、預設關閉）；Shadowmeld 的標籤；放在哪個版本。

## C. 候選清單的 24 筆建議新增

`docs/PartyCD-candidates.md` 的清單 (b)，加上 Incarnation: Tree of Life 33891。**待使用者挑選**；挑好的加進 Spells.lua（照分類設計的建構函式和標籤），光環 ID 用 `tools/auradata.py` 確認，進遊戲看得到再上。

## D. 小項

- 範例替身框：DandersFrames 從中間成長時，目前隊友 1 放右邊、隊友 2 放左邊；要進遊戲對照實際的隊伍排法，相反就對調 `SLOT_CENTERED`（UI.lua）。
- `tools/talentdata.py` 每跑一次都會改 TalentData.lua 的日期，資料沒變也一樣；改成內容有變才更新日期。
