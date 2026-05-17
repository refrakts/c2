# Patches against background-agents submodule

These patches are applied to the pinned upstream submodule before `terragrunt apply`.

## When to update

- After bumping the submodule SHA in `services/background-agents/`
- Verify each patch still applies with `git apply --check patches/*.patch` from inside the submodule
- If a patch fails, regenerate it manually against the new SHA

## Patches

(none yet — will add outputs-exposing patches when mobile needs cross-unit references)
