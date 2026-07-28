# dataextra-sesamelabs — landing page

Static marketing site for the document extraction platform (working name: **Structura**).

## Contents

| File | What it is |
|---|---|
| `index.html` | The live landing page. Self-contained — inline CSS/JS, no build step. |
| `index-editorial.html` | Alternate "editorial" design variant, kept for reference. Not deployed. |
| `landing-content.md` | Source copy for the page. |
| `landing-content.pdf` | Rendered copy deck. |
| `deploy/` | AWS S3 + CloudFront provisioning and deploy scripts. |

The only external dependency is Google Fonts (Poppins), loaded over HTTPS.

## Local preview

```sh
python3 -m http.server 8000
# open http://localhost:8000
```

## Hosting

Hosted on AWS as a static site: **S3 (private) → CloudFront (OAC)**. The bucket is
not public; CloudFront reaches it through an Origin Access Control, which is the
current AWS-recommended pattern (OAI is legacy).

### Region and price class

The bucket defaults to **us-east-1**. The audience is US, it is AWS's cheapest
region, and CloudFront only reads ACM certificates from us-east-1 — so keeping
the bucket there means a future custom subdomain needs nothing outside it.

The distribution runs at **PriceClass_100** (US, Canada, Europe, Israel edges).
Visitors outside those regions are still served correctly, just from a farther
edge. If meaningful traffic starts coming from Asia, raise it to
`PriceClass_200` (adds India, Japan, Singapore) or `PriceClass_All` in
`deploy/provision.sh`.

Override the region per-run if needed:

```sh
AWS_REGION=us-west-2 ./deploy/provision.sh
```

### One-time provisioning

```sh
export AWS_PROFILE=<new-account-profile>
./deploy/provision.sh
```

This creates the S3 bucket, the bucket policy scoped to the distribution, the
Origin Access Control, and the CloudFront distribution. It writes the resulting
IDs to `deploy/.deploy-state.json` (gitignored) and prints the CloudFront domain.

### Deploying a change

```sh
export AWS_PROFILE=<new-account-profile>
./deploy/deploy.sh
```

Syncs `index.html` to the bucket and issues a CloudFront invalidation for `/*`.

### Adding a custom subdomain later

The distribution starts on its default `*.cloudfront.net` domain and CloudFront's
own certificate. Moving to a real subdomain does not require rebuilding anything:

1. Request an ACM certificate for the hostname **in us-east-1** — CloudFront only
   reads certs from that region, regardless of where the bucket lives.
2. Add the DNS validation record and wait for the cert to reach `ISSUED`.
3. Add the hostname to the distribution's `Aliases` and point `ViewerCertificate`
   at the new cert ARN.
4. Add a DNS record for the hostname targeting the distribution domain — an
   ALIAS/A record in Route 53, or a CNAME anywhere else.

### Cache policy

`index.html` is uploaded with `Cache-Control: no-cache` so browsers always
revalidate — CloudFront still caches it at the edge, and the deploy script
invalidates on every push. Any hashed static assets added later should get a
long `max-age` instead.
