type BattleSession struct {
    ID          uuid.UUID
    Mode        string
    Status      string
    Players     map[uuid.UUID]*SessionPlayer
    StartedAt   time.Time
    Connections map[uuid.UUID]*websocket.Conn // 必要なら
}

type SessionPlayer struct {
    ID        uuid.UUID
    Role      string
    HP        int16
    MP        int16
    Stance    string
    LastPosID uuid.UUID
}

func LoadBattleSession(ctx context.Context, repo Repository, sessionID uuid.UUID) (*BattleSession, error) {
    sess, err := repo.GetGameSession(ctx, sessionID)              // game_sessions
    players, err := repo.ListGameUsers(ctx, sessionID)            // game_users
    snapshots, err := repo.ListPlayerSnapshots(ctx, sessionID)    // player_state_snapshots

    battle := &BattleSession{
        ID: sessionID,
        Mode: sess.Mode,
        Status: sess.Status,
        Players: make(map[uuid.UUID]*SessionPlayer),
        Connections: make(map[uuid.UUID]*websocket.Conn),
    }

    for _, p := range players {
        snap := snapshots[p.PlayerID] // hp/mp などを対応させる
        battle.Players[p.PlayerID] = &SessionPlayer{
            ID: p.PlayerID,
            Role: p.Role,
            HP:  snap.HP,
            MP:  snap.Mana,
            Stance: snap.Stance,
            LastPosID: snap.LastPositionID,
        }
    }
    return battle, nil
}

type Manager struct {
    repo     Repository
    sessions map[uuid.UUID]*BattleSession
    mu       sync.RWMutex
}

func (m *Manager) AttachConnection(ctx context.Context, sessionID, playerID uuid.UUID, conn *websocket.Conn) (*BattleSession, error) {
    m.mu.Lock()
    bs, ok := m.sessions[sessionID]
    if !ok {
        loaded, err := m.loadBattleSession(ctx, sessionID) // game_sessions/users/snapshots
        if err != nil {
            m.mu.Unlock()
            return nil, err
        }
        bs = loaded
        m.sessions[sessionID] = bs
    }
    m.mu.Unlock()

    bs.mu.Lock()
    defer bs.mu.Unlock()

    player, exists := bs.Players[playerID]
    if !exists {
        return nil, fmt.Errorf("player not part of session")
    }

    player.Conn = conn // structにConnを持たせるか、Connections map を使う
    return bs, nil
}

func (m *Manager) DetachConnection(sessionID, playerID uuid.UUID) {
    m.mu.RLock()
    bs := m.sessions[sessionID]
    m.mu.RUnlock()
    if bs == nil {
        return
    }

    bs.mu.Lock()
    defer bs.mu.Unlock()
    if conn := bs.Connections[playerID]; conn != nil {
        conn.Close()
    }
    delete(bs.Connections, playerID)
}


