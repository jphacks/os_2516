# モーション判定しきい値の調整ガイド（iOS クライアント）

目的: 走行判定と表示の安定性/即応性を、端末やデモ環境に合わせて最小変更でチューニングするための指針です。

## 実装サマリ（現状）
- データソース
  - `currentCadence` 優先（CoreMotionの平滑化済み歩/秒）→ なければ `derived`（Δsteps/Δt）を使用。
  - 無更新タイムアウトでフェイルセーフ（既定: 3.2s）。
- 走行判定
  - ヒステリシス採用：開始と停止で別しきい値。
  - 表示用の歩/秒は上記ソース選択の値をそのまま表示。
- ログ
  - 使用ソースと両方の値を出力（例: `used=currentCadence` / `derived=1.56`）。

実装箇所: `RealFightingGame/Data/Motion/MotionService.swift` の `CoreMotionMotionService`。

## しきい値一覧（調整ポイント）
- `runStartThreshold: Double = 1.6`
  - 役割: 「待機中 → 走行中」へ遷移する開始しきい値（歩/秒）。
  - 上げる効果: 誤検出減（走り出しがやや遅れる）。
  - 下げる効果: 走り出しの反応が早くなる（早歩きでもONになりやすい）。
  - 目安: 1.4–1.8。

- `runStopThreshold: Double = 1.2`
  - 役割: 「走行中 → 待機中」へ戻す停止しきい値（歩/秒）。
  - 上げる効果: 停止に落ちやすい（歩きの端境でOFFになりやすい）。
  - 下げる効果: 小休止でもONを維持しやすい。
  - 目安: 1.0–1.4（`runStartThreshold` より必ず低く）。

- `watchdogTimeoutSec ≒ 3.2s`（内部フィールド: `lastEmitAt` に対する無更新間隔）
  - 役割: 一定時間コールバックが来ない場合に `cadence=0 / isRunning=false` を自動送出。
  - 長くする: 誤停止が減るが、完全停止の反映が遅くなる。
  - 短くする: 反応は速いが、端末によっては誤停止のリスク。
  - 目安: 3.0–6.0（端末の `CMPedometer` 更新周期が長い場合は延長）。

## 調整手順（推奨フロー）
1. 実機で目標ユーザ動作（早歩き/小走り/停止）を想定し、現状ログで `derived` と `currentCadence` の傾向を把握。
2. 期待よりONが遅い → `runStartThreshold` を下げる（例: 1.6 → 1.5）。
3. 期待よりOFFが遅い → `runStopThreshold` を上げる（例: 1.2 → 1.3）または `watchdogTimeoutSec` を短縮（3.2 → 3.0）。
4. 調整後、再ビルドして以下を確認:
   - ログ: `used=...` と `cadence=...` が期待通りに遷移。
   - UI: 「走行中」バッジと歩/秒表示が体感に合致。

## ログの読み方（主要例）
- `currentCadence=1.70 sps, derived=1.56 sps, used=currentCadence`
  - OSの平滑化値を採用。安定走行時に多い。
- `currentCadence=-1.00 sps, derived=1.95 sps, used=derived`
  - OS値が未提供（nil）なので歩数差分から推定。
- `cadence=1.73 sps, isRunning=true`
  - 表示/ロジックで最終採用した歩/秒と走行状態。
- `watchdog timeout -> cadence=0, isRunning=false`
  - 無更新タイムアウトによるフェイルセーフ停止。

## 既知の注意点 / メモ
- 端末によって `CMPedometer` の更新周期・`currentCadence` の安定までの時間が異なります。閾値は実機で調整してください。
- 画面表示の即応性をさらに上げたい場合は、表示のみ短い固定窓（0.5–1.0s）で `derived` を再計算する拡張も可能です（別タスク）。

---
最終更新: 2025-10-19
