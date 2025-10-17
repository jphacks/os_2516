# Implementation Plan

- [ ] 1. プロジェクト基盤とデータベースセットアップ

  - Go サーバープロジェクトの初期化とディレクトリ構造作成
  - Supabase データベースマイグレーション実装
  - 基本的な設定ファイルと DI コンテナの作成
  - _Requirements: 6.1, 7.1, 7.4_

- [ ] 2. ドメインエンティティとサービスの実装

  - Player、GameSession、Position、AttackAction エンティティの作成
  - GameRulesService と AttackJudgmentService の実装
  - ドメインサービスの単体テスト作成
  - _Requirements: 2.1, 2.2, 5.1, 5.4_

- [ ] 3. データベースリポジトリの実装

  - SupabaseSessionRepository の実装とテスト
  - SupabasePlayerRepository の実装とテスト
  - SupabaseGameHistoryRepository の実装とテスト
  - データベース接続とマイグレーション機能のテスト
  - _Requirements: 4.1, 4.3, 5.2_

- [ ] 4. サーバーサイドユースケースの実装

  - AttackUseCase の実装：攻撃判定とダメージ計算ロジック
  - SessionUseCase の実装：ゲームセッション管理ロジック
  - PositionUseCase の実装：位置情報更新ロジック
  - 各ユースケースの単体テストと統合テスト
  - _Requirements: 2.1, 2.2, 2.4, 1.1, 1.4_

- [ ] 5. WebSocket 通信基盤の実装

  - WebSocketManager と WebSocketHandler の実装
  - リアルタイムメッセージ配信システムの構築
  - 接続管理とエラーハンドリングの実装
  - WebSocket 通信の統合テスト
  - _Requirements: 6.4, 7.3_

- [ ] 6. サーバーサイド HTTP API の実装

  - GameHandler と SessionHandler の実装
  - RESTful API エンドポイントの作成
  - ミドルウェア（CORS、ログ、認証）の実装
  - API 統合テストの作成
  - _Requirements: 5.1, 5.4, 6.4_

- [ ] 7. iOS プロジェクト基盤の構築

  - SwiftUI プロジェクトの初期化とディレクトリ構造作成
  - 依存性注入コンテナ（DIContainer）の実装
  - 基本的なナビゲーション構造の構築
  - _Requirements: 6.1, 6.2_

- [ ] 8. iOS ドメイン層の実装

  - PlayerState、Position、AttackAction モデルの作成
  - GameDomainService の実装
  - PlayerStateRepository インターフェースの定義
  - ドメインロジックの単体テスト作成
  - _Requirements: 2.1, 2.2, 4.1, 4.3_

- [ ] 9. UWB 位置検出システムの実装

  - UWBPositionService の実装（Nearby Interaction フレームワーク使用）
  - FallbackPositionService（Bluetooth + センサー）の実装
  - 位置検出の精度テストと統合テスト
  - _Requirements: 1.1, 1.2, 1.3_

- [ ] 10. iOS ネットワーク通信の実装

  - WebSocketNetworkService の実装
  - サーバーとのリアルタイム通信機能
  - ネットワークエラーハンドリングと再接続機能
  - 通信レイテンシーのテスト
  - _Requirements: 6.4, 7.3_

- [ ] 11. 振動フィードバックシステムの実装

  - CoreHapticsService の実装
  - 攻撃、ダメージ、魔素回収時の振動パターン作成
  - 振動フィードバックの統合テスト
  - _Requirements: 2.5, 4.2_

- [ ] 12. iOS アプリケーション層の実装

  - AttackUseCase の実装：攻撃実行ロジック
  - ManaCollectionUseCase の実装：魔素回収ロジック
  - GameSessionUseCase の実装：セッション参加・離脱ロジック
  - 各ユースケースの単体テストと統合テスト
  - _Requirements: 2.1, 2.2, 3.1, 3.2, 3.4_

- [ ] 13. iOS プレゼンテーション層の実装

  - GameViewModel の実装：ゲーム状態管理
  - LobbyViewModel の実装：ロビー機能
  - ViewModel と各 UseCase の連携テスト
  - _Requirements: 4.1, 4.3, 5.1_

- [ ] 14. iOS ユーザーインターフェースの実装

  - GameView の実装：メインゲーム画面
  - LobbyView の実装：ロビー画面
  - PlayerStatusView、AttackButtonView、ManaBarView コンポーネントの実装
  - UI 統合テストとアクセシビリティテスト
  - _Requirements: 4.1, 4.3, 2.5, 3.4_

- [ ] 15. 魔素回収システムの実装

  - 移動距離計算ロジックの実装
  - 散歩モードでの魔素回収機能
  - 魔素量管理と UI 表示の統合
  - 魔素回収機能の統合テスト
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [ ] 16. 攻撃システムの統合実装

  - 詠唱機能付き攻撃システムの実装
  - 攻撃判定とダメージ計算の統合
  - 攻撃エフェクトと振動フィードバックの連携
  - 攻撃システムのエンドツーエンドテスト
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [ ] 17. 裁定システムの実装

  - 自動裁定機能の実装
  - ルール違反検出システム
  - 妖精協会ルールの表示機能
  - 裁定システムの統合テスト
  - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [ ] 18. ゲームセッション管理の統合

  - プレイヤーマッチング機能の実装
  - セッション開始・終了処理の統合
  - 勝敗判定とゲーム終了処理
  - セッション管理の統合テスト
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 5.1_

- [ ] 19. エラーハンドリングとフォールバック機能

  - UWB 利用不可時のフォールバック実装
  - ネットワーク接続エラーの処理
  - ゲームセッション復旧機能
  - エラーハンドリングの統合テスト
  - _Requirements: 1.3, 6.4, 7.3_

- [ ] 20. パフォーマンス最適化とテスト

  - UWB 位置更新頻度の最適化（30Hz 目標）
  - WebSocket 通信レイテンシーの最適化（100ms 以下目標）
  - バッテリー消費量の最適化
  - パフォーマンステストの実行と調整
  - _Requirements: 1.2, 6.4, 7.3_

- [ ] 21. セキュリティ機能の実装

  - 位置情報の暗号化送信
  - チート防止機能の実装
  - プライバシー保護機能
  - セキュリティテストの実行
  - _Requirements: 5.2, 5.4_

- [ ] 22. 統合テストとエンドツーエンドテスト
  - 2 プレイヤー対戦の完全なフローテスト
  - 複数セッション同時実行テスト
  - 異常系シナリオのテスト
  - 本番環境でのデプロイテスト
  - _Requirements: 全要件の統合検証_
