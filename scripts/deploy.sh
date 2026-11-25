#!/usr/bin/env bash
# Deploys the pipeline stack and the static-site stack for one environment.
# Usage: scripts/deploy.sh <dev|stage|prod> <connection-arn> [sonar-host-url sonar-token-secret-arn]
# Run from AWS CloudShell or any shell with AWS credentials. Costs: see README.
set -euo pipefail

ENVIRONMENT="${1:?usage: deploy.sh <dev|stage|prod> <connection-arn> [sonar-host-url sonar-token-secret-arn]}"
CONNECTION_ARN="${2:?connection arn required (create and authorize a GitHub connection first)}"
SONAR_URL="${3:-}"
SONAR_SECRET="${4:-}"

case "$ENVIRONMENT" in
  dev)   BRANCH=develop ;;
  stage) BRANCH=release ;;
  prod)  BRANCH=main ;;
  *) echo "environment must be dev, stage or prod" >&2; exit 1 ;;
esac

cd "$(dirname "$0")/.."

aws cloudformation deploy \
  --stack-name "greeter-pipeline-${ENVIRONMENT}" \
  --template-file cloudformation/pipeline.yml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    Environment="$ENVIRONMENT" Branch="$BRANCH" ConnectionArn="$CONNECTION_ARN" \
    SonarHostUrl="$SONAR_URL" SonarTokenSecretArn="$SONAR_SECRET"

aws cloudformation deploy \
  --stack-name "greeter-site-${ENVIRONMENT}" \
  --template-file cloudformation/static-site.yml \
  --parameter-overrides Environment="$ENVIRONMENT"

BUCKET=$(aws cloudformation describe-stacks --stack-name "greeter-site-${ENVIRONMENT}" \
  --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text)
aws s3 sync site/ "s3://${BUCKET}/" --delete

aws cloudformation describe-stacks --stack-name "greeter-site-${ENVIRONMENT}" \
  --query "Stacks[0].Outputs[?OutputKey=='DistributionDomain'].OutputValue" --output text \
  | sed 's#^#Site: https://#'
