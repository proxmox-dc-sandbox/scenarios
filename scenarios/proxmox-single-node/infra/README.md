# infra/

Contains the scripts and templates of the scenario:

- `scripts/` - Utility shell scripts (dependencies check, ISO download,
  SSH key generation, KVM network, Proxmox VM creation and node
  preparation, up/down/reset wrappers).
- `scripts/lib/` - Sourced helpers: `env.sh` (orchestrator output channel)
  and `pve-ssh.sh` (direct SSH access to the node).
- `scripts/proxmox/` - Unattended Proxmox VE installation (`run.sh` +
  `pve.toml.tpl`) and node preparation (`node-prep.sh`).
- `templates/kvm-network/` - libvirt network definition (isolated network
  with DHCP served by the KVM host, reserved address for the node).

Note: a step working directory is relative to the scenario root; the runner
uses `exec.Cmd.Dir` (no global `chdir`).