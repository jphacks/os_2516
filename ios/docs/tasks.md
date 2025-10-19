# デモ向けタスク一覧（2025-10-19）

目的: plan.md の4項目（走行判定+MP回復／MP不足時Attack不可／演出（音・振動）／Battle画面改善）をデモ品質で完了する。

参考: `docs/plan.md`・`RealFightingGame.xcodeproj/project.pbxproj`・該当Swiftファイル。

## P0: デモ必須（今日着手→当日内目標）

### 1) 走行判定確認 + MP回復
- [x] DI注入（必須）: `RealFightingGame/Presentation/Views/Battle/BattleStageListView.swift`
  - `NavigationLink` 遷移先の `BattleView(sessionID:service:)` に `motionService: container.motionService` を追加して渡す。
- [ ] 走行しきい値の調整: `RealFightingGame/Data/Motion/MotionService.swift`
  - `cadence >= 1.4` の見直し、ログ整備。
- [x] 回復ループの安定化: `RealFightingGame/Presentation/ViewModels/BattleViewModel.swift`
  - モーション購読（`updates()`）→ `updateManaRegenLoop(running:)` → `increaseMana(by:)` の動作確認。
  - 現行: +3/秒、上限は `maxMana`。体験次第で係数調整。
- [x] 権限キー追加（必須）: `RealFightingGame.xcodeproj/project.pbxproj`
  - `INFOPLIST_KEY_NSMotionUsageDescription = "走行検知に使用します。"` を Debug/Release 双方へ追加。
- [x] 実機確認: 走行中バッジ/歩数レート表示/MP回復を確認。許可未付与時は安全に無効。
  - 権限拒否時バナー表示と「設定を開く」導線を追加（`BattleView` / `BattleViewModel`）。
  - ログ拡充（権限・available・currentCadence/derived/used/Δsteps/Δt）。
  - ヒステリシス（開始1.6/停止1.2）、フォールバック（Δsteps/Δt）、ウォッチドッグ（3.2s, 端末に合わせて調整可）を実装。
  - チューニング資料 `docs/motion-tuning.md` を追加。

受け入れ基準
- 走行ONで MP が秒間一定量回復、OFFで停止。
- Battle画面に「走行中」表示（シミュレータ時はモックで再現）。

### 2) MPが無いとAttackできない
- [x] 機能確認のみ: 既にVM/UIで抑止済み。
  - VM: `BattleViewModel.attackTapped()` で `mana >= attackManaCost` をガード。
  - UI: `BattleView` の `Attack` ボタンを `disabled(mana < cost)` に連動。
- [x] ローカル権限でのMP管理: 攻撃時に即時消費（楽観的更新）を実装。
  - サービス（モック）側のMP操作は削除し、クライアント権限へ統一。
- [ ] UI改善: ボタンにコスト表記（例: `Attack (-5)`）、MP不足時のヒント表示。
- [ ] コストの一元化検討: `MockBattleService.Config.attackManaCost` と `BattleViewModel.attackManaCost` の整合。

受け入れ基準
- MP不足時に攻撃は送出されず、ボタンも押下不可でユーザが気付ける。

### 3) 演出（音・振動）
- [ ] ハプティクス微調整（任意）: `CoreHapticsService`/`UIKitHapticsService`
  - Attack/Hit/Special/Win/Lose の強弱・種類を調整。
- [ ] 効果音レイヤ追加（新規）
  - 追加ファイル: 
    - `RealFightingGame/Infrastructure/Audio/AudioService.swift`
    - `RealFightingGame/Infrastructure/Audio/AVAudioService.swift`
    - `RealFightingGame/Infrastructure/Audio/NoopAudioService.swift`
    - `RealFightingGame/DI/ServiceFactory+Audio.swift`
  - 音源: `RealFightingGame/Resources/Sounds/{attack.wav, magic_cast.wav, win.wav, lose.wav}`
  - Xcode設定: 上記音源を「Copy Bundle Resources」に登録。
- [ ] 呼び出し箇所: `BattleViewModel`
  - `attackTapped()`／`specialTapped()`／`result` 遷移時に `audio.play(...)` を呼ぶ。

受け入れ基準
- Attack/Special/Win/Lose のタイミングで重なりなく音が鳴り、ハプティクスと違和感がない。

### 4) Battle画面の改善
- [ ] ステータス表示の統一: `PlayerStatusView` を活用し、HP/MPの視認性向上。
- [ ] ボタンUI: Attackにコスト表示、Special準備完了時の強調（色/バウンド等）。
- [ ] ガード可視化: 残り有効時間を簡易ゲージで表現（`runEnergy` を転用）。
- [ ] アクセシビリティ: VoiceOverラベル/値、ヒント整備。Dynamic Type 最低限対応。

受け入れ基準
- 主要コンポーネントが一目で状態把握可能、誤操作が減る。

## 依存関係と順序
1) 走行判定の注入/権限キー追加 → 2) Attack抑止のUI改善 → 3) 音源とオーディオ層 → 4) Battle UI磨き込み。

## 担当割り振り（例）
- モーション/回復: `BattleStageListView.swift`・`MotionService.swift`・`BattleViewModel.swift`・`project.pbxproj`
- 演出（音）: Audio層新規作成＋VMフック＋リソース登録
- UI/アクセシビリティ: `BattleView.swift`・`PlayerStatusView.swift`・`BattleResultView.swift`
- ビルド/統合: Xcode設定、`xcodebuild test`、実機デモ確認

## テスト観点
- ユニット: `MockMotionService` で ON/OFF 切替→ MP回復/停止を検証。
- UI: Attackボタンの `disabled` 条件、Special準備完了時の強調表示。
- デバイス: 実機でCMPedometerとハプティクス/オーディオ遅延を確認。

## 受け入れ条件（デモ）
- Battle画面で「走行中」表示が出る（実機/モック）。
- 走行ONでMP回復が視覚的に増加し、OFFで止まる。
- MP不足時にAttack不可（UI/ロジック双方で抑止）。
- Attack/Special/Win/Lose で効果音とハプティクスが適切に鳴動。
- 改善後UIで主要情報（HP/MP/ゲージ/行動可否）が即時に把握できる。

## 実行コマンド
- ビルド: `cd RealFightingGame && xcodebuild -scheme RealFightingGame -destination "platform=iOS Simulator,name=iPhone 15" build`
- テスト: `cd RealFightingGame && xcodebuild test -scheme RealFightingGame -destination "platform=iOS Simulator,name=iPhone 15"`

## 変更予定ファイル一覧
- 既存: 
  - `RealFightingGame/Presentation/Views/Battle/BattleStageListView.swift`
  - `RealFightingGame/Presentation/Views/Battle/BattleView.swift`
  - `RealFightingGame/Presentation/ViewModels/BattleViewModel.swift`
  - `RealFightingGame/Data/Motion/MotionService.swift`
  - `RealFightingGame/Presentation/Components/PlayerStatusView.swift`
  - `RealFightingGame/Presentation/Views/Battle/BattleResultView.swift`
  - `RealFightingGame.xcodeproj/project.pbxproj`
- 新規（演出/音）:
  - `RealFightingGame/Infrastructure/Audio/AudioService.swift`
  - `RealFightingGame/Infrastructure/Audio/AVAudioService.swift`
  - `RealFightingGame/Infrastructure/Audio/NoopAudioService.swift`
  - `RealFightingGame/DI/ServiceFactory+Audio.swift`
  - `RealFightingGame/Resources/Sounds/*.wav`
