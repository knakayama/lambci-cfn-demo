#!/usr/bin/env bash

aws cloudformation validate-template \
  --template-body file://cfn.yml
[[ $? == 0 ]] || exit 1

aws cloudformation wait stack-exists \
  --stack-name "$STACK_NAME"
[[ $? == 0 ]] || exit 1

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

if [[ "$LAMBCI_BRANCH" == "release/cfn" && -z "$LAMBCI_PULL_REQUEST" ]]; then

  status=
  count=1
  while true; do
    status="$(aws cloudformation describe-change-set \
      --change-set-name "$change_set_id" \
      --query 'Status' \
      --output "text")"

    [[ "$status" == "CREATE_COMPLETE" ]] && break

    echo "Wainting for CREATE_COMPLETE... $count retry"
    sleep 10
    count=$(( $count + 1 ))
  done

  aws cloudformation execute-change-set \
    --stack-name "$STACK_NAME" \
    --change-set-name "$change_set_id"
fi
