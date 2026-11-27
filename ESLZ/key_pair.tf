terraform {
  required_version = ">= 1.9"
}

variable "key_pairs" {
  description = "Key pairs to deploy, keyed by name"
  type        = any
  default     = {}
}

module "key_pair" {
  source   = "github.com/canada-ca-terraform-modules/terraform-aws-caf-key_pair.git?ref=v1.0.0"
  for_each = var.key_pairs

  userDefinedString = each.key
  env               = var.env
  key_pair          = each.value
  tags              = var.tags
}
