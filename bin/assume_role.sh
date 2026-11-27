# Sourced by create_key_pair.sh and delete_key_pair.sh. With KEY_PAIR_ROLE_ARN set, every aws call after it runs as that role, the one
# the stack's provider assumes, since a stack runs with the credentials of a person or a pipeline and the provider's role is not
# in this process's environment. The credentials stay in this process's environment: they are never printed or written.
if [[ -n ${KEY_PAIR_ROLE_ARN:-} ]]; then
  credentials=$(aws sts assume-role --role-arn "$KEY_PAIR_ROLE_ARN" --role-session-name key-pair-secret \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
  read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<< "$credentials"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  unset credentials
fi
