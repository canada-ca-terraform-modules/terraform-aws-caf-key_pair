#!/usr/bin/env bash
# Usage: delete_key_pair.sh <key-name>      (the terraform-aws-caf-key_pair module runs it at a destroy; by hand, the same)
#
# The opposite of create_key_pair.sh: deletes the EC2 key pair <key-name> and the Secrets Manager secret keypair/<key-name>, in the
# account and Region of the ambient credentials (or of KEY_PAIR_ROLE_ARN: assume_role.sh), which it prints first. The secret goes with no
# recovery window, also one already scheduled for deletion, so a key of the same name can be made again at once. A key pair or a secret
# that is already gone is no error (a destroy retried after a failure, or a tainted create that made nothing). The private key is
# never read. KEY_PAIR_REQUIRE_TAG=<tag>=<value> deletes only a key pair and a secret that carry that tag, so a destroy that follows a
# create that refused (a name already taken) never deletes a key it did not make; others are left alone and it is no error. It returns once the secret is no longer listed (Secrets Manager takes a few seconds to drop it, and a create at once
# after, as a replacement does, would refuse): KEY_PAIR_WAIT_TRIES polls (default 20), KEY_PAIR_WAIT_SECONDS apart (default 3).
set -euo pipefail

usage() { echo "Usage: ${0##*/} <key-name>   (letters, digits, . _ - ; at most 200)" >&2; exit 2; }

[[ $# == 1 && $1 =~ ^[A-Za-z0-9._-]{1,200}$ ]] || usage
key=$1
secret=keypair/$key

# shellcheck source=assume_role.sh
source "$(dirname "${BASH_SOURCE[0]}")/assume_role.sh"

account=$(aws sts get-caller-identity --query Account --output text)
region=${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2> /dev/null || true)}}
echo "Account $account, Region ${region:-unknown}: deleting the key pair $key and the secret $secret."

tag_name=
tag_value=
if [[ -n ${KEY_PAIR_REQUIRE_TAG:-} ]]; then
  tag_name=${KEY_PAIR_REQUIRE_TAG%%=*}
  tag_value=${KEY_PAIR_REQUIRE_TAG#*=}
fi

# A failed call stops the script (set -e): an API error is never taken for an absence.
if [[ -n $tag_name ]]; then
  key_found=$(aws ec2 describe-key-pairs --filters "Name=key-name,Values=$key" "Name=tag:$tag_name,Values=$tag_value" --query 'KeyPairs[0].KeyName' --output text)
else
  key_found=$key
fi
# delete-key-pair succeeds for a key pair that does not exist.
if [[ -n $key_found && $key_found != None ]]; then
  aws ec2 delete-key-pair --key-name "$key" > /dev/null || {
    echo "The key pair $key could not be deleted: nothing else was deleted." >&2
    exit 1
  }
else
  echo "The key pair $key is absent or not tagged $tag_name=$tag_value, so not made by the module: left alone."
fi

secret_filters=("Key=name,Values=$secret")
if [[ -n $tag_name ]]; then
  secret_filters+=("Key=tag-key,Values=$tag_name" "Key=tag-value,Values=$tag_value")
fi
secret_found=
refresh() {
  secret_found=$(aws secretsmanager list-secrets --include-planned-deletion --filters "${secret_filters[@]}" --query "SecretList[?Name=='$secret'].Name" --output text)
}
refresh
if [[ -n $secret_found && $secret_found != None ]]; then
  aws secretsmanager delete-secret --secret-id "$secret" --force-delete-without-recovery > /dev/null || {
    echo "The secret $secret could not be deleted (the key pair $key is gone): delete it by hand." >&2
    exit 1
  }
  gone=false
  for ((try = 0; try < ${KEY_PAIR_WAIT_TRIES:-20}; try++)); do
    refresh
    if [[ -z $secret_found || $secret_found == None ]]; then
      gone=true
      break
    fi
    sleep "${KEY_PAIR_WAIT_SECONDS:-3}"
  done
  if [[ $gone != true ]]; then
    echo "The secret $secret is deleted but still listed: wait, then make a key of that name again." >&2
    exit 1
  fi
fi
echo "Done."
