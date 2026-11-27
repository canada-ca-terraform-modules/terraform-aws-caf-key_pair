# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This file must be updated as part of every change to this module.

## [Unreleased]

### Added

- Initial release: one EC2 key pair per module instance, declared with a single `key_pair = each.value`, from one of three places: made by
  the module at the apply and deleted at the destroy with its Secrets Manager secret (the default; `bin/create_key_pair.sh` and
  `bin/delete_key_pair.sh`, run by a `terraform_data`, pipe the private key from EC2 to the secret so it never enters the state), looked
  up when `key_name` names one that exists (`data.aws_key_pair`), or imported from `public_key` (`aws_key_pair`).
- The name is `<env>-<userDefinedString>-key`, letters, digits, `.`, `_` and `-`, at most 200 characters, overridable with `key_pair.name`;
  the secret is `keypair/<name>`. The key pair and the secret are tagged (`tags`, `key_pair.tags`, the module tag and the Name).
- `key_pair.role_arn` is the role the scripts assume, the one of the stack's provider. The delete script waits until Secrets Manager no
  longer lists the secret, so a replacement can make the same name at once.
- The machine that applies needs bash and the AWS CLI; the README says so.
- The delete at a destroy removes only a key pair and a secret tagged with the module's name (`KEY_PAIR_REQUIRE_TAG`), so a create that
  refused because the name was taken, and the destroy that follows it, leave the existing key alone.

### Changed

- The README, the tfvars example, the comments and the tests describe a generic workload, with no product, design document or task named. The only runtime change is the description of the
  secret that the script creates, which no longer names the repository script.
