package repository

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/google/uuid"

	"server/internal/domain/game"
	"server/internal/session"
)

// GameSessionRepository はセッション管理用のリポジトリ実装です。
type GameSessionRepository struct {
	db *sql.DB
}

// NewGameSessionRepository は新しい GameSessionRepository を生成します。
func NewGameSessionRepository(db *sql.DB) *GameSessionRepository {
	if db == nil {
		return nil
	}
	return &GameSessionRepository{db: db}
}

// GetSession はセッション情報を取得します。
func (r *GameSessionRepository) GetSession(ctx context.Context, sessionID uuid.UUID) (*game.Session, error) {
	const query = `
	        SELECT id, stage_id, mode, status, started_at, ended_at
	        FROM game_sessions
	        WHERE id = $1
	    `

	var (
		id      uuid.UUID
		stageID uuid.UUID
		mode    string
		status  string
		started sql.NullTime
		ended   sql.NullTime
	)

	if err := r.db.QueryRowContext(ctx, query, sessionID).Scan(&id, &stageID, &mode, &status, &started, &ended); err != nil {
		if err == sql.ErrNoRows {
			return nil, session.ErrSessionNotFound
		}
		return nil, fmt.Errorf("get session: %w", err)
	}

	sess := &game.Session{
		ID:      id,
		StageID: stageID,
		Mode:    mode,
		Status:  game.SessionStatus(status),
	}
	if started.Valid {
		t := started.Time
		sess.StartedAt = &t
	}
	if ended.Valid {
		t := ended.Time
		sess.EndedAt = &t
	}

	return sess, nil
}

// ListParticipants はセッション参加者一覧を取得します。
func (r *GameSessionRepository) ListParticipants(ctx context.Context, sessionID uuid.UUID) ([]game.Participant, error) {
	const query = `
        SELECT player_id, role, initial_hp, initial_mp
        FROM game_users
        WHERE session_id = $1
    `

	rows, err := r.db.QueryContext(ctx, query, sessionID)
	if err != nil {
		return nil, fmt.Errorf("list participants: %w", err)
	}
	defer rows.Close()

	participants := make([]game.Participant, 0)
	for rows.Next() {
		var (
			playerID uuid.UUID
			role     string
			hp       int16
			mp       int16
		)
		if err := rows.Scan(&playerID, &role, &hp, &mp); err != nil {
			return nil, fmt.Errorf("scan participant: %w", err)
		}
		participants = append(participants, game.Participant{
			PlayerID:  playerID,
			Role:      role,
			InitialHP: int(hp),
			InitialMP: int(mp),
		})
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate participants: %w", err)
	}

	return participants, nil
}

// ListPlayerSnapshots はプレイヤーのスナップショットを取得します。
func (r *GameSessionRepository) ListPlayerSnapshots(ctx context.Context, sessionID uuid.UUID) (map[uuid.UUID]game.PlayerSnapshot, error) {
	const query = `
        SELECT session_id, player_id, hp, mp, stance, last_position_id, updated_at
        FROM player_state_snapshots
        WHERE session_id = $1
    `

	rows, err := r.db.QueryContext(ctx, query, sessionID)
	if err != nil {
		return nil, fmt.Errorf("list player snapshots: %w", err)
	}
	defer rows.Close()

	snapshots := make(map[uuid.UUID]game.PlayerSnapshot)
	for rows.Next() {
		var (
			sessID   uuid.UUID
			playerID uuid.UUID
			hp       int16
			mp       int16
			stance   sql.NullString
			lastPos  uuid.NullUUID
			updated  time.Time
		)
		if err := rows.Scan(&sessID, &playerID, &hp, &mp, &stance, &lastPos, &updated); err != nil {
			return nil, fmt.Errorf("scan player snapshot: %w", err)
		}
		snapshot := game.PlayerSnapshot{
			SessionID: sessID,
			PlayerID:  playerID,
			HP:        int(hp),
			MP:        int(mp),
			UpdatedAt: updated,
		}
		if stance.Valid {
			value := stance.String
			snapshot.Stance = &value
		}
		if lastPos.Valid {
			id := lastPos.UUID
			snapshot.LastPositionID = &id
		}
		snapshots[playerID] = snapshot
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate player snapshots: %w", err)
	}

	return snapshots, nil
}

// SaveEventWithSnapshots はゲームイベントとスナップショットを同時に永続化します。
func (r *GameSessionRepository) SaveEventWithSnapshots(ctx context.Context, event game.Event, snapshots map[uuid.UUID]game.PlayerSnapshot) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}

	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	eventID := event.ID
	if eventID == uuid.Nil {
		eventID = uuid.New()
	}
	if event.CreatedAt.IsZero() {
		event.CreatedAt = time.Now().UTC()
	}

	const insertEvent = `
        INSERT INTO game_events (
            id, session_id, trigger_id, target_id,
            trigger_hp, target_hp, trigger_mp, target_mp,
            category, type, created_at
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
    `

	var triggerMP interface{}
	if event.TriggerMP != nil {
		triggerMP = int16(*event.TriggerMP)
	}
	var targetMP interface{}
	if event.TargetMP != nil {
		targetMP = int16(*event.TargetMP)
	}

	if _, err = tx.ExecContext(
		ctx,
		insertEvent,
		eventID,
		event.SessionID,
		event.TriggerID,
		event.TargetID,
		int16(event.TriggerHP),
		int16(event.TargetHP),
		triggerMP,
		targetMP,
		string(event.Category),
		string(event.Type),
		event.CreatedAt,
	); err != nil {
		return fmt.Errorf("insert game_event: %w", err)
	}

	const upsertSnapshot = `
        INSERT INTO player_state_snapshots (
            session_id, player_id, hp, mp, stance, last_position_id, updated_at
        ) VALUES ($1,$2,$3,$4,$5,$6,$7)
        ON CONFLICT (session_id, player_id)
        DO UPDATE SET hp = EXCLUDED.hp,
                      mp = EXCLUDED.mp,
                      stance = EXCLUDED.stance,
                      last_position_id = EXCLUDED.last_position_id,
                      updated_at = EXCLUDED.updated_at
    `

	for _, snapshot := range snapshots {
		var stance interface{}
		if snapshot.Stance != nil {
			stance = *snapshot.Stance
		}
		var lastPosition interface{}
		if snapshot.LastPositionID != nil {
			lastPosition = *snapshot.LastPositionID
		}

		if _, err = tx.ExecContext(
			ctx,
			upsertSnapshot,
			snapshot.SessionID,
			snapshot.PlayerID,
			int16(snapshot.HP),
			int16(snapshot.MP),
			stance,
			lastPosition,
			snapshot.UpdatedAt,
		); err != nil {
			return fmt.Errorf("upsert player_state_snapshot: %w", err)
		}
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit tx: %w", err)
	}

	return nil
}

// UpdateSessionStatus はセッション状態を更新します。
func (r *GameSessionRepository) UpdateSessionStatus(ctx context.Context, sessionID uuid.UUID, status game.SessionStatus, endedAt *time.Time) error {
	const query = `
        UPDATE game_sessions
        SET status = $2,
            ended_at = $3,
            updated_at = NOW()
        WHERE id = $1
    `

	var ended interface{}
	if endedAt != nil {
		ended = *endedAt
	}

	result, err := r.db.ExecContext(ctx, query, sessionID, string(status), ended)
	if err != nil {
		return fmt.Errorf("update session status: %w", err)
	}

	affected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("session status rows affected: %w", err)
	}
	if affected == 0 {
		return session.ErrSessionNotFound
	}

	return nil
}

func (r *GameSessionRepository) FindJoinableSession(ctx context.Context, stageID uuid.UUID, excludePlayer uuid.UUID) (*game.Session, []game.Participant, map[uuid.UUID]game.PlayerSnapshot, error) {
	const query = `
	    SELECT id, stage_id, mode, status, started_at, ended_at
	    FROM game_sessions
	    WHERE stage_id = $1 AND status = $2
	    ORDER BY created_at
	    LIMIT 1
	`

	row := r.db.QueryRowContext(ctx, query, stageID, string(game.SessionStatusPreparing))

	var (
		id      uuid.UUID
		stage   uuid.UUID
		mode    string
		status  string
		started sql.NullTime
		ended   sql.NullTime
	)

	if err := row.Scan(&id, &stage, &mode, &status, &started, &ended); err != nil {
		if err == sql.ErrNoRows {
			return nil, nil, nil, nil
		}
		return nil, nil, nil, fmt.Errorf("find joinable session: %w", err)
	}

	participants, err := r.ListParticipants(ctx, id)
	if err != nil {
		return nil, nil, nil, err
	}

	if len(participants) == 0 {
		return nil, nil, nil, nil
	}

	for _, p := range participants {
		if p.PlayerID == excludePlayer {
			return nil, nil, nil, nil
		}
	}

	snapshots, err := r.ListPlayerSnapshots(ctx, id)
	if err != nil {
		return nil, nil, nil, err
	}

	sess := &game.Session{
		ID:      id,
		StageID: stage,
		Mode:    mode,
		Status:  game.SessionStatus(status),
	}
	if started.Valid {
		t := started.Time
		sess.StartedAt = &t
	}
	if ended.Valid {
		t := ended.Time
		sess.EndedAt = &t
	}

	return sess, participants, snapshots, nil
}

func (r *GameSessionRepository) AddParticipant(ctx context.Context, sessionID uuid.UUID, participant session.NewParticipant, activate bool) ([]game.Participant, map[uuid.UUID]game.PlayerSnapshot, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, nil, fmt.Errorf("begin tx: %w", err)
	}

	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	const insertParticipant = `
	    INSERT INTO game_users (id, session_id, player_id, role, initial_hp, initial_mp, joined_at)
	    VALUES ($1, $2, $3, $4, $5, $6, NOW())
	`

	const upsertSnapshot = `
	    INSERT INTO player_state_snapshots (session_id, player_id, hp, mp, stance, last_position_id, updated_at)
	    VALUES ($1, $2, $3, $4, NULL, NULL, NOW())
	    ON CONFLICT (session_id, player_id)
	    DO UPDATE SET hp = EXCLUDED.hp,
	                  mp = EXCLUDED.mp,
	                  updated_at = EXCLUDED.updated_at,
	                  stance = EXCLUDED.stance,
	                  last_position_id = EXCLUDED.last_position_id
	`

	participantID := uuid.New()
	if _, err = tx.ExecContext(ctx, insertParticipant, participantID, sessionID, participant.PlayerID, participant.Role, int16(participant.InitialHP), int16(participant.InitialMP)); err != nil {
		return nil, nil, fmt.Errorf("insert game_user: %w", err)
	}

	if _, err = tx.ExecContext(ctx, upsertSnapshot, sessionID, participant.PlayerID, int16(participant.InitialHP), int16(participant.InitialMP)); err != nil {
		return nil, nil, fmt.Errorf("upsert snapshot: %w", err)
	}

	if activate {
		const activateQuery = `
	        UPDATE game_sessions
	        SET status = $2,
	            started_at = COALESCE(started_at, NOW()),
	            updated_at = NOW()
	        WHERE id = $1
	    `
		if _, err = tx.ExecContext(ctx, activateQuery, sessionID, string(game.SessionStatusActive)); err != nil {
			return nil, nil, fmt.Errorf("activate session: %w", err)
		}
	} else {
		const touchQuery = `UPDATE game_sessions SET updated_at = NOW() WHERE id = $1`
		if _, err = tx.ExecContext(ctx, touchQuery, sessionID); err != nil {
			return nil, nil, fmt.Errorf("touch session: %w", err)
		}
	}

	if err = tx.Commit(); err != nil {
		return nil, nil, fmt.Errorf("commit tx: %w", err)
	}

	participants, err := r.ListParticipants(ctx, sessionID)
	if err != nil {
		return nil, nil, err
	}

	snapshots, err := r.ListPlayerSnapshots(ctx, sessionID)
	if err != nil {
		return nil, nil, err
	}

	return participants, snapshots, nil
}

// CreateSession は新しいゲームセッションを作成します。
func (r *GameSessionRepository) CreateSession(ctx context.Context, stageID uuid.UUID, participants []session.NewParticipant) (*game.Session, []game.Participant, map[uuid.UUID]game.PlayerSnapshot, error) {
	if len(participants) == 0 {
		return nil, nil, nil, fmt.Errorf("at least one participant is required")
	}

	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("begin tx: %w", err)
	}

	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	sessionID := uuid.New()
	status := game.SessionStatusPreparing
	var startedAt sql.NullTime

	if len(participants) >= 2 {
		status = game.SessionStatusActive
		startedAt = sql.NullTime{Time: time.Now().UTC(), Valid: true}
	}

	const insertSession = `
	    INSERT INTO game_sessions (id, stage_id, mode, status, started_at, created_at, updated_at)
	    VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
	`

	var started interface{}
	if startedAt.Valid {
		started = startedAt.Time
	}

	if _, err = tx.ExecContext(ctx, insertSession, sessionID, stageID, "duel", string(status), started); err != nil {
		return nil, nil, nil, fmt.Errorf("insert session: %w", err)
	}

	const insertParticipant = `
	    INSERT INTO game_users (id, session_id, player_id, role, initial_hp, initial_mp, joined_at)
	    VALUES ($1, $2, $3, $4, $5, $6, NOW())
	`

	const upsertSnapshot = `
	    INSERT INTO player_state_snapshots (session_id, player_id, hp, mp, stance, last_position_id, updated_at)
	    VALUES ($1, $2, $3, $4, NULL, NULL, NOW())
	    ON CONFLICT (session_id, player_id)
	    DO UPDATE SET hp = EXCLUDED.hp,
	                  mp = EXCLUDED.mp,
	                  updated_at = EXCLUDED.updated_at,
	                  stance = EXCLUDED.stance,
	                  last_position_id = EXCLUDED.last_position_id
	`

	createdParticipants := make([]game.Participant, 0, len(participants))
	snapshots := make(map[uuid.UUID]game.PlayerSnapshot, len(participants))

	for _, p := range participants {
		participantID := uuid.New()
		if _, err = tx.ExecContext(ctx, insertParticipant, participantID, sessionID, p.PlayerID, p.Role, int16(p.InitialHP), int16(p.InitialMP)); err != nil {
			return nil, nil, nil, fmt.Errorf("insert game_user: %w", err)
		}

		if _, err = tx.ExecContext(ctx, upsertSnapshot, sessionID, p.PlayerID, int16(p.InitialHP), int16(p.InitialMP)); err != nil {
			return nil, nil, nil, fmt.Errorf("upsert snapshot: %w", err)
		}

		snapshots[p.PlayerID] = game.PlayerSnapshot{
			SessionID: sessionID,
			PlayerID:  p.PlayerID,
			HP:        p.InitialHP,
			MP:        p.InitialMP,
			UpdatedAt: time.Now().UTC(),
		}

		createdParticipants = append(createdParticipants, game.Participant{
			PlayerID:  p.PlayerID,
			Role:      p.Role,
			InitialHP: p.InitialHP,
			InitialMP: p.InitialMP,
		})
	}

	if err = tx.Commit(); err != nil {
		return nil, nil, nil, fmt.Errorf("commit tx: %w", err)
	}

	var startedPtr *time.Time
	if startedAt.Valid {
		t := startedAt.Time
		startedPtr = &t
	}

	return &game.Session{
		ID:        sessionID,
		StageID:   stageID,
		Mode:      "duel",
		Status:    status,
		StartedAt: startedPtr,
	}, createdParticipants, snapshots, nil
}

// ClaimAndAddParticipant atomically finds a joinable preparing session for the given stage and inserts the participant.
// If no preparing session exists, returns nil,nil,nil,nil.
func (r *GameSessionRepository) ClaimAndAddParticipant(ctx context.Context, stageID uuid.UUID, participant session.NewParticipant, excludePlayer uuid.UUID) (*game.Session, []game.Participant, map[uuid.UUID]game.PlayerSnapshot, error) {
	// Start a transaction
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("begin tx: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	// Try to select a preparing session row and lock it to avoid races
	const selectQuery = `
		SELECT id, stage_id, mode, status, started_at, ended_at
		FROM game_sessions
		WHERE stage_id = $1 AND status = $2
		ORDER BY created_at
		FOR UPDATE SKIP LOCKED
		LIMIT 1
	`

	var (
		id      uuid.UUID
		stage   uuid.UUID
		mode    string
		status  string
		started sql.NullTime
		ended   sql.NullTime
	)

	row := tx.QueryRowContext(ctx, selectQuery, stageID, string(game.SessionStatusPreparing))
	if err := row.Scan(&id, &stage, &mode, &status, &started, &ended); err != nil {
		if err == sql.ErrNoRows {
			// no joinable session
			_ = tx.Commit()
			return nil, nil, nil, nil
		}
		return nil, nil, nil, fmt.Errorf("claim select: %w", err)
	}

	// Check participants and excludePlayer
	participants, err := r.ListParticipants(ctx, id)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("list participants: %w", err)
	}
	for _, p := range participants {
		if p.PlayerID == excludePlayer {
			// do not allow joining
			_ = tx.Commit()
			return nil, nil, nil, nil
		}
	}

	// Insert participant
	participantID := uuid.New()
	const insertParticipant = `
		INSERT INTO game_users (id, session_id, player_id, role, initial_hp, initial_mp, joined_at)
		VALUES ($1, $2, $3, $4, $5, $6, NOW())
	`
	if _, err = tx.ExecContext(ctx, insertParticipant, participantID, id, participant.PlayerID, participant.Role, int16(participant.InitialHP), int16(participant.InitialMP)); err != nil {
		return nil, nil, nil, fmt.Errorf("insert participant (claim): %w", err)
	}

	// Upsert snapshot
	const upsertSnapshot = `
		INSERT INTO player_state_snapshots (session_id, player_id, hp, mp, stance, last_position_id, updated_at)
		VALUES ($1,$2,$3,$4,NULL,NULL,NOW())
		ON CONFLICT (session_id, player_id)
		DO UPDATE SET hp = EXCLUDED.hp, mp = EXCLUDED.mp, updated_at = EXCLUDED.updated_at
	`
	if _, err = tx.ExecContext(ctx, upsertSnapshot, id, participant.PlayerID, int16(participant.InitialHP), int16(participant.InitialMP)); err != nil {
		return nil, nil, nil, fmt.Errorf("upsert snapshot (claim): %w", err)
	}

	// Activate session: set to active and started_at
	const activateQuery = `
		UPDATE game_sessions
		SET status = $2,
			started_at = COALESCE(started_at, NOW()),
			updated_at = NOW()
		WHERE id = $1
	`
	if _, err = tx.ExecContext(ctx, activateQuery, id, string(game.SessionStatusActive)); err != nil {
		return nil, nil, nil, fmt.Errorf("activate session (claim): %w", err)
	}

	if err = tx.Commit(); err != nil {
		return nil, nil, nil, fmt.Errorf("commit claim tx: %w", err)
	}

	// After commit, read participants and snapshots via repo methods (outside tx)
	parts, err := r.ListParticipants(ctx, id)
	if err != nil {
		return nil, nil, nil, err
	}
	snaps, err := r.ListPlayerSnapshots(ctx, id)
	if err != nil {
		return nil, nil, nil, err
	}

	sess := &game.Session{
		ID:      id,
		StageID: stage,
		Mode:    mode,
		Status:  game.SessionStatus(status),
	}
	if started.Valid {
		t := started.Time
		sess.StartedAt = &t
	}
	if ended.Valid {
		t := ended.Time
		sess.EndedAt = &t
	}

	return sess, parts, snaps, nil
}
