locals {
  repo_root   = get_repo_root()
  inputs_json = "${local.repo_root}/deploy/inputs.json"
  config      = jsondecode(file(local.inputs_json))

  core_tf = "${local.repo_root}/services/background-agents/terraform/environments/production"
}
