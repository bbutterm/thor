#!/usr/bin/env python3
"""Fast push checks. The complete suite is still required before a push."""
from __future__ import annotations

import sys

sys.dont_write_bytecode = True
from run_test_suite import main  # noqa: E402

# Broad, measured quick coverage: loading, game flow, dialogue, enemy logic,
# generation, localisation, saves, UI and weapon abilities. Missing scenes fail.
CI_FAST_SCENES = (
    "dialogue_test", "enemy_test", "generator_test", "headless_assets_test",
    "i18n_test", "save_test", "smoke_test", "ui_test", "weapon_skill_test",
)

if __name__ == "__main__":
    print(f"CI fast subset: {len(CI_FAST_SCENES)} scenes; this is not the full suite", flush=True)
    raise SystemExit(main(sys.argv[1:], selected=CI_FAST_SCENES))
