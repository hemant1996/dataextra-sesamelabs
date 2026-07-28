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

### Cache policy

`index.html` is uploaded with `Cache-Control: no-cache` so browsers always
revalidate — CloudFront still caches it at the edge, and the deploy script
invalidates on every push. Any hashed static assets added later should get a
long `max-age` instead.
