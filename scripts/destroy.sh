#!/usr/bin/env bash
# Tears down everything deploy.sh created for one environment, then checks nothing is left.
# Usage: scripts/destroy.sh <dev|stage|prod>
set -euo pipefail
ENVIRONMENT="${1:?usage: destroy.sh <dev|stage|prod>}"

for stack in "greeter-site-${ENVIRONMENT}" "greeter-pipeline-${ENVIRONMENT}"; do
  BUCKETS=$(aws cloudformation describe-stack-resources --stack-name "$stack" \
    --query "StackResources[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" --output text 2>/dev/null || true)
  for b in $BUCKETS; do
    # Versioned buckets must be emptied of all versions before CloudFormation can delete them.
    aws s3api list-object-versions --bucket "$b" --output json \
      --query '{Objects: [Versions, DeleteMarkers][][].{Key:Key,VersionId:VersionId}}' > /tmp/del.json || true
    if grep -q '"Key"' /tmp/del.json; then aws s3api delete-objects --bucket "$b" --delete file:///tmp/del.json >/dev/null; fi
  done
  aws cloudformation delete-stack --stack-name "$stack"
  aws cloudformation wait stack-delete-complete --stack-name "$stack"
  echo "deleted $stack"
done

echo "leftover check:"
aws ecr describe-repositories --query "repositories[?contains(repositoryName,'greeter-${ENVIRONMENT}')].repositoryName" --output text
aws codepipeline list-pipelines --query "pipelines[?contains(name,'greeter-${ENVIRONMENT}')].name" --output text
aws cloudfront list-distributions --query "DistributionList.Items[?contains(Comment||'','greeter')].Id" --output text 2>/dev/null || true
echo "(blank lines above mean nothing is left)"
