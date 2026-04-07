# Plan: OpenSpiel Integration with Zig Engine for RL Agent Training

## Context

The Zig Netrunner engine has a complete C API (`zig/src/api.zig`, 95+ exported functions) and an interactive TUI (`zig/src/tui.zig` via libvaxis). The goal is to train RL agents that can play Netrunner competitively, and eventually add a "vs AI" mode to the TUI.

Netrunner is a **2-player sequential imperfect-information zero-sum game** with an astronomically large game tree (hidden hands, hidden R&D, facedown installs, complex decision trees). This rules out tree-traversal algorithms (CFR, Deep CFR) and requires sample-based approaches.

## Architecture Decision: PettingZoo + NFSP over pure OpenSpiel

After research, the recommended path is:

**Layer 1:** Python `ctypes` wrapper around `libnetrunner.so` (the Zig C API)
**Layer 2:** PettingZoo `AECEnv` (Alternating Environment Cycle) wrapping the ctypes layer
**Layer 3:** OpenSpiel Python game wrapping PettingZoo env (via Shimmy bridge) for NFSP access
**Layer 4:** Training loop using OpenSpiel NFSP (primary) + SB3 MaskablePPO (secondary/baseline)
**Layer 5:** Export trained policy → Zig-native inference in TUI for vs-AI mode

### Why this stack:

| Concern | Decision | Reason |
|---------|----------|--------|
| Game engine | Keep in Zig, call via C API | Engine is 430KB of battle-tested logic; no rewrite |
| Python bridge | `ctypes` over `cffi` | Zero build deps, C header already exists (`zig/include/netrunner.h`) |
| Env interface | PettingZoo AEC | Standard for turn-based 2-player; native action masking; SB3 compatible |
| Algorithm | NFSP (primary) | Best proven approach for large imperfect-info games; doesn't require tree traversal |
| Algorithm | MaskablePPO (secondary) | Simpler baseline; faster to iterate; good for initial validation |
| Inference in TUI | ONNX Runtime C API | Small, embeddable, no Python dependency at runtime |

### Algorithm comparison for Netrunner:

| Algorithm | Imperfect Info | Scalability | Notes |
|-----------|---------------|-------------|-------|
| **NFSP** | Yes (designed for it) | Good | Two NNs per player; converges toward Nash equilibrium |
| **Deep CFR** | Yes | Poor for large games | Requires tree traversal; infeasible for Netrunner |
| **MaskablePPO** | Via self-play | Good | Simpler; no Nash convergence guarantee; good baseline |
| **AlphaZero** | No (perfect info only) | N/A | Not applicable to Netrunner |
| **DREAM** | Yes (model-free) | Promising | Not in OpenSpiel; standalone implementation |

## Phase 1: Python ctypes wrapper for `libnetrunner.so`

Create `python/netrunner_engine.py` wrapping all C API functions.

```python
import ctypes

class NetrunnerEngine:
    def __init__(self, matchup_id: int, seed: int):
        self._lib = ctypes.CDLL("zig/zig-out/lib/libnetrunner.so")
        self._handle = self._lib.netrunner_create(matchup_id, seed)

    def num_actions(self) -> int:
        return self._lib.netrunner_num_actions(self._handle)

    def apply_action(self, index: int) -> int:
        return self._lib.netrunner_apply_action(self._handle, index)

    def is_terminal(self) -> bool:
        return bool(self._lib.netrunner_is_terminal(self._handle))

    def current_player(self) -> int:  # 0=corp, 1=runner
        return self._lib.netrunner_current_player(self._handle)

    def winner(self) -> int:  # 0=corp, 1=runner, -1=none
        return self._lib.netrunner_winner(self._handle)

    # ... wrap remaining 90+ functions
```

**Key functions to wrap:**
- Game lifecycle: `create`, `destroy`, `is_terminal`, `winner`
- Actions: `num_actions`, `apply_action`, `action_description`, `action_card_code`
- State: `player_credits`, `player_clicks`, `player_hand_size`, `player_deck_size`, `player_score`
- Board: `server_count`, `server_ice_count`, `server_content_count`, all card query functions
- Runner rig: `rig_program_count/name/code/strength/virus`, hardware, resources
- Run state: `is_run_active`, `run_server`, `run_phase`, `run_position`

**Files:** `python/netrunner_engine.py`

## Phase 2: Observation space design

The observation tensor encodes what a player can see. Netrunner has asymmetric information:

### Corp observes:
- Own hand (card codes, one-hot or embedding)
- Own credits, clicks, bad pub
- All servers: installed cards (known), ICE (known), content (known)
- Runner: credits, clicks, tags, installed cards (all face-up), MU
- Runner hand size (count only, not contents)
- Runner stack/heap sizes
- Score areas (both)
- Run state if active
- Turn number

### Runner observes:
- Own hand (card codes)
- Own credits, clicks, tags, MU, link
- Own rig: all installed programs/hardware/resources
- Corp servers: ICE (rezzed ones visible with strength/subs, unrezzed = unknown), content (rezzed visible, unrezzed = unknown count)
- Corp credits, clicks, bad pub
- Corp hand size (count only)
- Corp R&D size, Archives (faceup cards visible)
- Score areas (both)
- Run state if active
- Turn number

### Tensor encoding (flat float array):

```
Section                          Size (approx)
─────────────────────────────────────────────
Player ID (one-hot)              2
Own credits                      1 (normalized)
Own clicks                       1
Own hand (card IDs, padded)      10 * CARD_EMBEDDING_DIM
Opponent credits                 1
Opponent clicks                  1
Opponent hand size               1
Score (both)                     2
Corp servers (5 max):
  ICE per server (3 max):
    rezzed flag                  1
    card code (if rezzed)        CARD_EMBEDDING_DIM
    strength (if rezzed)         1
  Content per server (3 max):
    rezzed flag                  1
    card code (if rezzed)        CARD_EMBEDDING_DIM
Runner rig:
  Programs (6 max)               6 * (CARD_EMBEDDING_DIM + counters)
  Hardware (3 max)               3 * CARD_EMBEDDING_DIM
  Resources (5 max)              5 * (CARD_EMBEDDING_DIM + counters)
Run state                        ~10 (active, server, phase, position)
Turn number                      1
─────────────────────────────────────────────
TOTAL                            ~500-800 floats (depending on embedding dim)
```

For card embeddings: use a learned embedding layer (card_code → 16-32 dim vector) or one-hot over the ~160 card pool.

**Files:** `python/netrunner_obs.py`

## Phase 3: Action space design

The C API already provides `num_actions()` and `apply_action(index)` where index is 0..N-1 into the current legal actions list. But OpenSpiel/PettingZoo need a **fixed action space** with masking.

### Approach: Dynamic action indexing with description-based mapping

Since Netrunner's action space is too large and context-dependent for a flat enumeration, use the engine's native action indexing:

```python
# At each step:
num_legal = engine.num_actions()       # e.g., 7
# Action space = Discrete(MAX_ACTIONS)  # e.g., 512
# Action mask = [1]*num_legal + [0]*(MAX_ACTIONS - num_legal)
# Agent picks index 0..num_legal-1
# We call engine.apply_action(chosen_index)
```

This is the simplest approach: the agent learns to pick from a variable-length menu. The mask ensures only legal actions are selected. `MAX_ACTIONS` should be set to the empirical maximum (likely ~50-100 based on the engine).

**Alternative (for NFSP):** Map each `(ActionKind, card_code, server)` tuple to a stable integer. This gives NFSP a consistent action space across states. More complex but better for game-theoretic convergence.

**Files:** `python/netrunner_actions.py`

## Phase 4: PettingZoo AECEnv

```python
from pettingzoo import AECEnv
from gymnasium import spaces
import numpy as np

class NetrunnerEnv(AECEnv):
    metadata = {"name": "netrunner_v0"}

    def __init__(self, matchup_id=0, seed=None):
        super().__init__()
        self.possible_agents = ["corp", "runner"]
        self.agents = list(self.possible_agents)
        self.engine = NetrunnerEngine(matchup_id, seed or random.randint(0, 2**32))

        self.observation_spaces = {
            agent: spaces.Dict({
                "observation": spaces.Box(low=0, high=1, shape=(OBS_SIZE,), dtype=np.float32),
                "action_mask": spaces.Box(low=0, high=1, shape=(MAX_ACTIONS,), dtype=np.int8),
            }) for agent in self.agents
        }
        self.action_spaces = {
            agent: spaces.Discrete(MAX_ACTIONS) for agent in self.agents
        }

    def observe(self, agent):
        obs = build_observation(self.engine, agent)  # from Phase 2
        mask = np.zeros(MAX_ACTIONS, dtype=np.int8)
        mask[:self.engine.num_actions()] = 1
        return {"observation": obs, "action_mask": mask}

    def step(self, action):
        self.engine.apply_action(action)
        # Check terminal, update rewards, switch agent
        if self.engine.is_terminal():
            winner = self.engine.winner()
            self.rewards = {"corp": 1.0 if winner == 0 else -1.0,
                           "runner": 1.0 if winner == 1 else -1.0}
            self.terminations = {a: True for a in self.agents}

    @property
    def agent_selection(self):
        return "corp" if self.engine.current_player() == 0 else "runner"
```

**Files:** `python/netrunner_env.py`

## Phase 5: Training with NFSP

NFSP (Neural Fictitious Self-Play) is the primary algorithm. It maintains two networks per player:
- **Best response network** (DQN): learns to exploit the opponent's average policy
- **Average policy network** (supervised): tracks the player's own average strategy

This converges toward Nash equilibrium without tree traversal.

```python
import pyspiel
from open_spiel.python.algorithms import nfsp

# Register game via Shimmy PettingZoo→OpenSpiel bridge, or
# implement OpenSpiel Python game wrapping the engine directly

env = rl_environment.Environment("netrunner")

agents = [
    nfsp.NFSP(player_id=0, state_representation_size=OBS_SIZE,
              num_actions=MAX_ACTIONS, hidden_layers_sizes=[256, 256],
              reservoir_buffer_capacity=2e6, anticipatory_param=0.1),
    nfsp.NFSP(player_id=1, state_representation_size=OBS_SIZE,
              num_actions=MAX_ACTIONS, hidden_layers_sizes=[256, 256],
              reservoir_buffer_capacity=2e6, anticipatory_param=0.1),
]

for episode in range(NUM_EPISODES):
    time_step = env.reset()
    while not time_step.last():
        player = time_step.observations["current_player"]
        action = agents[player].step(time_step)
        time_step = env.step([action])
    for agent in agents:
        agent.step(time_step)  # terminal update
```

**Secondary baseline: MaskablePPO with self-play**

```python
from sb3_contrib import MaskablePPO
from pettingzoo.utils import aec_to_parallel

env = NetrunnerEnv(matchup_id=0)
model = MaskablePPO("MlpPolicy", env, verbose=1)
model.learn(total_timesteps=1_000_000)
```

**Files:** `python/train_nfsp.py`, `python/train_ppo.py`

## Phase 6: Export trained policy for TUI

After training, export the policy network to ONNX format for embedding in the Zig TUI:

```python
# Export PyTorch policy to ONNX
torch.onnx.export(agent.policy_network, dummy_input, "netrunner_corp.onnx")
torch.onnx.export(agent.policy_network, dummy_input, "netrunner_runner.onnx")
```

Then in the TUI, use ONNX Runtime C API to run inference:

```zig
// In tui.zig, when it's the AI's turn:
const obs = buildObservationTensor(game);     // same encoding as Python
const action_logits = onnx_session.run(obs);  // ONNX Runtime C API
const legal_mask = getLegalActionMask(game);
const action = argmax(action_logits * legal_mask);
game.applyAction(action);
```

**Files:**
- `zig/src/ai.zig` — ONNX Runtime wrapper + observation builder
- `zig/src/tui.zig` — Add AI opponent mode
- `models/` — Stored `.onnx` model files

## Phase 7: TUI vs-AI mode

Extend the TUI menu to add "Play vs AI (Corp)" and "Play vs AI (Runner)":

```
┌─────────────────────────┐
│  Android: Netrunner     │
│                         │
│  1. Human vs Human      │
│  2. Play as Runner (AI Corp)
│  3. Play as Corp (AI Runner)
│  4. AI vs AI (watch)    │
│  5. Load Replay         │
└─────────────────────────┘
```

The game loop in `tui.zig` already alternates between corp/runner decisions. When the AI's turn comes, instead of waiting for keyboard input, call the ONNX inference and auto-apply the action with a configurable delay for watchability.

**Files:** `zig/src/tui.zig` (modify), `zig/src/ai.zig` (new)

## Implementation Order

| Phase | Description | Effort | Dependencies |
|-------|-------------|--------|-------------|
| 1 | Python ctypes wrapper | Small | `libnetrunner.so` (exists) |
| 2 | Observation space design | Medium | Phase 1 |
| 3 | Action space design | Small | Phase 1 |
| 4 | PettingZoo AECEnv | Medium | Phases 1-3 |
| 5 | NFSP + PPO training | Large | Phase 4 |
| 6 | ONNX export | Small | Phase 5 |
| 7 | TUI vs-AI mode | Medium | Phase 6 |

## Key Risks

1. **Observation design quality** — Bad observations = agent can't learn. May need iteration.
2. **Action space size** — If MAX_ACTIONS is too large, learning is slow. Start with ~128, measure empirically.
3. **Training time** — Netrunner's game tree is enormous. NFSP may need millions of episodes. Use GPU.
4. **ONNX Runtime in Zig** — Need to link ONNX Runtime C library. Alternatively, export to a simpler format (raw weights + manual forward pass in Zig).
5. **Reward shaping** — Pure win/loss (+1/-1) may be too sparse. Consider intermediate rewards (agenda scored, credits gained, etc.) for PPO but NOT for NFSP (which needs zero-sum terminal rewards).

## Files Summary

```
python/
├── netrunner_engine.py      # ctypes wrapper for libnetrunner.so
├── netrunner_obs.py         # Observation tensor builder
├── netrunner_actions.py     # Action space mapping
├── netrunner_env.py         # PettingZoo AECEnv
├── train_nfsp.py            # NFSP training script
├── train_ppo.py             # MaskablePPO baseline
└── export_onnx.py           # Export trained model to ONNX

zig/src/
├── ai.zig                   # ONNX Runtime wrapper + obs builder (new)
└── tui.zig                  # Add vs-AI mode (modify)

models/
├── netrunner_corp.onnx      # Trained corp policy
└── netrunner_runner.onnx    # Trained runner policy
```

## Verification

1. **Phase 1:** `python -c "from netrunner_engine import *; e = NetrunnerEngine(0, 42); print(e.num_actions())"`
2. **Phase 4:** `python -c "from netrunner_env import *; env = NetrunnerEnv(); env.reset(); print(env.observe('corp'))"`
3. **Phase 5:** Training loss curves should decrease; agent should beat random baseline within ~100K episodes
4. **Phase 7:** `zig build tui` → select "Play as Runner" → AI corp makes reasonable plays
