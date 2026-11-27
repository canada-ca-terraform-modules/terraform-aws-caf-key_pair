## One EC2 key pair, from one of three places (key_pair, README): made by the module at the apply and deleted at the destroy together with
## its private key's secret in Secrets Manager (the default); named, an existing one the plan looks up (it fails when it is missing);
## or imported from a public key. The generated key never enters the state, an output or a log: the scripts in bin/ pipe it from EC2 to
## the secret, so the machine that applies needs bash and the AWS CLI. aws_key_pair cannot do this: it takes a public key, and a
## generated private key would sit in the state.
data "aws_region" "current" {}

locals {
  existing-name = try(var.key_pair.key_name, null)
  public-key    = try(var.key_pair.public_key, null)
  mode          = local.existing-name != null ? "existing" : (local.public-key != null ? "imported" : "generated")

  # Tags - Merging tags provided by ESLZ with tags provided by the user. Name is last so the naming standard wins.
  tags = merge(var.tags, try(var.key_pair.tags, {}), local.module_tag, { Name = local.key-name })
}

data "aws_key_pair" "existing" {
  count = local.mode == "existing" ? 1 : 0

  key_name = local.existing-name
}

resource "aws_key_pair" "this" {
  count = local.mode == "imported" ? 1 : 0

  key_name   = local.key-name
  public_key = local.public-key
  tags       = local.tags
}

# A destroy provisioner reads only self, so what the delete needs travels in input. The name output reads this resource, so an instance
# that uses it is made after the key pair and destroyed before it. The tags are applied when the key pair is made: a change of tags
# alone does not touch it. A failed create leaves this tainted: the next apply deletes what it made, then makes it again.
resource "terraform_data" "generated" {
  count = local.mode == "generated" ? 1 : 0

  triggers_replace = [local.key-name, data.aws_region.current.region]
  input = {
    name     = local.key-name
    region   = data.aws_region.current.region
    role_arn = try(var.key_pair.role_arn, null) == null ? "" : var.key_pair.role_arn
    tags     = local.tags
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/bin/create_key_pair.sh\" \"${self.input.name}\""
    environment = {
      AWS_REGION        = self.input.region
      KEY_PAIR_ROLE_ARN = self.input.role_arn
      KEY_PAIR_TAGS     = jsonencode([for k, v in self.input.tags : { Key = k, Value = v }])
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "bash \"${path.module}/bin/delete_key_pair.sh\" \"${self.input.name}\""
    environment = {
      AWS_REGION        = self.input.region
      KEY_PAIR_ROLE_ARN = self.input.role_arn
      # Only a key pair and a secret this module made (it tags both with its name) are deleted: a create that refused because the name was
      # taken leaves this tainted, and the destroy that follows must not delete the key of someone else.
      KEY_PAIR_REQUIRE_TAG = "module=${self.input.tags.module}"
    }
  }
}
