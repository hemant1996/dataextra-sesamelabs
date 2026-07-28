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

Live at **https://structura.sesamelabs.ai**.

Hosted on AWS as a static site: **S3 (private) → CloudFront (OAC)**. The bucket is
not public; CloudFront reaches it through an Origin Access Control, which is the
current AWS-recommended pattern (OAI is legacy).

AWS account `046497227076`, CLI profile `sesamelabs`. The distribution's own
`*.cloudfront.net` domain keeps working alongside the custom one.

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

### DNS — read this before changing anything

**`sesamelabs.ai` DNS is served by Namecheap, not AWS.** The live nameservers are
`dns1/dns2.registrar-servers.com`, and the domain carries **Google Workspace mail**
(`MX → smtp.google.com`) plus a Google verification `TXT` record.

There is also a Route 53 hosted zone for `sesamelabs.ai` in the AWS account. It is
**empty and not authoritative** — it holds only NS and SOA records. Repointing the
registrar's nameservers at it would take down email immediately. Either leave DNS
at Namecheap, or migrate every existing record into Route 53 *first* and verify,
then switch.

Records added at Namecheap for this site (both `CNAME`):

| Host | Value | Purpose |
|---|---|---|
| `structura` | `d1scsx7o0g41td.cloudfront.net` | points the subdomain at CloudFront |
| `_b8b3a5ad….structura` | `….acm-validations.aws` | ACM validation — **do not delete** |

Leave the validation record in place permanently. ACM re-checks it to renew the
certificate automatically; removing it eventually breaks renewal.

### How the custom domain is wired

1. ACM certificate for `structura.sesamelabs.ai`, issued **in us-east-1** —
   CloudFront reads certificates only from that region, wherever the bucket lives.
2. DNS-validated via the CNAME above.
3. Distribution has the hostname in `Aliases`, with `ViewerCertificate` set to the
   ACM ARN, `sni-only`, minimum TLS `TLSv1.2_2021`.
4. Namecheap CNAME points the hostname at the distribution domain.

Adding another hostname later repeats the same four steps. Note that a CNAME
cannot sit at a zone apex — a bare `sesamelabs.ai` would need either Route 53
ALIAS records or Namecheap's ALIAS record type.

### Cache policy

`index.html` is uploaded with `Cache-Control: no-cache` so browsers always
revalidate — CloudFront still caches it at the edge, and the deploy script
invalidates on every push. Any hashed static assets added later should get a
long `max-age` instead.
