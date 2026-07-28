#!/usr/bin/env bash
#
# One-time infrastructure setup for the landing page.
#
#   S3 bucket (private, all public access blocked)
#     -> CloudFront distribution reaching it via Origin Access Control
#
# Idempotent: safe to re-run. Writes deploy/.deploy-state.json.
#
# Usage:  AWS_PROFILE=sesamelabs ./deploy/provision.sh

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

preflight
resolve_bucket
ACCOUNT="$(account_id)"

info "account $ACCOUNT / region $AWS_REGION / bucket $BUCKET"

# --- 1. bucket ----------------------------------------------------------
if aws_ s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  ok "bucket already exists"
else
  info "creating bucket"
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws_ s3api create-bucket --bucket "$BUCKET" >/dev/null
  else
    aws_ s3api create-bucket --bucket "$BUCKET" \
      --create-bucket-configuration "LocationConstraint=$AWS_REGION" >/dev/null
  fi
  ok "bucket created"
fi

# The bucket stays private end to end — CloudFront is the only reader.
aws_ s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" >/dev/null
ok "public access blocked"

# --- 2. origin access control -------------------------------------------
OAC_ID="$(awscf list-origin-access-controls \
  --query "OriginAccessControlList.Items[?Name=='$OAC_NAME'].Id | [0]" \
  --output text 2>/dev/null || true)"

if [[ -z "$OAC_ID" || "$OAC_ID" == "None" ]]; then
  info "creating origin access control"
  OAC_ID="$(awscf create-origin-access-control --origin-access-control-config "{
      \"Name\": \"$OAC_NAME\",
      \"Description\": \"OAC for $BUCKET\",
      \"SigningProtocol\": \"sigv4\",
      \"SigningBehavior\": \"always\",
      \"OriginAccessControlOriginType\": \"s3\"
    }" --query 'OriginAccessControl.Id' --output text)"
fi
ok "OAC $OAC_ID"

# --- 3. cloudfront distribution -----------------------------------------
ORIGIN_DOMAIN="$BUCKET.s3.$AWS_REGION.amazonaws.com"

DIST_ID="$(awscf list-distributions \
  --query "DistributionList.Items[?Origins.Items[0].DomainName=='$ORIGIN_DOMAIN'].Id | [0]" \
  --output text 2>/dev/null || true)"

if [[ -z "$DIST_ID" || "$DIST_ID" == "None" ]]; then
  info "creating cloudfront distribution (takes a few minutes to deploy)"
  CONFIG="$(mktemp)"
  cat >"$CONFIG" <<JSON
{
  "CallerReference": "dataextra-sesamelabs-$(date +%s)",
  "Comment": "$DIST_COMMENT",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "PriceClass": "PriceClass_100",
  "HttpVersion": "http2and3",
  "IsIPV6Enabled": true,
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "s3-$BUCKET",
        "DomainName": "$ORIGIN_DOMAIN",
        "OriginPath": "",
        "OriginAccessControlId": "$OAC_ID",
        "S3OriginConfig": { "OriginAccessIdentity": "" },
        "ConnectionAttempts": 3,
        "ConnectionTimeout": 10,
        "CustomHeaders": { "Quantity": 0 }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3-$BUCKET",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"] }
    },
    "Compress": true,
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6"
  },
  "ViewerCertificate": { "CloudFrontDefaultCertificate": true }
}
JSON
  RESULT="$(awscf create-distribution --distribution-config "file://$CONFIG")"
  rm -f "$CONFIG"
  DIST_ID="$(jq -r '.Distribution.Id' <<<"$RESULT")"
  ok "distribution created"
else
  ok "distribution already exists"
fi

DIST_DOMAIN="$(awscf get-distribution --id "$DIST_ID" \
  --query 'Distribution.DomainName' --output text)"
ok "distribution $DIST_ID -> $DIST_DOMAIN"

# --- 4. bucket policy scoped to this distribution -----------------------
# Written after the distribution exists, because the policy condition pins
# the exact distribution ARN allowed to read the bucket.
info "attaching bucket policy"
aws_ s3api put-bucket-policy --bucket "$BUCKET" --policy "{
  \"Version\": \"2008-10-17\",
  \"Statement\": [
    {
      \"Sid\": \"AllowCloudFrontServicePrincipalReadOnly\",
      \"Effect\": \"Allow\",
      \"Principal\": { \"Service\": \"cloudfront.amazonaws.com\" },
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::$BUCKET/*\",
      \"Condition\": {
        \"StringEquals\": {
          \"AWS:SourceArn\": \"arn:aws:cloudfront::$ACCOUNT:distribution/$DIST_ID\"
        }
      }
    }
  ]
}"
ok "bucket policy attached"

# --- 5. state -----------------------------------------------------------
jq -n \
  --arg bucket "$BUCKET" --arg region "$AWS_REGION" --arg account "$ACCOUNT" \
  --arg oac "$OAC_ID" --arg dist "$DIST_ID" --arg domain "$DIST_DOMAIN" \
  '{bucket:$bucket, region:$region, account:$account, oacId:$oac,
    distributionId:$dist, distributionDomain:$domain}' >"$STATE_FILE"

printf '\n\033[32mprovisioned.\033[0m  site will be live at: \033[1mhttps://%s\033[0m\n' "$DIST_DOMAIN"
printf 'CloudFront takes ~5-10 min to finish deploying. Now run: ./deploy/deploy.sh\n'
