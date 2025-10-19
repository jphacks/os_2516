# 戦闘画面改善計画

_最終更新日: 2025-10-20_

## 目的

- `TASK_LIST.md` の戦闘画面タスクのうち、①Go サーバーの WebSocket を経由した相手位置の可視化、② 戦闘開始前の待機 UX を最優先で解決する。
- `ios/RealFightingGame` と `Server/internal` の既存構成に沿った改修方針を整理し、iOS/サーバー双方で同じ前提を共有する。

## 現状整理

- **サーバー (`Server/internal/api/router.go`)** は `position_update` を受けるたびに `wsServerMessage{kind:"position"}` を全接続へブロードキャストし、`session.Manager` が各プレイヤーの `LastPosition` を保持している。ただし初期の `init` メッセージには座標が含まれず、HP/MP のスナップショットのみが返される。
- **iOS データ層 (`RemoteBattleService`)** は `position` メッセージをデコードして `latestPositions` に蓄積し、`BattleTelemetry`（距離・相手方位）を算出しているが、緯度経度等の詳細はドメイン層へ露出していない。
- **iOS プレゼンテーション層 (`BattleViewModel` / `BattleView`)** は HP/MP とモーション状態を表示するのみで、相手位置インジケータや「待機中」フェーズが存在しない。`join` 完了後は `opponentPlayerId` が未確定でもすぐ `.inputting` に遷移する。

## マイルストーン A — 相手位置の可視化（最優先）

### サーバー側タスク

1. **セッション開始時に最新位置を共有できるようにする**

   - `newStatePayload` もしくは `wsStatePayload` を拡張し、初期 `init` メッセージで各プレイヤーの最終座標（lat/lon/heading/timestamp）をオプションで返す。
   - もしくは `AttachConnection` 後に一度だけ `position_snapshot` 的なメッセージを送る手も検討する。
   - 切断 → 再接続時も `session.Manager.UpdatePosition` が確実にブロードキャストされるよう挙動を再確認する。
   - `Server/internal/session/session_manager_test.go` にテストを追加し、更新された heading/timestamp の保持とブロードキャストを検証する。

2. **WebSocket 契約の明文化**
   - 位置系メッセージの形式とライフサイクルを `Server/README.md` もしくは専用ドキュメントに記載する。
   - 相手の接続/切断を待機 UI に渡せるよう、`info` メッセージなどの補助イベントも検討する。

### iOS データ層

1. **ドメインモデルの拡張**

   - `ios/RealFightingGame/Domain/Entities` に `BattleOpponentPosition`（緯度・経度・heading・更新時刻・精度）を追加し、UI が直接利用できる形にする。
   - `BattleTelemetry` あるいは `BattleState` を拡張して新構造体を保持しつつ、既存の距離/heading との後方互換を維持する。

2. **RemoteBattleService の改修**

   - `position` メッセージ処理時に、従来の telemetry 更新に加えて `BattleOpponentPosition` を生成・保存する。
   - `state` (`kind:"init"`) に位置情報が含まれる場合は初期値として適用し、未含有なら次の `position` まで待機する。
   - 自分と相手の更新時刻を比較し、2 秒以上古い更新は UI へ流さないなど鮮度チェックを挟む。
   - デコード結果を `AsyncStream` 経由で確実に `BattleViewModel` へ届けられるよう、`BattleState` の差分通知を整理する。

3. **テスト**
   - `RealFightingGameTests` に `Battle` 用フォルダを新設し、`wsServerMessage(kind:"position")` がドメインモデルへ正しく変換されること、古い更新がフィルタされることを検証する。
   - Go サーバーと同形式のフィクスチャを `Resources/Fixtures` に追加してシリアライズ互換性を担保する。

### iOS プレゼンテーション層

1. **ViewModel 公開プロパティ**

   - `BattleViewModel` に距離・方位・更新鮮度を含む `opponentIndicator`（仮）を追加する。
   - `RemoteBattleService` からの新しい `BattleState` が流れてきたときにインジケータを更新し、必要であれば端末の `LocationSample.heading` と組み合わせて相対方位を計算する。
   - 1.5 秒以上更新が無い場合は「捜索中…」などのフォールバック表示に切り替える。

2. **UI コンポーネント**

   - SwiftUI のオーバーレイ `OpponentLocatorView`（仮）を作成し、以下を表示する。
     - 方位差に応じた矢印表示
     - 距離（メートル/キロ換算）
     - 更新時刻や信号強度（古くなるほど色がフェードするなど）
   - `BattleView` の既存表示（ファイアボール演出等）を崩さないようオーバーレイ階層に組み込む。

3. **ハプティクス/サウンド連携（任意）**

   - 相手との距離が 5m 未満になったタイミングで軽いバイブ通知を送るなど、`RunStatusIndicator` との連携を検討する。

4. **UX 検証**
   - `ios/docs/motion-tuning.md` などに操作感のメモを追記する。
   - テレメトリ状態（近距離/遠距離/情報欠落）ごとの UI チェックリストやスナップショットテストを整備する。

## マイルストーン B — 戦闘開始前待機画面

### 想定挙動

- プレイヤーがセッションに参加したものの相手が未接続の場合、「対戦相手を探しています…」等の待機画面を表示する。
- 相手が接続し `opponentPlayerId` が確定した時点で自動的に戦闘画面へ遷移する。
- ユーザーが手動で待機を中止できるようにし、WebSocket セッションを適切にクローズする。

### 実装ステップ

1. **セッション状態フラグの活用**

   - サーバー側で `info` または `state` メッセージ内にセッションステータス（`waiting` / `active`）を明示する。`game.Session.Status` が既に存在するため、2 人目の参加時に `state` ブロードキャストされるか再確認する。
   - 必要であれば軽量な `opponent_joined` イベントを追加する。

2. **ViewModel のフェーズ管理**

   - `BattleViewModel.Phase` に `.waitingForOpponent` を追加し、`join` 完了時の `state.players` やセッションステータスに応じてフェーズを決定する。
   - `state` や `info` メッセージを監視し、相手参加後に `.inputting` へ遷移する。
   - 15 秒程度相手が現れない場合の案内表示やリトライ手段を提供する。

3. **UI への反映**

   - 魔法少女テーマのアニメーションとキャンセルボタンを備えた `BattleWaitingView`（仮）を作成する。
   - `BattleView` 内でフェーズに応じて待機レイアウトと戦闘レイアウトを切り替え、待機中はファイアボール演出やランインジケータを抑制する。

4. **終了処理の確認**

   - キャンセル/戻る操作時に `service.end()` を呼び、`locationStreamTask` や `motionStreamTask` などが確実に解放されるよう確認する。待機画面で不要な位置更新が開始しないようガードを入れる。

5. **テスト**
   - `RealFightingGameUITests` にて、モック `BattleService` が「1 人のみ →2 人参加」に変化した際の待機画面表示/解除を確認する。
   - `BattleViewModel` をモックストリームでテストし、`.waitingForOpponent` から `.inputting` への遷移が正しく行われることを検証する。

## 依存関係と連携事項

- プロトコル変更はバックエンド担当と都度すり合わせ、必要なら `hp_mp_api.yaml` に WebSocket スキーマを追記する。
- 待機画面のビジュアルはデザインチームに共有し、`ios/docs/plan.md` などに決定事項を記録する。
- 認証トークン期限切れ時の再接続シナリオでも待機/戦闘遷移が破綻しないか確認する。

## リスクと対策

- **位置情報の鮮度低下**: UI 側で鮮度チェックを行い、矢印が誤誘導しないようフォールバック表示を用意する。
- **バッテリー消費**: 0.5 秒周期を基本とし、UI 更新を 20Hz 以下に抑える。
- **サーバー負荷**: 初期スナップショット送信で WebSocket ペイロードが増加する可能性があるため、フレームサイズを監視し必要なら圧縮を検討する。
- **状態不整合**: `RemoteBattleService.log` や Go サーバーの構造化ログを活用し、相手参加/切断のトレースを残す。

## 今後の進め方チェックリスト

1. WebSocket スキーマ変更案をまとめ、バックエンドとレビューする。
2. モックデータを使って `OpponentLocatorView` の UI プロトタイプを検証する。
3. サーバー側で初期スナップショット送信とテストを実装する。
4. iOS データ層の改修とユニットテストを追加する。
5. ViewModel と UI を接続し、待機フェーズを導入する。
6. `design.md` / `tasks.md` を更新し、`xcodebuild test` と `go test ./...` を実行する。
7. 実機 2 台でエンドツーエンドを検証し、フィードバックを踏まえて演出を磨く。
