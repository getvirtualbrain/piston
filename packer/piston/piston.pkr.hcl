packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.3"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

locals {
  image_uri = "${var.ecr_registry}/piston:${var.image_tag}"
  # ami_name doit être unique par build (deux bakes du même tag - ex: rerun
  # manuel - ne doivent pas se marcher dessus tant que most_recent choisit la
  # bonne côté Terraform).
  ami_name = substr("piston-${var.environment}-${var.image_tag}-${formatdate("YYYYMMDD-hhmmss", timestamp())}", 0, 128)
}

source "amazon-ebs" "piston" {
  region        = var.aws_region
  instance_type = var.instance_type

  # Instance de build dans un subnet privé, sans IP publique : Packer s'y
  # connecte via SSM Session Manager (agent -> SSM, sortant uniquement), pas
  # de SSH exposé. Nécessite le plugin session-manager-plugin sur le runner
  # CI et les permissions ssm:StartSession sur le rôle GitHub OIDC (cf.
  # aws/modules/oidc AllowPackerPistonAMI dans virtualbrain-terraform).
  ssh_username                = "ubuntu"
  ssh_interface               = "session_manager"
  iam_instance_profile        = var.instance_profile
  subnet_id                   = var.subnet_id
  security_group_id           = var.security_group_id
  associate_public_ip_address = false

  # 099720109477 = Canonical, propriétaire officiel des AMIs Ubuntu
  # (cloud-images.ubuntu.com), même famille d'image que le data "aws_ami" de
  # virtualbrain-terraform (ubuntu-noble-24.04).
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"]
    most_recent = true
  }

  ami_name = local.ami_name

  ami_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size            = var.volume_size
    volume_type            = "gp3"
    delete_on_termination = true
    encrypted              = true
  }

  # Tags lus par le data "aws_ami" côté virtualbrain-terraform
  # (aws/environment/{env}/ec2/data.tf) : most_recent + Service/Environment.
  tags = {
    Name           = local.ami_name
    Service        = "piston"
    Environment    = var.environment
    SourceImageTag = var.image_tag
    ManagedBy      = "packer"
  }

  run_tags = {
    Name    = "packer-piston-builder"
    Service = "piston"
  }
}

build {
  sources = ["source.amazon-ebs.piston"]

  # Packer exécute par défaut les scripts inline via /bin/sh (dash sous
  # Ubuntu), qui ne supporte pas "set -o pipefail" et casse le
  # curl | docker login plus bas : on force bash sur tous les provisioners
  # qui utilisent ces bashismes.
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "cloud-init status --wait",
      "curl -fsSL https://get.docker.com/ | sudo sh",
      "sudo apt-get update -qq && sudo apt-get install -y -qq unzip",
      "curl -fsSL \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o /tmp/awscliv2.zip",
      "unzip -q /tmp/awscliv2.zip -d /tmp",
      "sudo /tmp/aws/install",
      "rm -rf /tmp/aws /tmp/awscliv2.zip",
    ]
  }

  # Pré-télécharge l'image piston dans l'AMI en utilisant le rôle instance
  # (packer-piston-builder, lecture ECR seule) via IMDS - aucune credential
  # long-lived sur la box.
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    environment_vars = [
      "IMAGE_URI=${local.image_uri}",
      "ECR_REGISTRY=${var.ecr_registry}",
      "AWS_REGION=${var.aws_region}",
    ]
    inline = [
      "set -euo pipefail",
      "aws ecr get-login-password --region \"$AWS_REGION\" | sudo docker login --username AWS --password-stdin \"$ECR_REGISTRY\"",
      "sudo docker pull \"$IMAGE_URI\"",
    ]
  }

  # Valide que l'image pré-téléchargée démarre bel et bien avant de
  # promouvoir l'AMI - évite de bake et publier une image cassée.
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    environment_vars = [
      "IMAGE_URI=${local.image_uri}",
    ]
    inline = [
      "set -euo pipefail",
      "sudo docker run -d --rm --name piston-validate --privileged --cgroupns=host -p 2000:2000 --tmpfs /tmp:exec \"$IMAGE_URI\"",
      "for i in $(seq 1 30); do curl -fsS http://localhost:2000/ >/dev/null 2>&1 && break; sleep 2; done",
      "curl -fsS http://localhost:2000/ >/dev/null",
      "sudo docker stop piston-validate",
    ]
  }

  provisioner "file" {
    content     = templatefile("${path.root}/files/piston.service.tftpl", { image_uri = local.image_uri })
    destination = "/tmp/piston.service"
  }

  # enable sans start : le service démarrera au vrai boot de l'instance ASG
  # (systemd multi-user.target), pas ici.
  provisioner "shell" {
    inline_shebang = "/bin/bash -e"
    inline = [
      "sudo mv /tmp/piston.service /etc/systemd/system/piston.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable piston.service",
    ]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
