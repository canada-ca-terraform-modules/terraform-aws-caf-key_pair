# terraform-aws-caf-key_pair

CAF-compliant Terraform module for one EC2 key pair per module instance, from one of three places. By default the module **makes** the key pair at the apply, keeps its private key in a Secrets Manager secret and **deletes both at the destroy**, without the private key ever entering the state. It can instead look up a key pair that exists, or import a public key. Supports the `aws_key_pair` resource of aws provider `~> 6.68` (tested against `6.71.0`).

## Usage

### ESLZ module block (`ESLZ/key_pair.tf`)

```hcl
module "key_pair" {
  source   = "github.com/canada-ca-terraform-modules/terraform-aws-caf-key_pair.git?ref=v1.0.0"
  for_each = var.key_pairs

  userDefinedString = each.key
  env               = var.env
  key_pair          = each.value
  tags              = var.tags
}
```

Config is always a map keyed by name, so one stack can carry any number of key pairs. See [`ESLZ/key_pair.tfvars`](ESLZ/key_pair.tfvars) for every `key_pair` parameter. The instance takes `module.key_pair["<key>"].name` as its `key_name`.

## Where the key pair comes from

| `key_pair` | What the module does | Resources |
| ---------- | -------------------- | --------- |
| `{}` (the default) | **Makes** `<env>-<name>-key` at the apply and **deletes** it at the destroy, with the secret `keypair/<that name>` that holds its private key | `terraform_data` running `bin/create_key_pair.sh` and `bin/delete_key_pair.sh` |
| `{ key_name = "..." }` | Looks up a key pair that exists (made by `bin/create_key_pair.sh`, or by hand): the plan fails when it is missing | `data.aws_key_pair` |
| `{ public_key = "..." }` | Imports the public key as `<env>-<name>-key`; the owner keeps the private key | `aws_key_pair` |

`key_name` and `public_key` together are rejected. A caller that wants no key pair does not call the module.

### The generated key never enters the state

`aws_key_pair` takes a public key, so a key pair Terraform generates (`tls_private_key`) would keep its private key in the state. The module avoids that: at the apply the script pipes the private key from `aws ec2 create-key-pair` into `aws secretsmanager create-secret`, so it is in no argument, file, output, log or state. It also removes both at the destroy, the secret without a recovery window, and waits until Secrets Manager stops listing it, so a replacement can make the same name at once. The instance reads `name`, which reads the `terraform_data`, so it is made after the key pair and destroyed before it.

- **The machine that applies needs bash and the AWS CLI.** A stack run by a pipeline needs both in its image.
- `key_pair.role_arn` is the role the scripts assume (the one of the stack's provider, which a stack's own credentials are not). Without it they use the ambient credentials. The Region is the provider's.
- The tags are applied to the key pair and the secret when they are made; a change of tags alone does not touch them.
- A failed create leaves the `terraform_data` tainted: the next apply deletes what it made and makes it again. The create script stops, and says so, when a key pair or a secret (also one scheduled for deletion) of that name exists, since EC2 shows a private key once. The delete deletes only a key pair and a secret that carry the module's `module` tag, which the create puts on both, so a name already taken by a key the module did not make is left alone.
- Read the key back: `aws secretsmanager get-secret-value --secret-id keypair/<name> --query SecretString --output text`. A Windows administrator password: `aws ec2 get-password-data --instance-id <id> --priv-launch-key <file holding that key>`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.68 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.71.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_key_pair.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [terraform_data.generated](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_key_pair.existing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/key_pair) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_env"></a> [env](#input\_env) | (Required) env value used in name generation | `string` | n/a | yes |
| <a name="input_key_pair"></a> [key\_pair](#input\_key\_pair) | Object describing where the key pair comes from (see TFVars Parameters in the README): nothing (the default) makes one at the apply and deletes it at the destroy, key\_name names one that exists, public\_key imports one. Optional `name` key overrides the auto-derived "<env>-<userDefinedString>-key" name. | `any` | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the key pair and its secret (merged with key\_pair.tags) | `map(string)` | `{}` | no |
| <a name="input_userDefinedString"></a> [userDefinedString](#input\_userDefinedString) | (Required) UserDefinedString part of the name of the key pair (and of its secret) | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_arn"></a> [arn](#output\_arn) | Returns the ARN of the key pair; null for a key pair the module makes (see id) |
| <a name="output_id"></a> [id](#output\_id) | Returns the ID of the key pair (key-...); null for a key pair the module makes, which EC2 numbers only at the apply and which no resource reads back |
| <a name="output_mode"></a> [mode](#output\_mode) | Returns where the key pair comes from: generated, existing or imported |
| <a name="output_name"></a> [name](#output\_name) | Returns the name of the key pair, to give an instance as key\_name: the one given, or the derived one. Known at the plan, since a caller merges it into configuration that sets counts and for\_each; reading it from the resource still orders the instance after the key pair. |
| <a name="output_secret_name"></a> [secret\_name](#output\_secret\_name) | Returns the Secrets Manager secret that holds the private key of a key pair the module makes; null for the others |
<!-- END_TF_DOCS -->

## TFVars Parameters

Every key of the `key_pair` object. All are optional.

| Parameter | Type | Default | Description |
| --------- | ---- | ------- | ----------- |
| `name` | string | `null` | Optional name used as the whole name. When omitted, defaults to `"<env>-<userDefinedString>-key"`. Either way the case is kept, characters other than letters, digits, `.`, `_` and `-` are removed, and it is cut at 200 characters (the limit of the secret and the scripts; EC2 allows 255). The secret is `keypair/<name>`. |
| `key_name` | string | `null` | The name of a key pair that exists: the module looks it up and makes nothing. |
| `public_key` | string | `null` | A public key to import as the key pair. |
| `role_arn` | string | `null` | The role the scripts assume when the module makes the key pair (the role of the stack's provider). Without it they use the ambient credentials. |
| `tags` | map(string) | `{}` | Merged with ESLZ-level tags, the module tag and the Name. |

## Scope

The module covers `aws_key_pair`, the only resource with that prefix, for the import of a public key, and adds what the provider cannot do: a key pair whose private key is made at the apply without entering the state. The module skill's `coverage_check.sh hashicorp/aws 6.71.0 aws_key_pair .` reports that the resource is covered. Of its arguments, `key_name_prefix` is not exposed (the module always names the key pair) and `region` follows the provider.

Not covered: the key type is RSA (what a Windows administrator password needs); a customer managed KMS key for the secret; rotation of a generated key (replace the key pair, which replaces the instance that launched with it).
