# Terraform layer

Creation of the VMs, VNets and Proxmox resources of the scenario.

The step directory is used as the working dir (exec.Cmd.Dir, no chdir);
`terraform init` is run automatically when `.terraform/` is missing, and
`-var-file=terraform.tfvars` is passed when that file exists.
