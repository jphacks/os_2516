# Database Design

リアル版格闘ゲームの主要ユースケース（位置同期、攻撃判定、裁定管理、マナ収支追跡）を支えるリレーショナル設計案です。Supabase/PostgreSQL を想定し、Apple ID を用いたログインとデバイス管理も考慮しています。

## ユーザー・認証テーブル

### users — 認証ユーザー
| カラム | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | UUID | PK | ユーザー識別子 |
| preferred_name | TEXT | NOT NULL | 表示名初期値（プレイヤー名と連動可能） |
| email | TEXT | UNIQUE | Apple 提供メール（匿名アドレス含む） |
| is_active | BOOLEAN | DEFAULT TRUE | 退会フラグ |
| created_at | TIMESTAMPTZ | DEFAULT now() | 登録日時 |
| updated_at | TIMESTAMPTZ | DEFAULT now() | 更新日時 |

### apple_accounts — Apple ID 連携
| カラム | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| user_id | UUID | PK, FK -> users.id | 紐付くユーザー（1:1） |
| apple_sub | TEXT | UNIQUE NOT NULL | Apple Sign in の `sub` 永続ID |
| email | TEXT |  | サインイン時メール（変更トラッキング用） |
| email_verified | BOOLEAN | DEFAULT TRUE | Apple 提供フラグ |
| full_name | JSONB |  | 姓名（初回のみ）を JSON で保持 |
| auth_revoked_at | TIMESTAMPTZ |  | Apple 側解除日時 |

### user_sessions — 認証セッション
| カラム | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | UUID | PK | セッションID |
| user_id | UUID | FK -> users.id | ログインユーザー |
| refresh_token | TEXT | UNIQUE NOT NULL | 暗号化保存したリフレッシュトークン |
| issued_at | TIMESTAMPTZ | NOT NULL | 発行日時 |
| expires_at | TIMESTAMPTZ | NOT NULL | 失効日時 |
| revoked_at | TIMESTAMPTZ |  | 明示無効化日時 |
| client_info | JSONB |  | デバイス種別・OS・アプリバージョン |

### user_devices — デバイス紐付け
| カラム | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | UUID | PK | デバイスID |
| user_id | UUID | FK -> users.id | 所有ユーザー |
| device_token | TEXT | UNIQUE | プッシュ通知トークン |
| platform | TEXT | NOT NULL | `ios` 等 |
| app_version | TEXT |  | 利用アプリバージョン |
| last_seen_at | TIMESTAMPTZ | DEFAULT now() | 最終アクセス |

## コアテーブル

### players — プレイヤーマスタ
| カラム | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | UUID | PK | プレイヤー識別子 |
| user_id | UUID | UNIQUE, FK -> users.id | 紐付くユーザー（ゲストは NULL 可） |
| display_name | TEXT | NOT NULL | 表示名（重複許容） |
| hp | SMALLINT | NOT NULL DEFAULT 100 | 基本HP（初期値） |
| mp | SMALLINT | NOT NULL DEFAULT 100 | 基本MP（初期値） |
| rank | SMALLINT | DEFAULT 0 | 内部レーティング指標 |
| avatar_url | TEXT |  | アバター画像パス |
| created_at | TIMESTAMPTZ | DEFAULT now() | 登録日時 |
| updated_at | TIMESTAMPTZ | DEFAULT now() | 更新日時（トリガー更新） |

### game_sessions — 対戦セッション
| カラム | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | UUID | PK | セッション識別子 |
| title | TEXT |  | 任意タイトル |
| mode | TEXT | NOT NULL | `duel` などモード種別 |
| status | TEXT | NOT NULL | `preparing` `active` `finished` 等 |
| battle_stage_id | UUID | FK -> battle_stages.id | 使用ステージ |
| started_at | TIMESTAMPTZ |  | 開始時刻 |
| ended_at | TIMESTAMPTZ |  | 終了時刻 |
| winner_user_id | UUID | FK -> game_users.id | 勝者参加ユーザー（引き分けは NULL） |
| result_summary | JSONB |  | 勝敗やスコアのサマリ（チーム戦拡張用） |
| referee_note | TEXT |  | 裁定メモ |

### battle_stages — 対戦ステージ
| カラム | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | UUID | PK | ステージ識別子 |
| name | TEXT | NOT NULL | ステージ名 |
| latitude | NUMERIC(9,6) | NOT NULL | 緯度 |
| longitude | NUMERIC(9,6) | NOT NULL | 経度 |
| radius_m | NUMERIC(6,2) |  | 有効範囲半径（メートル） |
| description | TEXT |  | 補足説明 |
| created_at | TIMESTAMPTZ | DEFAULT now() | 登録日時 |
| updated_at | TIMESTAMPTZ | DEFAULT now() | 更新日時 |

### game_users — セッション参加ユーザー
| カラム | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | UUID | PK | 参加記録ID |
| session_id | UUID | FK -> game_sessions.id | 参加セッション |
| player_id | UUID | FK -> players.id | 対象プレイヤー |
| role | TEXT | NOT NULL | `player` `referee` `observer` 等 |
| join_at | TIMESTAMPTZ | DEFAULT now() | 参加時刻 |
| leave_at | TIMESTAMPTZ |  | 離脱時刻 |
| initial_hp | SMALLINT | DEFAULT 100 | 開始HP |
| initial_mana | SMALLINT | DEFAULT 0 | 開始マナ |
| UNIQUE(session_id, player_id) |  |  | 重複参加防止 |
| INDEX(session_id, role) |  |  | ロール別参照用 |
| outcome | TEXT |  | `win` `lose` `draw` などプレイヤーごとの結果 |
| final_hp | SMALLINT |  | 終了時 HP |

### player_state_snapshots — 現在ステート
| カラム | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | UUID | PK | スナップショットID |
| session_id | UUID | FK -> game_sessions.id | 対象セッション |
| player_id | UUID | FK -> players.id | 対象プレイヤー |
| hp | SMALLINT | NOT NULL | 現在HP |
| mana | SMALLINT | NOT NULL | 現在マナ |
| stance | TEXT |  | 状態（詠唱中・防御中等） |
| last_position_id | UUID | FK -> position_logs.id | 最新測位 |
| updated_at | TIMESTAMPTZ | DEFAULT now() | 更新時刻 |
| UNIQUE(session_id, player_id) |  |  | 1レコード維持 |

## イベント・ログテーブル

### position_logs — 位置・向きログ
| カラム | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | UUID | PK | ログID |
| session_id | UUID | FK -> game_sessions.id | セッション |
| player_id | UUID | FK -> players.id | プレイヤー |
| recorded_at | TIMESTAMPTZ | NOT NULL | 測位タイムスタンプ |
| x | NUMERIC(7,3) | NOT NULL | arena内X座標（m） |
| y | NUMERIC(7,3) | NOT NULL | arena内Y座標 |
| z | NUMERIC(6,2) |  | 高さ |
| orientation_deg | NUMERIC(6,2) |  | 端末向き（度） |
| accuracy_cm | NUMERIC(5,2) |  | 精度（cm） |
| source | TEXT | NOT NULL | `uwb` `fallback` 等 |
| INDEX(session_id, recorded_at DESC) |  |  | リアルタイム参照用 |

### game_events — 行動イベント
| カラム | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | UUID | PK | イベントID |
| session_id | UUID | FK -> game_sessions.id | セッション |
| trigger_id | UUID | FK -> players.id | 行動主体（攻撃者・回復者など） |
| target_id | UUID | FK -> players.id | 対象プレイヤー（自分自身含む） |
| trigger_hp | SMALLINT |  | 行動直後の主体HP |
| target_hp | SMALLINT |  | 行動直後の対象HP |
| category | game_event_category | NOT NULL | 行動分類（例: `attack`, `heal`） |
| type | game_event_type | NOT NULL | カテゴリ内の詳細種別（例: `fire`） |
| created_at | TIMESTAMPTZ | DEFAULT now() | 記録時刻 |
| INDEX(session_id, created_at) |  |  | 時系列照会用 |

### mana_events — マナ獲得・消費
| カラム | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | UUID | PK | イベントID |
| session_id | UUID | FK -> game_sessions.id | セッション |
| player_id | UUID | FK -> players.id | プレイヤー |
| event_type | TEXT | NOT NULL | `gain_run` `gain_walk` `spend_attack` 等 |
| amount | SMALLINT | NOT NULL | 正:獲得、負:消費 |
| source_position_id | UUID | FK -> position_logs.id | 関連位置（任意） |
| note | TEXT |  | 補足 |
| recorded_at | TIMESTAMPTZ | DEFAULT now() | 記録時刻 |
| INDEX(session_id, player_id) |  |  | 残量追跡用 |

### referee_decisions — 裁定・警告
| カラム | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | UUID | PK | 裁定ID |
| session_id | UUID | FK -> game_sessions.id | セッション |
| reporter_id | UUID | FK -> players.id | 報告者（裁定者/システム） |
| target_id | UUID | FK -> players.id | 対象プレイヤー |
| rule_code | TEXT | NOT NULL | 適用ルールID（例: `FAIR-001`） |
| verdict | TEXT | NOT NULL | `warning` `penalty` `dismissed` |
| detail | TEXT |  | 自由記述 |
| resolved_at | TIMESTAMPTZ |  | 処理完了時刻 |
| INDEX(session_id, verdict) |  |  | 違反集計用 |

### session_events — 汎用イベントストア
| カラム | 型 | 制約 | 説明 |
| --- | --- | --- | --- |
| id | BIGSERIAL | PK | イベントID |
| session_id | UUID | FK -> game_sessions.id | セッション |
| event_type | TEXT | NOT NULL | `hp_change` `buff` `system` 等 |
| payload | JSONB | NOT NULL | 追加情報（差分データ） |
| occurred_at | TIMESTAMPTZ | NOT NULL | 発生時刻 |
| INDEX(session_id, occurred_at) |  |  | イベントリプレイ用 |

## 運用メモ
- 高頻度ログは Supabase に蓄積し、長期保管は BigQuery 等へアーカイブするとスケーラブルです。
- `player_state_snapshots` はアプリ層キャッシュ＋サーバ更新で整合性を維持します。
- Apple Sign in 用の `apple_sub` は不変なので主キーではなく UNIQUE 制約で保持し、ユーザー退会時は `users.is_active` とセッション無効化で対応します。
- `game_event_category` と `game_event_type` は PostgreSQL ENUM として管理し、拡張時は `ALTER TYPE ... ADD VALUE` を用います。
- ステージ情報は `battle_stages` に集約し、ロケーション更新はステージ更新かセッション単位の `result_summary` 補足に記録します。
- ルールコードやペナルティ種別拡張時は `rule_definitions` テーブルを追加して管理できます。
