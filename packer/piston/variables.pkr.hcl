variable "aws_region" {
  type    = string
  default = "eu-west-3"
}

# Doit correspondre exactement à local.environment côté virtualbrain-terraform
# (aws/environment/{env}/ec2/versions.tf) : "staging" ou "prod" (pas
# "production") - c'est la valeur du tag Environment que le data "aws_ami"
# Terraform filtre pour choisir la dernière AMI baked. Le nom de
# l'environnement GitHub, lui, s'appelle "production" (cf. workflow) : ne pas
# confondre les deux.
variable "environment" {
  type = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "Environment must be staging or prod, matching Terraform's local.environment rather than the GitHub environment name."
  }
}

# Tag ECR immuable à figer dans l'AMI, ex: python-3.13-staging-<sha12> (jamais
# le tag flottant python-3.13-<env>) : garantit une AMI reproductible et un
# rollback fiable en repointant simplement sur un ancien SourceImageTag.
variable "image_tag" {
  type = string
}

# Hostname du registre ECR, ex: <account_id>.dkr.ecr.eu-west-3.amazonaws.com
# (= steps.ecr.outputs.registry de aws-actions/amazon-ecr-login dans le
# workflow appelant).
variable "ecr_registry" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "m6i.large"
}

# Subnet privé + security group pour l'instance de build transitoire.
# Valeurs = outputs Terraform packer_piston_builder_subnet_id /
# packer_piston_builder_security_group_id (aws/environment/{env}/ec2),
# reportées manuellement dans les variables de l'environnement GitHub
# correspondant (PACKER_BUILDER_SUBNET_ID / PACKER_BUILDER_SECURITY_GROUP_ID).
variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "instance_profile" {
  type    = string
  default = "packer-piston-builder"
}

variable "volume_size" {
  type    = number
  default = 50
}
