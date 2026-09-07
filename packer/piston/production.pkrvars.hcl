# "prod", pas "production" : doit matcher local.environment côté
# virtualbrain-terraform (aws/environment/prod/ec2), consommé tel quel comme
# tag Environment par le data "aws_ami" Terraform.
environment      = "prod"
instance_profile = "packer-piston-builder"

# subnet_id, security_group_id, ecr_registry et image_tag sont propres à
# chaque build (compte AWS / commit) : passés en -var par le workflow CI,
# jamais codés en dur ici.
