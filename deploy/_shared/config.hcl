locals {
  repo_root   = get_repo_root()
  inputs_json = "${local.repo_root}/deploy/inputs.json"
  config      = jsondecode(file(local.inputs_json))

  # The deploy directory itself — Terragrunt's source.
  # Our main.tf composes core (from .terragrunt-source/) and modules.
  deploy_dir = "${local.repo_root}/deploy"
}