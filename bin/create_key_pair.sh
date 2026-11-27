#!/usr/bin/env bash
# Usage: create_key_pair.sh <key-name>      (the terraform-aws-caf-key_pair module runs it at an apply; it can also be run by hand)
#
# Makes the EC2 key pair <key-name> (RSA, 2048 bits: what EC2 generates) and keeps its private key in the Secrets Manager secret
# keypair/<key-name>, in the account and Region of the ambient credentials (AWS_PROFILE, AWS_REGION or AWS_DEFAULT_REGION), which it
# prints before it makes anything (with KEY_PAIR_ROLE_ARN set, those of that role: assume_role.sh). The private key goes from EC2 to
# Secrets Manager through a pipe: it is never in a file, on the terminal or in Terraform state (the stacks only name the key pair); a
# stub test cannot prove "never in a file", the pipe is the design. KEY_PAIR_TAGS, a JSON list of {"Key", "Value"}, tags both.
# It refuses when the key pair or the secret (also one scheduled for deletion) exists, since EC2 shows a private key once, and it
# deletes the key pair again when the secret cannot be made.
# Read the key back: aws secretsmanager get-secret-value --secret-id keypair/<key-name> --query SecretString --output text
set -euo pipefail

usage() { echo "Usage: ${0##*/} <key-name>   (letters, digits, . _ - ; at most 200)" >&2; exit 2; }

[[ $# == 1 && $1 =~ ^[A-Za-z0-9._-]{1,200}$ ]] || usage
# shellcheck source=assume_role.sh
source "$(dirname "${BASH_SOURCE[0]}")/assume_role.sh"

key=$1
secret=keypair/$key

account=$(aws sts get-caller-identity --query Account --output text)
region=${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2> /dev/null || true)}}
echo "Account $account, Region ${region:-unknown}: making the key pair $key and the secret $secret."

found=$(aws ec2 describe-key-pairs --filters "Name=key-name,Values=$key" --query 'KeyPairs[0].KeyName' --output text)
if [[ $found != None && -n $found ]]; then
  echo "The key pair $key already exists: nothing done (EC2 shows a private key only when it is made)." >&2
  echo "If an earlier run left it without its secret: aws ec2 delete-key-pair --key-name $key, then run this again." >&2
  exit 1
fi

found=$(aws secretsmanager list-secrets --include-planned-deletion --filters "Key=name,Values=$secret" --query "SecretList[?Name=='$secret'].Name" --output text)
if [[ -n $found && $found != None ]]; then
  echo "The secret $secret already exists or is scheduled for deletion: nothing done." >&2
  exit 1
fi

# KEY_PAIR_TAGS, when set, is a JSON list of {"Key": ..., "Value": ...}: the tags of the key pair and of the secret.
key_tags=()
secret_tags=()
if [[ -n ${KEY_PAIR_TAGS:-} ]]; then
  key_tags=(--tag-specifications "[{\"ResourceType\":\"key-pair\",\"Tags\":$KEY_PAIR_TAGS}]")
  secret_tags=(--tags "$KEY_PAIR_TAGS")
fi

# Secrets Manager refuses an empty secret string, so a key pair that cannot be made stores nothing.
# The statuses of both ends of the pipe: the key pair is deleted again only when this script made it and the secret failed.
set +e
aws ec2 create-key-pair --key-name "$key" --key-type rsa --key-format pem ${key_tags[@]+"${key_tags[@]}"} --query KeyMaterial --output text |
  aws secretsmanager create-secret --name "$secret" --description "Private key of the EC2 key pair $key" \
    --secret-string file:///dev/stdin ${secret_tags[@]+"${secret_tags[@]}"} --query Name --output text > /dev/null
statuses=("${PIPESTATUS[@]}")
set -e

if ((statuses[0] != 0)); then
  echo "The key pair $key could not be made: nothing was stored." >&2
  exit 1
fi
if ((statuses[1] != 0)); then
  if aws ec2 delete-key-pair --key-name "$key" > /dev/null; then
    echo "The secret $secret could not be made: the new key pair $key was deleted." >&2
  else
    echo "The secret $secret could not be made and the key pair $key could not be deleted: delete it by hand (aws ec2 delete-key-pair --key-name $key)." >&2
  fi
  exit 1
fi
echo "Key pair $key made; its private key is in the secret $secret."
