include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "git::${include.root.locals.core_modules_repo}//03-compute?ref=${include.root.locals.core_modules_version}"
}

dependency "foundation" {
  config_path = "../01-foundation"

  mock_outputs = {
    bridges = {
      vmbr0 = "vmbr0"
    }
    os_images = {
      "ubuntu-2204-cloudinit" = "local:iso/jammy-server-cloudimg-amd64.img"
    }
    lxc_templates = {
      "alpine-3-23"      = "local:vztmpl/alpine-3.23-default_20260116_amd64.tar.xz"
      "turnkey-dokuwiki" = "local:vztmpl/debian-12-turnkey-dokuwiki_18.0-1_amd64.tar.gz"
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

dependency "networking" {
  config_path = "../02-networking"

  mock_outputs = {
    vnets = { pubvm = "pubvm" }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

# Values from toadd/compute-tfvars.
# - proxmox_ssh_* and *_state_path are handled by root.hcl/dependencies.
# - cloud_init_templates_dir points to the client-owned templates of this unit.
inputs = {
  vnets         = dependency.networking.outputs.vnets
  bridges       = dependency.foundation.outputs.bridges
  os_images     = dependency.foundation.outputs.os_images
  lxc_templates = dependency.foundation.outputs.lxc_templates

  cloud_init_templates_dir = "${get_terragrunt_dir()}/cloud-init-templates"

  storage_roles = {
    "snippets" = { content = ["snippets"] }
    "images"   = { content = ["images"], datastore = "local-lvm" }
    "rootdir"  = { content = ["rootdir"] }
  }

  extra_bridges = ["vmbr0"]

  virtual_machines = {
    "cloudbox3" = {
      target_node = "pve"
      os_image    = "ubuntu-2204-cloudinit"
      cores       = 2
      cpu_type    = "x86-64-v2-AES"
      memory      = 2048
      serial      = true
      cloud_init = {
        snippet_datastore = "snippets"
        init_datastore    = "images"
        template_file     = "ubuntu-password.yaml.tftpl"
        ssh_keys          = [get_env("LAB_VM_SSH_KEY")]
        template_vars = {
          password = get_env("LAB_VM_PASSWORD")
        }
      }
      interfaces = {
        "net0" = {
          vnet = "pubvm"
          ip   = "172.16.50.26/24"
          gw   = "172.16.50.1"
        }
      }
      disks = {
        "scsi0" = { storage = "images", size = 10 }
      }
    }

    "cloudbox4" = {
      target_node = "pve"
      os_image    = "ubuntu-2204-cloudinit"
      cores       = 2
      cpu_type    = "x86-64-v2-AES"
      memory      = 2048
      serial      = true
      cloud_init = {
        snippet_datastore = "snippets"
        init_datastore    = "images"
        template_file     = "ubuntu-password.yaml.tftpl"
        ssh_keys          = [get_env("LAB_VM_SSH_KEY")]
        template_vars = {
          password = get_env("LAB_VM_PASSWORD")
        }
      }
      interfaces = {
        "net0" = {
          vnet = "pubvm"
          ip   = "172.16.50.16/24"
          gw   = "172.16.50.1"
        }
      }
      disks = {
        "scsi0" = { storage = "images", size = 10 }
      }
    }

    "cloudbox5" = {
      target_node = "pve"
      os_image    = "ubuntu-2204-cloudinit"
      cores       = 2
      cpu_type    = "x86-64-v2-AES"
      memory      = 2048
      serial      = true
      cloud_init = {
        snippet_datastore = "snippets"
        init_datastore    = "images"
        template_file     = "ubuntu-password.yaml.tftpl"
        ssh_keys          = [get_env("LAB_VM_SSH_KEY")]
        template_vars = {
          password = get_env("LAB_VM_PASSWORD")
        }
      }
      interfaces = {
        "net0" = {
          vnet = "pubvm"
          ip   = "172.16.60.16/24"
          gw   = "172.16.60.1"
        }
      }
      disks = {
        "scsi0" = { storage = "images", size = 10 }
      }
    }
  }

  containers = {}
}
