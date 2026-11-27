## Names follow Documentation/Standards/AWS-Naming-and-Tagging-Suffixes.md: <env>-<userDefinedString>-<suffix> (key for an EC2 key pair),
## case kept. An EC2 key pair name is at most 255 ASCII characters; the module holds it to 200, which the secret keypair/<name> and the
## scripts (bin/) allow, and to letters, digits, hyphens, dots and underscores. The base is capped at 196 so that "<base>-key" fits 200.
## The secret is named from the key pair: keypair/<name>.
locals {
  name-regex     = "/[^0-9A-Za-z._-]/"
  env-compliant  = replace(var.env, local.name-regex, "")
  name-compliant = replace(var.userDefinedString, local.name-regex, "")

  # Truncate, then trim: the cut (or an empty env) can leave a leading/trailing hyphen.
  base-name-auto = trim(substr("${local.env-compliant}-${local.name-compliant}", 0, 196), "-")

  key-name-custom = trim(substr(replace(try(var.key_pair.name, null) != null ? var.key_pair.name : "", local.name-regex, ""), 0, 200), "-")
  key-name        = local.key-name-custom != "" ? local.key-name-custom : trim("${local.base-name-auto}-key", "-")
  secret-name     = "keypair/${local.key-name}"
}
