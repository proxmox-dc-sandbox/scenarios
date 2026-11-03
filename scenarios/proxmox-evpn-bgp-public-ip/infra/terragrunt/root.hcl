# ---------------------------------------------------------------------------
# Client project root configuration.
#
# Extracted from terragrunt-client.zip (modules repository, toadd/) and
# integrated into the scenario. It is a standalone client project: it is not
# part of the modules repository.
#
# The units consume pdcs-core-tf-modules through an immutable pinned tag,
# defined once here (core_modules_repo + core_modules_version). States and
# generated files stay local to each unit.
# ---------------------------------------------------------------------------
locals {
  # --- core-tf-modules: pinned source ---------------------------------
  core_modules_repo = "https://github.com/proxmox-dc-sandbox/core-tf-modules.git"
  scenario_dir         = dirname(dirname(dirname(get_terragrunt_dir())))
  repo_root            = dirname(dirname(local.scenario_dir))
  core_modules_version = "v0.1.0"

  # --- Proxmox node / credentials -------------------------------------------
  proxmox_node_name    = get_env("PROXMOX_NODE_NAME")
  proxmox_node_address = get_env("PROXMOX_NODE_ADDRESS")
  # Credentials: an API token is used when provided; otherwise the provider
  # falls back to root password auth (PVE_ROOT_PASSWORD, generated and
  # persisted by the orchestrator), so a first run never needs a token that does not
  # exist yet. Same logic for SSH: key when a path is provided, password
  # otherwise.
  api_token     = get_env("PROXMOX_VE_API_TOKEN")
  root_password = get_env("PVE_ROOT_PASSWORD")
  ssh_key_path  = get_env("PROXMOX_VE_SSH_PRIVATE_KEY_PATH")
  ssh_password  = get_env("PROXMOX_VE_SSH_PASSWORD")
  # When the node is behind a bastion, the SSH proxy started by the
  # bastion-proxy step is used by the provider SSH (snippets uploads).
  ssh_socks5 = get_env("PROXMOX_VE_SSH_SOCKS5")
}

# State backend, generated per unit. Each layer keeps its own state.
remote_state {
  backend = "local"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}

# Provider configuration, generated per unit. Credentials come from the
# environment:
#   PROXMOX_VE_ENDPOINT
#   PROXMOX_VE_API_TOKEN
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    provider "proxmox" {
      insecure = ${get_env("PROXMOX_VE_INSECURE")}
      %{if local.api_token != ""~}
      api_token = "${local.api_token}"
      %{else~}
      username = "${get_env("PROXMOX_VE_USERNAME")}"
      password = "${local.root_password}"
      %{endif~}

      ssh {
        agent    = ${get_env("PROXMOX_VE_SSH_AGENT")}
        username = "${get_env("PROXMOX_VE_SSH_USERNAME")}"
        password = "${local.ssh_password}"
        %{if local.ssh_key_path != ""~}
        private_key = try(file("${local.ssh_key_path}"), null)
        %{endif~}
        %{if local.ssh_socks5 != ""~}
        socks5_server = "${local.ssh_socks5}"
        %{endif~}

        node {
          name    = "${local.proxmox_node_name}"
          address = "${local.proxmox_node_address}"
        }
      }
    }
  EOF
}
