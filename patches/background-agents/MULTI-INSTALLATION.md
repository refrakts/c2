# Multi-GitHub App Installation ID Patch Plan

Plan for supporting multiple GitHub App installation IDs on one Constructor / background-agents deployment, applied as c2 patches on top of the rsynced upstream copy at `.services/background-agents/`. The upstream submodule at `services/background-agents/` stays untouched.

## Goals

- One deployment and one GitHub App (`appId` + `privateKey`) with multiple installation IDs.
- `/repos` returns the merged repository list across all configured installations.
- Clone, push, bot, and webhook paths mint tokens for the repository owner installation.
- Keep the patch surface small and ordered by concept.

## Config

```pkl
github {
  app {
    appId = "..."
    privateKey = "..."
    installationId = "111111" // default/fallback
    installations = new Mapping {
      ["org-a"] = "111111"
      ["org-b"] = "222222"
      ["org-c"] = "333333"
      ["org-d"] = "444444"
    }
  }
}
```

Runtime behavior lowercases owner keys for lookup. Unknown owners fall back to `installationId`.

## Viability Notes From Prototype

- Existing patch numbering already includes `0004-include-codex-costs.patch`, so new patches should start at `0005` unless that patch is renumbered.
- c2 can render `github_app_installation_map` as a Terraform `map(string)` and let Terraform use `jsonencode(var.github_app_installation_map)` for Worker and Modal env vars. This is cleaner than forcing Pkl to emit a nested JSON string.
- GitHub token cache keys already include installation ID: `github:installation-token:v1:{appId}:{installationId}`.
- Current `SourceControlProvider.generatePushAuth()` has no repo context; multi-install push support requires changing it to accept optional `GetRepositoryConfig` and passing the session repo owner/name at PR creation.

## Patch Order

| Patch | Slug | Scope |
| --- | --- | --- |
| `0005` | `github-installation-map-env` | Terraform env wiring |
| `0006` | `shared-installation-resolver` | shared parser/resolver |
| `0007` | `control-plane-multi-install` | repo listing, clone token, push token |
| `0008` | `github-bot-webhook-installation` | webhook installation routing |
| `0009` | `modal-clone-token-by-owner` | Modal clone/image token routing |

## Runtime Env

| Variable | Purpose |
| --- | --- |
| `GITHUB_APP_INSTALLATION_ID` | Default/fallback installation ID |
| `GITHUB_APP_INSTALLATION_MAP` | JSON object of owner login to installation ID |

Workers and Modal receive `GITHUB_APP_INSTALLATION_MAP` as a JSON string generated with Terraform `jsonencode()`.

## Resolver API

```ts
parseInstallationMap(raw: string | undefined): Map<string, string>;
resolveInstallationId(owner: string, map: Map<string, string>, defaultInstallationId: string): string;
```

Behavior:

- Missing or invalid JSON returns an empty map.
- Only string values are kept.
- Keys are lowercased on insert and lookup.
- Unknown owners use the default installation ID.

## Implemented Experiment

The current working tree prototypes:

- c2 schema/config example support for `github.app.installations`.
- c2 inputs rendering for `github_app_installation_map` as a map.
- Terraform env wiring in background-agents production files.
- Shared TypeScript resolver with tests.
- Control-plane owner-based config resolution for access checks, branch listing, clone token, and push auth.
- `/repos` cache key bump to `repos:list:v2` and merged multi-install listing for GitHub.

## Remaining Work

- Generate final patch files from the prototype, split by concept.
- Add GitHub bot webhook installation routing using `payload.installation.id` first, owner map fallback second.
- Add Modal Python owner-based token routing for spawn, restore/resume, and image build paths.
- Add focused control-plane tests for merged repo listing and owner-specific push token selection.
- Run full build/test verification after patch generation.

## Manual Test Matrix

| Case | Expected |
| --- | --- |
| `GET /repos` | Repos from all configured installations |
| New session for fallback owner | Clone works with fallback installation |
| New session for mapped owner | Clone works with mapped installation |
| Push/PR for mapped owner | Token minted for mapped installation |
| Bot webhook with `installation.id` | Uses payload installation ID |
| Owner missing from map | Uses fallback installation ID |
| Wrong ID for one owner | Only that owner fails |

## Operations

- Delete `repos:list` and `repos:list:v2` from KV after rollout if stale data exists.
- If the map changes later, delete the current repos cache key or bump it again.
- Restart long-running Modal sandboxes after map changes because clone tokens in env are minted at spawn time.
