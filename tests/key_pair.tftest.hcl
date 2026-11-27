mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "ca-central-1" }
  }
}

variables {
  env               = "G3Cg"
  userDefinedString = "vm1"
}

# Three ways to a key pair: made by the module (the default), named (it exists), or a public key to import. Only the first runs the scripts.
run "a_key_pair_that_is_not_described_is_made_and_removed_by_the_module" {
  command = plan

  assert {
    condition     = length(terraform_data.generated) == 1 && length(data.aws_key_pair.existing) == 0 && length(aws_key_pair.this) == 0
    error_message = "With no key_name and no public_key the module makes the key pair through its scripts and looks nothing up."
  }
  assert {
    condition     = output.mode == "generated" && output.name == "G3Cg-vm1-key" && output.secret_name == "keypair/G3Cg-vm1-key"
    error_message = "The key pair is <env>-<name>-key and its private key is in the secret keypair/<that name>."
  }
  assert {
    condition     = terraform_data.generated[0].input.name == "G3Cg-vm1-key" && terraform_data.generated[0].input.region == "ca-central-1" && terraform_data.generated[0].input.role_arn == ""
    error_message = "The scripts get the name, the Region of the provider and, without a role, the ambient credentials (an empty role)."
  }
  assert {
    condition     = terraform_data.generated[0].input.tags == { Name = "G3Cg-vm1-key", module = "terraform-aws-caf-key_pair" }
    error_message = "The key pair and the secret are tagged with the Name and the module, as every resource of the standard is."
  }
}

run "the_role_and_the_tags_reach_the_scripts" {
  command = plan

  variables {
    tags     = { owner = "team-x" }
    key_pair = { role_arn = "arn:aws:iam::111111111111:role/deploy", tags = { purpose = "admin" } }
  }

  assert {
    condition     = terraform_data.generated[0].input.role_arn == "arn:aws:iam::111111111111:role/deploy"
    error_message = "The scripts assume the role of the provider."
  }
  assert {
    condition     = terraform_data.generated[0].input.tags == { Name = "G3Cg-vm1-key", module = "terraform-aws-caf-key_pair", owner = "team-x", purpose = "admin" }
    error_message = "The tags are var.tags, key_pair.tags, the module tag and the Name."
  }
}

run "a_key_pair_that_exists_is_looked_up_and_nothing_is_made" {
  command = plan

  variables {
    key_pair = { key_name = "G3Ng-app-admin" }
  }

  assert {
    condition     = length(terraform_data.generated) == 0 && length(data.aws_key_pair.existing) == 1 && length(aws_key_pair.this) == 0
    error_message = "With key_name the module looks the key pair up (the plan fails when it is missing) and makes nothing."
  }
  assert {
    condition     = output.mode == "existing" && output.name == "G3Ng-app-admin" && output.secret_name == null
    error_message = "The module returns the name it was given and has no secret."
  }
}

run "a_public_key_is_imported_under_the_derived_name" {
  command = plan

  variables {
    key_pair = { public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl owner@host" }
  }

  assert {
    condition     = length(terraform_data.generated) == 0 && length(data.aws_key_pair.existing) == 0 && length(aws_key_pair.this) == 1
    error_message = "With public_key the module imports it as a key pair and runs no script."
  }
  assert {
    condition     = aws_key_pair.this[0].key_name == "G3Cg-vm1-key" && output.mode == "imported" && output.secret_name == null
    error_message = "The imported key pair has the derived name and no secret (the owner keeps the private key)."
  }
}

run "a_key_pair_cannot_be_named_and_imported_at_once" {
  command = plan

  variables {
    key_pair = { key_name = "G3Ng-app-admin", public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" }
  }

  expect_failures = [var.key_pair]
}

# The name: letters, digits, hyphens, dots and underscores, at most 200 (the secret keypair/<name> and the scripts allow no more).
run "the_shortest_name" {
  command = plan

  variables {
    env               = "A"
    userDefinedString = "b"
  }

  assert {
    condition     = output.name == "A-b-key"
    error_message = "The shortest derived name is <env>-<name>-key."
  }
}

run "the_longest_name_is_200_characters" {
  command = plan

  variables {
    env               = join("", [for i in range(100) : "e"])
    userDefinedString = join("", [for i in range(200) : "u"])
  }

  assert {
    condition     = length(output.name) == 200 && endswith(output.name, "-key")
    error_message = "A name cut at its limit still ends with the suffix."
  }
}

run "a_cut_that_lands_on_a_hyphen_is_trimmed" {
  command = plan

  variables {
    env               = join("", [for i in range(195) : "e"])
    userDefinedString = "uuu"
  }

  assert {
    condition     = output.name == "${join("", [for i in range(195) : "e"])}-key"
    error_message = "The hyphen the cut leaves at the end of the base is trimmed, so the name has no double hyphen."
  }
}

run "an_env_that_is_only_a_hyphen_leaves_no_leading_hyphen" {
  command = plan

  variables {
    env               = "-"
    userDefinedString = "u"
  }

  assert {
    condition     = output.name == "u-key"
    error_message = "A name does not begin with a hyphen."
  }
}

run "characters_a_key_pair_name_cannot_hold_are_removed" {
  command = plan

  variables {
    userDefinedString = "vm 1!"
  }

  assert {
    condition     = output.name == "G3Cg-vm1-key"
    error_message = "Spaces and punctuation outside . _ - are removed."
  }
}

run "a_custom_name_replaces_the_derived_one_and_is_sanitized_like_it" {
  command = plan

  variables {
    key_pair = { name = "My key_pair.1!" }
  }

  assert {
    condition     = output.name == "Mykey_pair.1" && output.secret_name == "keypair/Mykey_pair.1"
    error_message = "A custom name is cleaned of what a key pair name cannot hold and names the secret too."
  }
}

run "a_custom_name_is_cut_at_200_characters" {
  command = plan

  variables {
    key_pair = { name = join("", [for i in range(300) : "n"]) }
  }

  assert {
    condition     = length(output.name) == 200
    error_message = "A custom name is cut at the limit of the secret and the scripts."
  }
}

run "a_custom_name_of_only_removed_characters_falls_back_to_the_derived_name" {
  command = plan

  variables {
    key_pair = { name = "!! ??" }
  }

  assert {
    condition     = output.name == "G3Cg-vm1-key"
    error_message = "A custom name with nothing left after the clean-up gives the derived name, never an empty one."
  }
}

run "a_custom_name_applies_to_an_imported_key_pair_too" {
  command = plan

  variables {
    key_pair = { name = "ops.key", public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" }
  }

  assert {
    condition     = aws_key_pair.this[0].key_name == "ops.key" && output.name == "ops.key"
    error_message = "The custom name is the name of the imported key pair."
  }
}
