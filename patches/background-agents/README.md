# Patches against background-agents submodule

These patches are applied to the rsync'd working copy at
`.services/background-agents/` after `02-sync-upstream.yml` runs, before
`terraform init`. The upstream submodule at `services/background-agents/` is
never modified.

## How it works

1. `02-sync-upstream.yml` rsyncs the pinned submodule into `.services/`
2. Patches in this directory are applied in numeric order via `ansible.posix.patch`
3. Terraform runs against the patched working copy
4. `.services/` is gitignored and ephemeral; regenerated on every deploy

To toggle patches on for a project, set `patches = true` on its entry in
`config.pkl`'s `projects` map.

## When to update

- After bumping the submodule SHA in `services/background-agents/`
- Verify each patch still applies cleanly: run `mise run deploy --tags=sync,upstream`
  — if a patch fails, ansible.posix.patch reports which hunk and where
- If a patch fails, regenerate it against the new SHA:

```bash
  cd services/background-agents
  # apply your changes by hand
  git diff > ../../patches/background-agents/<patch-name>.patch
  git checkout .
```

## Patches

For the multi-GitHub-App-installation experiment, see
[`MULTI-INSTALLATION.md`](./MULTI-INSTALLATION.md).

### `0001-make-backend-configurable.patch`

Removes the hardcoded `bucket`, `key`, and `region` values from `backend.tf`
so all three can be supplied via `-backend-config` at `terraform init` time.

This is what lets c2 share a single R2 state bucket across multiple projects
(b-a and constructor-mobile) using distinct keys per project, with all values
sourced from `config.pkl` → `state` and rendered by `04-terraform-init.yml`.

### `0002-custom-web-domain.patch`

Adds a `custom_web_app_domain` variable to upstream's production environment.
When set, the web app URL switches from the platform default (workers.dev or
vercel.app) to the custom domain, and a `[[routes]]` block is appended to
`wrangler.production.toml` to register the domain with the worker.

Files touched:
- `variables.tf` — new `custom_web_app_domain` variable, default `""`
- `locals.tf` — `web_app_url` ternary updated to prefer the custom domain;
  new `custom_domain_routes` local builds the TOML fragment
- `web-cloudflare.tf` — interpolates the optional TOML block into the
  generated `wrangler.production.toml`

The variable is wired through from `config.pkl` → `deployment.customWebAppDomain`
→ `inputs.json` → `terraform.tfvars`. Leave it empty to use the platform default.

### `0003-opencode-and-model-list-cleanup.patch`

Two related changes wrapped in one patch:

**OpenCode Go API key wiring.** Adds an optional `opencode_api_key` Terraform
variable and threads it into the `llm-api-keys` Modal secret via `merge()`.
When unset, the key isn't added to the secret at all — Modal doesn't see an
empty `OPENCODE_API_KEY` value that would break OpenCode SDK auth in sandboxes.
The key comes from `config.pkl` → `deployment.openCodeApiKey` (default `""`).

**Default model list cleanup.** Trims `packages/shared/src/models.ts` to a
leaner set:

- *Removed older Anthropic models:* `claude-haiku-4-5`, `claude-sonnet-4-5`,
  `claude-opus-4-5` (all superseded by 4.6/4.7)
- *Removed older OpenAI models:* `gpt-5.2`, `gpt-5.4`, `gpt-5.2-codex`
  (superseded by `gpt-5.5` and `gpt-5.3-codex` variants)
- *Replaced `opencode/` Zen entries with the full `opencode-go/` catalog:*
  GLM 5/5.1, Kimi K2.5/K2.6, DeepSeek V4 Pro/Flash, MiMo V2.5/V2.5 Pro,
  MiniMax M2.5/M2.7, Qwen 3.5/3.6 Plus (12 models)
- OpenCode Go models stay opt-in (not in `DEFAULT_ENABLED_MODELS`); users
  enable them via the web settings page

Files touched:
- `variables.tf` — new `opencode_api_key` variable, default `""`
- `terraform/environments/production/modal.tf` — `llm-api-keys` secret values
  use `merge()` to conditionally include `OPENCODE_API_KEY`
- `packages/shared/src/models.ts` — `VALID_MODELS`, `MODEL_OPTIONS`,
  `MODEL_REASONING_CONFIG`, and `DEFAULT_ENABLED_MODELS` all reflect the
  trimmed roster

> **Maintenance note:** This patch touches `packages/shared/src/models.ts`,
> which is upstream's TypeScript source rather than infrastructure code.
> Upstream is likely to evolve this file as new models land. When bumping
> the submodule SHA, expect this patch to need regeneration more often than
> the others. If the model cleanup is broadly useful, consider opening a PR
> against ColeMurray/background-agents to upstream it, then dropping this
> portion of the patch.

### `0010-web-theme-switching.patch`

Makes the Appearance color scheme control switch the app's shadcn/next-themes
theme, instead of only changing syntax highlighting. The existing Light/Dark/System
selection is moved into its own Theme section, persisted through the existing
syntax-highlight preferences storage, and still controls the matching code
highlighting stylesheet.

Files touched:
- `packages/web/src/components/settings/appearance-settings.tsx` — wires the
  color scheme toggle to `next-themes` via `setTheme()` and separates app theme
  controls from code highlighting theme choices

### `0011-allow-tweakcn-theme-overrides.patch`

Moves the app's built-in CSS variable defaults into Tailwind's `base` layer.
The shadcn CLI appends tweakcn registry themes in that same layer, so this lets
those generated variables override the defaults during Ansible sync. Without
this, the unlayered defaults have higher cascade priority and the applied theme
does not visibly change the UI.

Files touched:
- `packages/web/src/app/globals.css` — wraps the default `:root`, dark media
  query, and `.dark` variable blocks in `@layer base`

## Conventions

- File names follow `NNNN-short-slug.patch` (git format-patch style)
- Numeric prefix controls apply order (sorted lexicographically by Ansible)
- One conceptual change per patch — easier to drop or regenerate individually
- Generate with `git diff > ...` not `git format-patch` (the latter includes
  commit metadata that `ansible.posix.patch` doesn't need)
- After generating, `git checkout .` to discard the working-copy edit — the
  patch system reapplies it via rsync + patch on every deploy
