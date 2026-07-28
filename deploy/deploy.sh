#!/usr/bin/env bash
#
# Push the landing page to S3 and invalidate the CloudFront cache.
#
# Usage:  AWS_PROFILE=sesamelabs ./deploy/deploy.sh

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

preflight
read_state

info "uploading index.html -> s3://$BUCKET"
# no-cache means browsers revalidate every load; CloudFront still serves it
# from the edge, and the invalidation below refreshes the edge on each deploy.
aws_ s3 cp "$SITE_DIR/index.html" "s3://$BUCKET/index.html" \
  --content-type "text/html; charset=utf-8" \
  --cache-control "no-cache" \
  --only-show-errors
ok "uploaded"

info "invalidating cloudfront cache"
INVALIDATION_ID="$(awscf create-invalidation --distribution-id "$DIST_ID" \
  --paths '/*' --query 'Invalidation.Id' --output text)"
ok "invalidation $INVALIDATION_ID created"

printf '\n\033[32mdeployed.\033[0m  \033[1m%s\033[0m  (also https://%s)\n' "$SITE_URL" "$DIST_DOMAIN"
