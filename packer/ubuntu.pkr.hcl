# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

# Ubuntu runner AMI. Packer boots the current Ubuntu cloud image, runs
# provision/*.sh over SSH, gates on the vulnerability scan, makes the AMI
# and copies it to ami_regions.

packer {
  required_version = "= 1.16.1"
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "= 1.8.2"
    }
  }
}

variable "arch" {
  type = string
  validation {
    condition     = contains(["amd64", "arm64"], var.arch)
    error_message = "The arch must be amd64 or arm64."
  }
}

variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "ami_regions" {
  type        = list(string)
  default     = []
  description = "Regions to copy the AMI to, besides the build region."
}

variable "image_version" {
  type        = string
  description = "Version that names the image, such as 20261012.1739."
}

variable "ubuntu_release" {
  type    = string
  default = "26.04"
}

variable "runner_version" {
  type = string
}

variable "agent_version" {
  type = string
}

variable "subnet_id" {
  type    = string
  default = ""
}

variable "ami_groups" {
  type        = list(string)
  default     = ["all"]
  description = "Groups the AMI is shared with. Pass [] to keep it private to the building account."
}

variable "output_dir" {
  type        = string
  default     = "out"
  description = "Where the scan result and the manifest are written."
}

locals {
  name = "hatchrun-ubuntu${split(".", var.ubuntu_release)[0]}-${var.arch}-${var.image_version}"
  # Small instances keep a build at a few cents; the IAM role allows
  # only these types.
  instance_type = var.arch == "amd64" ? "c7i.large" : "c7g.large"
}

data "amazon-parameterstore" "base_ami" {
  region = var.region
  name   = "/aws/service/canonical/ubuntu/server/${var.ubuntu_release}/stable/current/${var.arch}/hvm/ebs-gp3/ami-id"
}

source "amazon-ebs" "ubuntu" {
  region          = var.region
  source_ami      = data.amazon-parameterstore.base_ami.value
  instance_type   = local.instance_type
  subnet_id       = var.subnet_id
  ami_name        = local.name
  ami_description = "hatchrun runner, Ubuntu ${var.ubuntu_release} ${var.arch}, runner ${var.runner_version}, hatchrun-agent ${var.agent_version}"
  ami_regions     = var.ami_regions
  # Public in every region by default, so users launch the AMI where they
  # run and never need to copy it. Only the AMI is shared; the snapshots
  # stay private.
  ami_groups = var.ami_groups

  # SSH is open to this machine's public IP only, for the length of the
  # build, with a throwaway ed25519 key.
  communicator                              = "ssh"
  ssh_username                              = "ubuntu"
  temporary_key_pair_type                   = "ed25519"
  temporary_security_group_source_public_ip = true
  associate_public_ip_address               = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Unencrypted so the AMI can be made public. Launch templates encrypt
  # each runner's copy and pick its size.
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
  }

  run_tags = {
    Name                   = "${local.name}-builder"
    "hatchrun:image-build" = local.name
  }
  tags = {
    Name                     = local.name
    "hatchrun:image-version" = var.image_version
    "hatchrun:arch"          = var.arch
    "hatchrun:base-ami"      = data.amazon-parameterstore.base_ami.value
  }
  snapshot_tags = {
    Name                     = local.name
    "hatchrun:image-version" = var.image_version
    "hatchrun:arch"          = var.arch
  }
}

build {
  sources = ["source.amazon-ebs.ubuntu"]

  # Provisioning races the package updates cloud-init starts at boot.
  provisioner "shell" {
    inline = ["cloud-init status --wait > /dev/null"]
  }

  provisioner "file" {
    source      = "${path.root}/../versions.env"
    destination = "/tmp/versions.env"
  }

  provisioner "shell" {
    scripts = [
      "${path.root}/../provision/00-base.sh",
      "${path.root}/../provision/10-docker.sh",
      "${path.root}/../provision/20-runner-user.sh",
      "${path.root}/../provision/30-actions-runner.sh",
      "${path.root}/../provision/40-hatchrun-agent.sh",
      "${path.root}/../provision/50-toolcache.sh",
      "${path.root}/../provision/60-boot.sh",
      "${path.root}/../provision/80-scan.sh",
    ]
    environment_vars = ["IMAGE_VERSION=${var.image_version}"]
    execute_command  = "chmod +x {{ .Path }}; sudo env {{ .Vars }} bash -c 'set -a; . /tmp/versions.env; set +a; exec {{ .Path }}'"
  }

  provisioner "file" {
    direction   = "download"
    source      = "/tmp/hatchrun-scan.json"
    destination = "${var.output_dir}/scan-${var.arch}.json"
  }

  # A fixable HIGH or CRITICAL vulnerability stops the build here, before
  # any AMI exists or is copied.
  provisioner "shell-local" {
    inline = ["${path.root}/../scripts/check-scan.sh ${var.output_dir}/scan-${var.arch}.json"]
  }

  provisioner "shell" {
    script          = "${path.root}/../provision/90-cleanup.sh"
    execute_command = "chmod +x {{ .Path }}; sudo bash {{ .Path }}"
  }

  post-processor "manifest" {
    output     = "${var.output_dir}/packer-manifest-${var.arch}.json"
    strip_path = true
  }
}
