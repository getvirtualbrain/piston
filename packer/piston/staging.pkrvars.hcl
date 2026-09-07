environment      = "staging"
instance_profile = "packer-piston-builder"

# subnet_id, security_group_id, ecr_registry et image_tag sont propres à
# chaque build (compte AWS / commit) : passés en -var par le workflow CI,
# jamais codés en dur ici.
