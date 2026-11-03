# infra/

Contains the infrastructure-as-code and install scripts of the scenario:

- `terraform/` - Terraform (or OpenTofu) layers: VM, VNet and storage creation.
- `ansible/` - Guest configuration playbooks.
- `scripts/` - Utility shell scripts (up/down/reset, seed, preflight...).
- `*.tfvars` - Environment variables of the Terraform layers.

Note: a step working directory is relative to the scenario root; the runner
uses `exec.Cmd.Dir` (no global `chdir`).
