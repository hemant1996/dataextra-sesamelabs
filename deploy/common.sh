#!/usr/bin/env bash
# Shared config + helpers for the provision/deploy scripts.
# Sourced, not executed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$SCRIPT_DIR/.deploy-state.json"

# --- overridable settings -----------------------------------------------
AWS_PROFILE="${AWS_PROFILE:-sesamelabs}"
# us-east-1: cheapest region, closest origin for a US launch, and the region
# CloudFront requires ACM certs to live in, so a future subdomain needs no
# second region.
AWS_REGION="${AWS_REGION:-us-east-1}"
BUCKET="${BUCKET:-}"                       # defaults to dataextra-sesamelabs-landing-<accountid>
DIST_COMMENT="dataextra-sesamelabs landing page"
# Public hostname on the distribution. Served via an ACM cert in us-east-1 with
# a CNAME at Namecheap; the *.cloudfront.net domain keeps working too.
SITE_URL="${SITE_URL:-https://structura.sesamelabs.ai}"
OAC_NAME="dataextra-sesamelabs-landing-oac"
# ------------------------------------------------------------------------

export AWS_PROFILE AWS_REGION

aws_() { aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"; }
# CloudFront is a global service; always call it in us-east-1.
awscf() { aws --profile "$AWS_PROFILE" --region us-east-1 cloudfront "$@"; }

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[32m  ok\033[0m %s\n' "$*"; }

preflight() {
  command -v aws >/dev/null || die "aws CLI not found on PATH"
  command -v jq  >/dev/null || die "jq not found on PATH (brew install jq)"

  aws_ sts get-caller-identity >/dev/null 2>&1 \
    || die "profile '$AWS_PROFILE' has no valid credentials. Run: aws configure --profile $AWS_PROFILE"

  # Origin Access Control landed in AWS CLI ~2.7.28 (Aug 2022). Older CLIs lack
  # the subcommand entirely and fail in confusing ways further down.
  if ! awscf list-origin-access-controls --max-items 1 >/dev/null 2>&1; then
    die "this aws CLI ($(aws --version 2>&1)) does not support Origin Access Control.
       Upgrade to AWS CLI v2 (>= 2.7.28):
         curl -o /tmp/AWSCLIV2.pkg https://awscli.amazonaws.com/AWSCLIV2.pkg
         sudo installer -pkg /tmp/AWSCLIV2.pkg -target /"
  fi
}

account_id() { aws_ sts get-caller-identity --query Account --output text; }

resolve_bucket() {
  if [[ -z "$BUCKET" ]]; then
    BUCKET="dataextra-sesamelabs-landing-$(account_id)"
  fi
}

read_state() {
  [[ -f "$STATE_FILE" ]] || die "no $STATE_FILE. Run ./deploy/provision.sh first"
  BUCKET="$(jq -r .bucket "$STATE_FILE")"
  DIST_ID="$(jq -r .distributionId "$STATE_FILE")"
  DIST_DOMAIN="$(jq -r .distributionDomain "$STATE_FILE")"
  AWS_REGION="$(jq -r .region "$STATE_FILE")"
  export AWS_REGION
}
