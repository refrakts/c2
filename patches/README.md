# Patches against background-agents submodule

These patches are applied to the pinned upstream submodule before `terraform plan`/`apply`.

## When to update

- After bumping the submodule SHA in `services/background-agents/`
- Verify each patch still applies with `git apply --check patches/*.patch` (run from inside the submodule)
- If a patch fails to apply against a new SHA, regenerate it manually

## Patches

- `0001-providers-as-modules.patch` — Removes root-level `provider {}` blocks
  from `terraform/environments/production/versions.tf` so the module can be
  called as a child from our own `deploy/main.tf`. Provider configuration is
  moved to our root, where it belongs in Terraform's module model.
