# Terraform remote-exec / file provisioners upload the script to
# /tmp/terraform_%RAND%.sh and EXECUTE it directly. With /tmp mounted noexec
# (CIS L1) that fails with "Permission denied". Move script_path to a
# directory that is not noexec - the automation user's home.

resource "vsphere_virtual_machine" "vm" {
  # ...

  connection {
    type        = "ssh"
    host        = self.default_ip_address
    user        = "svc_ansible"
    private_key = file(var.ssh_private_key_path)
    script_path = "/home/svc_ansible/terraform_%RAND%.sh"
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = ["cloud-init status --wait"]
  }
}

# Better still: let Terraform only create the VM and hand configuration to
# Ansible (local-exec or the pipeline's next stage). Fewer provisioners =
# fewer things that break under hardening.
