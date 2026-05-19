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

### `0011-google-ai-studio.patch`

Adds Google AI Studio (Gemini) as a supported model provider, mirroring the
opt-in shape of OpenCode Go in `0003`.

**API key wiring.** New `google_ai_studio_api_key` Terraform variable threaded
into the `llm-api-keys` Modal secret via the same conditional `merge()`
pattern. When unset, `GOOGLE_GENERATIVE_AI_API_KEY` is omitted from the secret
entirely (the `@ai-sdk/google` provider reads that env var by default — see
[ai-sdk.dev](https://ai-sdk.dev/providers/ai-sdk-providers/google-generative-ai)).
The value comes from `config.pkl` → `deployment.inferenceKeys.googleAiStudio`
(optional, default `null` → empty string).

**Model registry.** Adds two Gemini models to `packages/shared/src/models.ts`:

- `google/gemini-3.1-pro-preview` — Google flagship
- `google/gemini-3.1-pro-preview-customtools` — custom-tools variant

Both expose `efforts: ["low", "high"]` in `MODEL_REASONING_CONFIG` (default
`"high"`). Google models stay opt-in (not in `DEFAULT_ENABLED_MODELS`); users
enable them via the web settings page. `normalizeModelId` also learns to
prefix bare `gemini-*` IDs with `google/` for backward-compat with stored
data.

**Reasoning effort plumbing.** Adds a `provider_id == "google"` branch to
`bridge.py::_build_prompt_request_body` that translates the existing
`reasoning_effort` string into the AI SDK's
`providerOptions.google.thinkingConfig.thinkingLevel`. Gemini 3 models use a
categorical level (`"minimal" | "low" | "medium" | "high"`) rather than
OpenAI-style effort strings or Anthropic-style token budgets, so the branch
passes the effort through 1:1 when it matches and falls back to `"high"` for
unrelated levels (e.g. `"max"`/`"xhigh"`). `includeThoughts: true` surfaces
reasoning summaries the same way OpenAI's `reasoningSummary: "auto"` does.

Files touched:
- `terraform/environments/production/variables.tf` — new
  `google_ai_studio_api_key` variable, default `""`
- `terraform/environments/production/modal.tf` — extends the
  `llm-api-keys` `merge()` with a conditional
  `GOOGLE_GENERATIVE_AI_API_KEY` entry
- `packages/shared/src/models.ts` — adds `VALID_MODELS`, `MODEL_OPTIONS`,
  `MODEL_REASONING_CONFIG` entries and a `gemini-` normalization rule
- `packages/sandbox-runtime/src/sandbox_runtime/bridge.py` — adds the
  `google` branch alongside the existing `anthropic`/`openai` branches

> **Ordering note:** This patch depends on `0003` for its `modal.tf`,
> `variables.tf`, and `models.ts` context (the `merge()` call and the
> trimmed model lists must already be in place). Apply order is enforced
> by the numeric file-name prefix.

### `0010-web-theme.patch`

Two closely related changes to the web app's theme system, kept in one patch
because the tweakcn override fix is only observable once the Appearance toggle
actually drives `next-themes`.

**Appearance toggle drives next-themes.** The Light/Dark/System selection in
Settings → Appearance was previously wired only to syntax highlighting. The
patch moves it into its own Theme section and threads it through
`next-themes.setTheme()` so the toggle now switches the app's shadcn/next-themes
theme as well. The selection still persists through the existing
syntax-highlight preferences storage and still controls the matching code
highlighting stylesheet.

**Tweakcn theme overrides actually apply.** The app's built-in CSS variable
defaults are moved into Tailwind's `base` layer. The shadcn CLI appends tweakcn
registry themes in that same layer, so this lets those generated variables
override the defaults during Ansible sync. Without this, the unlayered defaults
have higher cascade priority and the applied theme does not visibly change the
UI.

Files touched:
- `packages/web/src/components/settings/appearance-settings.tsx` — wires the
  color scheme toggle to `next-themes` via `setTheme()` and separates app theme
  controls from code highlighting theme choices
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
