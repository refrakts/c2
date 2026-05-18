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

### `0001-make-bucket-configurable.patch`

Removes the hardcoded `bucket = "open-inspect-terraform-state"` from `backend.tf`
so the bucket name can be supplied via `-backend-config` at `terraform init` time.

Without this patch, every deployment of c2 would share upstream's bucket name —
fine for a single tenant, broken for multiple friends each using their own R2
account. The bucket value comes from `config.pkl` → `state.bucket` and is
written into `backend.tfvars` by `04-terraform-init.yml`.

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

## Conventions

- File names follow `NNNN-short-slug.patch` (git format-patch style)
- Numeric prefix controls apply order (sorted lexicographically by Ansible)
- One conceptual change per patch — easier to drop or regenerate individually
- Generate with `git diff > ...` not `git format-patch` (the latter includes
  commit metadata that `ansible.posix.patch` doesn't need)
- After generating, `git checkout .` to discard the working-copy edit — the
  patch system reapplies it via rsync + patch on every deploy