# UWB Nearby Interaction 実装サマリ

## 変更概要
- UWB 測距の中核として `NearbyInteractionService` を新設し、`NISession` の生成・トークンの Base64 アーカイブ/復元・距離/方角の更新およびエラー状態を一元管理。
- WebSocket 経由で発行・受信する近距離トークン専用イベントを整理し、`BattleService`/`RemoteBattleService` に公開・購読 API を追加して Nearby Interaction シグナルをゲームセッションに橋渡し。
- DI で新サービスを提供し、`BattleViewModel` が近距離イベントを監視してトークン送信・受信・エラー通知をさばけるよう連携。
- バトル画面の下部に距離・方角・警告を示す `NearbyInteractionIndicator` を追加し、ステージ遷移時にサービスを注入して UI へ測距情報を表示。
- iOS 設定での権限説明文とエンタイトルメントに Nearby Interaction を追加し、UWB センサー利用の事前準備を完了。

## 意図と背景
- 端末間の UWB 近接測位をゲーム体験に組み込み、マッチング直後に距離・方角を表示する MVP を構築するため。
- トークン交換の業務ロジックを `BattleService` 経由に集約し、ネットワーク層と UI 層を疎結合のまま保つ設計。
- SwiftUI での表示は既存バトル UI を崩さずに状態・エラー・権限不足を明示。
- 権限プロンプト文言・エンタイトルメントを先に整備し、実機検証時の許可ダイアログやビルド設定で躓かないようにする狙い。