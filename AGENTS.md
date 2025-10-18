# Repository Guidelines

## Project Structure & Module Organization
Keep planning references at the repo root (`design.md`, `requirements.md`, `tasks.md`). Place the iOS client under `RealFightingGame/` following the layered layout described in `design.md`, and mirror game features inside `RealFightingGameTests/`. Host the Go backend inside `real-fighting-server/` with `cmd/server` for entrypoints, business logic in `internal/{domain,application,infra}`, and reusable packages in `pkg`. Store shared diagrams in `docs/` and large binaries in `Assets/`.

## Build, Test, and Development Commands
Run `cd RealFightingGame && xcodebuild -scheme RealFightingGame -destination "platform=iOS Simulator,name=iPhone 15" build` for a smoke build. Execute `cd RealFightingGame && xcodebuild test -scheme RealFightingGame -destination "platform=iOS Simulator,name=iPhone 15"` before merging UI or gameplay updates. Start the Go server locally with `cd real-fighting-server && go run cmd/server/main.go`, and validate business rules via `cd real-fighting-server && go test ./...`.

## Coding Style & Naming Conventions
Follow Swift API Design Guidelines: UpperCamelCase types, lowerCamelCase members, four-space indentation, and reformat with `swiftformat` or Xcode re-indent. For Go, favor short lowercase package names, constructor helpers named `NewThing`, and format code with `gofmt` or `goimports` before commit.

## Testing Guidelines
Name Swift test suites `<Feature>Tests.swift` and individual methods `test...`, using XCTest expectations for deterministic async coverage. For Go modules, colocate `_test.go` files, build table-driven cases, and cover attack resolution, UWB fallbacks, and session lifecycle logic. Run both platform test commands before PR review.

## Commit & Pull Request Guidelines
Keep commit subjects short, present-tense, and optionally scoped (e.g., `iOS: Lobby flow`); elaborate in bodies when touching multiple layers or schemas. PR descriptions must state intent, list functional impacts, link relevant `tasks.md` checklist items, provide simulator captures for UI changes, and record verification steps and known risks.

## Security & Configuration Tips
Never commit live secrets; share sample configuration through `.env.example` only. Document architecture changes in `design.md`, update requirement shifts in `requirements.md`, and log sprint blockers or follow-up actions in `tasks.md` to keep all agents aligned.
