# 位置同期＆攻撃判定再設計プラン

## アプリ概要
- リアル空間で魔法バトルを行う iOS 向け対戦ゲーム。プレイヤーは移動しながら攻撃を発動し、HP/MP や命中判定をサーバーと同期する。
- iOS クライアントは SwiftUI + MVVM 構成で、位置・センサー情報を取得しつつ WebSocket 経由でゲームセッションを制御する。
- バックエンドは Go 製のリアルタイム判定サービスで、セッション管理、攻撃結果計算、イベント配信を担う。

## 変更背景
- UWB + Nearby Interaction を使った初期アプローチでは距離計測は成功したものの、テスト端末で方角が安定取得できず、攻撃判定に必要な精度を満たせなかった。
- フィールド運用では機種差・設置環境によるセンサー制限が致命的となるため、姿勢・攻撃タイミングの計算をサーバーへ寄せ、方角はクライアントの IMU 値を直接送る方式へ転換する。
- 0.5 秒ごとの位置更新と攻撃イベント時の即時位置・方位送信に統一することで、クライアント間の同期とログ解析を容易にし、将来的な ML/チート検知にも活用できるデータを確保する。

## 全体フロー
1. マッチング完了後、各クライアントは WebSocket でセッションへ参加し、`position_update` イベントを 0.5 秒間隔で送信。
2. バックエンドはプレイヤーごとの最新座標と向きを保持し、更新を全クライアントへブロードキャスト。
3. 攻撃操作時、クライアントは瞬時の `attack_triggered` イベントを送り、サーバーで命中判定 → 結果 (`attack_result`) を両端末へ返す。
4. サーバーは判定結果を永続化し、HP/MP 変化をイベントとして返送。クライアントは UI を更新し、必要に応じてハプティクスやエフェクトを再生。

## iOS 実装方針
### データ収集
- 位置情報: `CoreLocation` の `CLLocationManager` を高精度モードで稼働させ、`desiredAccuracy` を `kCLLocationAccuracyBestForNavigation` に設定。バックグラウンド利用を見越して権限文言を更新。
- 方位情報: `CoreMotion` (`CMMotionManager` or `CMDeviceMotion`) でヨー角を取得。攻撃瞬間の値をサンプルし、方位角 (0–360°) として送信。
- 座標表現: 緯度経度 + 標高 (任意) に加え、将来の屋内対応用にローカル座標 (x, y, z) も拡張できるよう JSON を設計。

### WebSocket イベントスキーマ（例）
```json
{
  "type": "position_update",
  "payload": {
    "playerId": "uuid",
    "timestamp": "2024-11-08T12:34:56.789Z",
    "location": { "lat": 35.0, "lon": 139.0, "alt": 5.2 },
    "heading": 123.4,
    "accuracy": { "horizontal": 0.8, "vertical": 1.5, "heading": 5.0 }
  }
}
```
```json
{
  "type": "attack_triggered",
  "payload": {
    "playerId": "uuid",
    "timestamp": "2024-11-08T12:35:01.123Z",
    "location": { "lat": 35.0, "lon": 139.0 },
    "heading": 118.0,
    "attackId": "uuid",
    "chargeLevel": 2
  }
}
```

### アプリ層の改修ポイント
- `Infrastructure/Network/GameMessage.swift` に新イベントタイプを追加し、DTO/UseCase 層で `PositionUpdate` と `AttackTrigger` を扱う。
- `Application/UseCases/GameSessionUseCase` に 0.5 秒周期タスクを組み込み、`Task` + `AsyncStream` でキャンセル可能にする。
- ViewModel 層 (`GameViewModel`) では現在位置のパブリッシュと攻撃ボタン押下時の追加メッセージ送信を実装。UI は相手位置をマップ枠/矢印などで描画し、サーバー戻り値で HP/MP を更新。
- ハプティクス: 命中確定 (`attack_result.hit == true`) で `CoreHapticsService` に通知。

### フェイルセーフ
- 権限未許可・位置精度不十分時は `position_update` を送信しないか、`accuracy` を閾値で判定し UI に警告表示。
- WebSocket 切断時はバッファリングせず、再接続後に最新位置のみ送信。
- テスト: `RealFightingGameTests` にモック WebSocket を追加し、周期送信がキャンセルされることと攻撃イベントの直後送信を検証。

## バックエンド実装方針
### WebSocket 層
- 既存の `session.Manager` に `HandleMessage` を追加し、`position_update` と `attack_triggered` をパース。
- `internal/domain/game` に `PositionSnapshot` と `AttackRequest` エンティティを定義し、セッション別にインメモリ保持。
- 位置更新はセッション内の全クライアントへ `position_broadcast` として即時送信し、UI をリアルタイム同期。

### 攻撃判定
1. `attack_triggered` 受信 → 最新の相手位置 (±200ms 以内) と比較。
2. 距離・方位差・攻撃種別 (charge level) を判定エンジン (`internal/game/attack`) に委譲。
3. 命中結果とダメージ量を算出し、`session.Manager.ApplyEvent` を通じて HP/MP を更新・永続化。
4. 両プレイヤーへ `attack_result` イベントを送信。内容には命中可否、残 HP/MP、ノックバック処理などを含める。

### 状態管理と永続化
- セッション接続中はインメモリで最新位置を保持し、既存の `BattleSession.Players` に `LastKnownPosition` を追加。
- 攻撃ログは `game.Events` として DB 保存。将来のリプレイ/レフェリー UI に再利用。
- 不正検知用途に、位置更新の履歴を一定期間リングバッファ保存し、移動速度が閾値超過した際にフラグ付け。

### テスト・監視
- `go test ./...` で `attack` パッケージにテーブル駆動テストを追加し、距離・角度境界ケースを網羅。
- WebSocket ハンドラは統合テストを用意し、`position_update` → `attack_triggered` → `attack_result` の往復を検証。
- ログ: 攻撃判定に使用した座標と時間差を構造化ログに出力し、将来的な可観測性基盤に接続。

## 今後の進め方
- [ ] iOS 側で位置/方位の権限フローとサンプル送信を実装し、スタブサーバーで疎通確認。
- [ ] バックエンドに `position_update` イベント処理と状態キャッシュを追加し、モックデータで負荷検証。
- [ ] 攻撃判定ロジックの仕様 (距離閾値・角度許容幅・MP 消費量) を `design.md` に追記し、クライアントとフォーマットを合意。
- [ ] 実機 2 台で 0.5 秒送信によるレイテンシと命中精度を計測し、閾値や頻度をチューニング。
