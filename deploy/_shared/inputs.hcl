include "config" {
  path = "./config.hcl"
}

inputs = {
  for k, v in include.config.locals.config :
  k => v
  if !startswith(k, "state_")
}
