#!/usr/bin/env bash

set -x

aws cloudformation validate-template \
  --template-body file://cfn.yml

aws cloudformation wait stack-exists \
  --stack-name "$STACK_NAME"

change_set_id="$(aws cloudformation create-change-set \
  --stack-name "$STACK_NAME" \
  --change-set-name "change-set-${LAMBCI_BUILD_NUM}" \
  --template-body file://cfn.yml \
  --capabilities "CAPABILITY_IAM" \
  --role-arn "$CFN_ROLE_ARN" \
  --parameters ParameterKey="KeyPair",ParameterValue="${KEY_PAIR_NAME}" \
  --query "Id" \
  --output "text")"

execution_status=
count=1
while true; do
  execution_status="$(aws cloudformation describe-change-set \
    --change-set-name "$change_set_id" \
    --query '[ExecutionStatus,StatusReason]' \
    --output "json")"

  # if not changes, then break immediately
  [[ "$execution_status" =~ "The submitted information didn't contain changes" ]] && break
  # if returned strings contain 'AVAILABLE', then pass test
  [[ "$execution_status" =~ AVAILABLE ]] && break

  # retry
  echo "Wainting for AVAILABLE... $count retry"
  # currently no waiters for change set
  sleep 10
  count=$(( $count + 1 ))
done

if [[ "$LAMBCI_BRANCH" == "release/cfn" ]]; then
  aws cloudformation execute-change-set \
    --stack-name "$STACK_NAME" \
    --change-set-name "$change_set_id"
fi
