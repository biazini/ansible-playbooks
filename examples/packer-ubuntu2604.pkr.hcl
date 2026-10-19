# Fragment only - merge into your vsphere-iso build.
#
# Two things matter for CIS:
#  1. Disk layout is decided HERE (autoinstall). Separate /var, /var/log,
#     /var/log/audit, /var/tmp and /home were Level 2 in the 22.04/24.04
#     benchmarks; /tmp is handled as tmpfs by the role. Decide now - it cannot
#     be fixed cheaply after deployment.
#  2. The shell provisioner uploads scripts to remote_folder (default /tmp)
#     and executes them. Run them through bash so noexec never matters.

build {
  sources = ["source.vsphere-iso.ubuntu2604"]

  provisioner "shell" {
    remote_folder   = "/home/packer"
    execute_command = "echo '${var.ssh_password}' | sudo -S -E bash '{{ .Path }}'"
    inline          = ["cloud-init status --wait || true"]
  }

  provisioner "ansible" {
    playbook_file   = "../ubuntu-cis-l1/playbooks/site.yml"
    user            = "packer"
    use_proxy       = false
    extra_arguments = [
      "--extra-vars", "cis_template_build=true cis_allow_reboot=false",
      "--extra-vars", "@../ubuntu-cis-l1/inventories/example/group_vars/all.yml",
    ]
    ansible_env_vars = ["ANSIBLE_CONFIG=../ubuntu-cis-l1/ansible.cfg"]
  }

  provisioner "ansible" {
    playbook_file = "../ubuntu-cis-l1/playbooks/seal-template.yml"
    user          = "packer"
    use_proxy     = false
  }
}

# NOTE: during the Packer build the connecting user is "packer", not
# svc_ansible. Add "packer" to cis_ssh_allow_groups (or to the automation
# group) for the build, and remove the packer user in seal-template.yml or via
# cloud-init on first boot.
