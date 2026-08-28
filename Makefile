PY := python3.12
VENV := .venv
BIN := $(VENV)/bin
ifeq ($(OS),Windows_NT)
PY_CMD := $(VENV)\Scripts\python.exe
else
PY_CMD := $(BIN)/python
endif
BOT ?= rookie
# `AS` is a GNU make BUILT-IN (the assembler, default `as`), so `AS ?= all`
# never fired and a plain `make spar BOT=rookie` ran `spar.py --as as`, which
# argparse rejects. `?=` only assigns when a variable is UNDEFINED, and make had
# already defined this one. Keep the documented `AS=defender` interface working
# by honouring AS only when it really came from the command line.
ROLE ?= all
ifeq ($(origin AS),command line)
ROLE := $(AS)
endif

.PHONY: install spar ui validate qualify submit test clean check-no-key

install:
	# --seed is REQUIRED: `uv venv` alone creates a venv with no pip, so the very
	# next line died with "No module named pip" on a fresh clone. The stdlib
	# fallback seeds pip on its own.
	uv venv --python 3.12 --seed $(VENV) || $(PY) -m venv $(VENV)
	$(PY_CMD) -m pip install -q --upgrade pip
	$(PY_CMD) -m pip install -q pytest
	@echo "ready. no api key needed, ever."

spar:
	$(PY_CMD) spar.py --bot $(BOT) --as $(ROLE)

ui:
	$(PY_CMD) -m kit.arena_ui.build_ui
	$(PY_CMD) -m kit.arena_ui.serve --open

# Always validate against the REAL exported world. Without --world the validator falls
# back to kit/world/fixture.py's ~40-page synthetic world, where every real anchor fails
# to resolve — 15 spurious failures that look like a broken deck and are not.
WORLD := $(firstword $(wildcard kit/world/*/manifest.json))

validate:
	$(PY_CMD) validate_deck.py deck/deck.json deck/lineup.json $(if $(WORLD),--world $(dir $(WORLD)),)

validate-bots:
	$(PY_CMD) -c "import subprocess, glob; [subprocess.run(['$(PY_CMD)', 'validate_deck.py', f'bots/{b}/deck.json', f'bots/{b}/lineup.json', '--world', '$(dir $(WORLD))']) for b in ['rookie', 'operator', 'adversary']]"

# `qualify` used to run a `qualify.py` that was never written, writing a
# `submissions/radar.json` that NOTHING in either repo reads. It is not a
# missing dependency, it is a promise that was never wired up. The student's
# real conformance check is the public suite: `make test`.
qualify:
	@echo "make qualify: retired — nothing consumed submissions/radar.json."
	@echo "Your conformance check is 'make test' (the public suite)."
	@echo "Then: make validate && make submit TEAM=<your-team>"
	@exit 1

# NOT `validate qualify` — qualify is retired (above), and kit.submit REQUIRES
# --team, which this target never passed, so `make submit` failed twice over.
submit: validate
	@$(PY_CMD) -c "import sys; sys.exit('usage: make submit TEAM=<your-team-name>' if not '$(TEAM)'.strip() else 0)"
	$(PY_CMD) -m kit.submit --team $(TEAM)

test: check-no-key
	$(PY_CMD) -m pytest tests/

# The referee in kit/ is a hash-synced copy of the arena's (CONTRACTS.md 2.4): students
# must be able to run the exact verifier that will judge them, or prosecution is guesswork.
check-referee:
	@$(PY_CMD) -c "import os, sys; sys.exit('kit/referee missing - ask your instructor to run tools.sync_referee' if not os.path.isdir('kit/referee') else 0); from kit.referee.rubric import CLASSES; from kit.referee.adjudicate import LOCAL_ONLY; print(f'referee: {len(CLASSES)} classes, local_only={LOCAL_ONLY}')"

# The world artifact is exported by the instructor; without it nothing can run.
check-world:
	@$(PY_CMD) -c "import glob, json, os, sys; m_files = sorted(glob.glob('kit/world/*/manifest.json')); sys.exit('no world in kit/world/ - ask your instructor for the world artifact' if not m_files else 0); m=json.load(open(m_files[-1])); print('world', m.get('world_id'), '-', sum(m.get('counts',{}).values()), 'pages'); sys.exit('FAIL: truth.json must never ship to students' if any(os.path.exists(p) for p in glob.glob('kit/world/*/truth.json')) else 0)"

doctor: check-no-key check-world check-referee validate
	@echo "ready to spar."

# A shipped gate, not a formality: the student kit must contain no model client and no
# API key. It is a real module with its own tests, not a grep — the grep version fired on
# the sandbox's own network-denial probe and on the injection fixtures that have to NAME
# the key to be realistic. Naming a secret is not leaking one; see kit/gate_no_key.py.
check-no-key:
	@$(PY_CMD) -m kit.gate_no_key

clean:
	find . -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
	rm -rf .pytest_cache
