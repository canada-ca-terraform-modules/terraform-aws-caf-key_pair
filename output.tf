output "name" {
  description = "Returns the name of the key pair, to give an instance as key_name: the one given, or the derived one. Known at the plan, since a caller merges it into configuration that sets counts and for_each; reading it from the resource still orders the instance after the key pair."
  value = {
    existing  = try(data.aws_key_pair.existing[0].key_name, null)
    imported  = try(aws_key_pair.this[0].key_name, null)
    generated = try(terraform_data.generated[0].input.name, null)
  }[local.mode]
}

output "id" {
  description = "Returns the ID of the key pair (key-...); null for a key pair the module makes, which EC2 numbers only at the apply and which no resource reads back"
  value       = try(data.aws_key_pair.existing[0].id, aws_key_pair.this[0].key_pair_id, null)
}

output "arn" {
  description = "Returns the ARN of the key pair; null for a key pair the module makes (see id)"
  value       = try(data.aws_key_pair.existing[0].arn, aws_key_pair.this[0].arn, null)
}

output "secret_name" {
  description = "Returns the Secrets Manager secret that holds the private key of a key pair the module makes; null for the others"
  value       = local.mode == "generated" ? local.secret-name : null
}

output "mode" {
  description = "Returns where the key pair comes from: generated, existing or imported"
  value       = local.mode
}
