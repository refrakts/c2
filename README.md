# c2
Constructor²

## Optional Web Theme

Set a tweakcn shadcn theme URL on the `background-agents` project to apply it
during sync before the web app builds:

```pkl
projects {
  ["background-agents"] {
    tweakcnThemeUrl = "https://tweakcn.com/r/themes/neo-brutalism.json"
  }
}
```

## Initial deployment

The first `mise run deploy` runs a two-phase Terraform apply because Cloudflare
Durable Objects require a worker to exist before bindings can reference it.
This is handled automatically; both phases complete in a single `mise run deploy`.

If your first deploy is interrupted mid-flight (Ctrl-C, network failure), the
playbook detects the partial state on the next run and recovers automatically.
You should never need to manually intervene with terraform state.

If you DO see persistent migration tag errors that the recovery flow can't
resolve, the nuclear option is to delete the worker server-side and start fresh:

  wrangler delete --name open-inspect-control-plane-<your-deployment-name>
  cd .services/background-agents/terraform/environments/production
  terraform state rm module.control_plane_worker.cloudflare_worker.this
  terraform state rm module.control_plane_worker.cloudflare_worker_version.this
  terraform state rm module.control_plane_worker.cloudflare_workers_deployment.this
  cd -
  mise run deploy
