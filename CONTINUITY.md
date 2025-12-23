- Goal (incl. success criteria):
  - Fix app freeze during codebase review (LEANN tool execution) and stabilize UX.

- Constraints/Assumptions:
  - Maintain continuity ledger updates for goal/decisions/state changes.

- Key decisions:
  - None yet.

- State:
  - LEANN bridge updated with sendable-safe output collector for async process I/O.

- Done:
  - Read existing continuity ledger.
  - Added LEANN path resolution with env overrides and missing-configuration handling.
  - Guarded codebase search tools for missing index/configuration.
  - Fixed orchestrator delegation helpers to accept agents parameter.
  - Added LEANN root override setting and reloadable configuration.
  - Added resolved LEANN path status indicator in Settings.

- Now:
  - Make LEANN bridge non-blocking to prevent UI freezes.

- Next:
  - Retest codebase review flow and confirm no freezes.

- Open questions (UNCONFIRMED if needed):
  - UNCONFIRMED: Do you want to bundle LEANN assets in app resources or rely on external install?

- Working set (files/ids/):
  - `CONTINUITY.md`
  - Added Log utility and replaced print logging across core/mac modules.
  - Centralized UserDefaults keys usage across settings and services.
  - Removed redundant orchestrator conditional in agent configuration.
  - Updated README, ARCHITECTURE, TESTING_ORCHESTRATION for LEANN setup and logging notes.
  - Reworked LEANNBridgeService.runPythonCommand to avoid blocking waitUntilExit and added sendable-safe collector.
