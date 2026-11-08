---
title: Deployment
sidebar_position: 6
---

# Deployment

Optimizr has two public surfaces, both hosted on **GitHub Pages** from the same repository and the same artifact:

| Surface | URL | Source |
| --- | --- | --- |
| Documentation | `https://403access.github.io/optimizr/docs/` | `docs-site/` (Docusaurus) |
| Marketing site | `https://403access.github.io/optimizr/` | `marketing/` (static) |

## How the artifact is assembled

The Pages workflow builds Docusaurus, then combines the two sites into a single directory:

```
site/
  index.html            ← marketing/index.html
  assets/…              ← marketing assets
  docs/
    index.html          ← Docusaurus build output
    assets/…
    roadmap/index.html
    product/…
    tech/…
  .nojekyll
```

This gives one deploy, one URL, and relative links that work in production. Docusaurus is configured with:

```ts
url: 'https://403access.github.io',
baseUrl: '/optimizr/docs/',
```

The marketing site links to `./docs/`, which resolves correctly at the artifact root.

## Workflow

`.github/workflows/pages.yml` runs on pushes to `main` (and manually via `workflow_dispatch`):

```yaml
permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

steps:
  - checkout
  - setup Node 22
  - npm ci (docs-site, lockfile committed)
  - npm run build (docs-site)
  - assemble marketing + docs into site/
  - configure-pages
  - upload-pages-artifact (site/)
  - deploy-pages
```

Key details:

- **No secret is required.** GitHub's OIDC token and the `GITHUB_TOKEN` handle deployment.
- **`concurrency` prevents overlapping deploys** and cancels superseded runs.
- **`upload-pages-artifact`** packages the assembled `site/` directory; the deploy job receives it via `actions/deploy-pages`.
- **`.nojekyll` is created** so files/folders beginning with `_` are served (Docusaurus emits `_docusaurus` assets).

## Enabling Pages

The repository must be configured once:

1. Push the repository to GitHub.
2. Open **Settings → Pages**.
3. Set **Build and deployment → Source** to **GitHub Actions**.
4. Push to `main` or run the workflow manually.

The API equivalent used during initial setup:

```bash
curl -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/403access/optimizr/pages \
  -d '{"build_type":"workflow","source":{"branch":"main","path":"/"}}'
```

Then verify:

```bash
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/403access/optimizr/pages
```

## Local reproduction

```bash
# 1. Build docs
cd docs-site
npm ci --no-audit --no-fund
npm run build
cd ..

# 2. Assemble exactly like CI
rm -rf site
mkdir -p site
cp -R marketing/. site/
cp -R docs-site/build site/docs
touch site/.nojekyll

# 3. Serve at the production path
rm -rf .preview && mkdir -p .preview/optimizr
cp -R site/. .preview/optimizr/
python3 -m http.server 4173 --directory .preview
```

Check both:

- `http://localhost:4173/optimizr/`
- `http://localhost:4173/optimizr/docs/`

If internal docs links 404 locally, verify that you are serving the assembled artifact under `/optimizr/` and not `docs-site/build/` directly; the base path is `/optimizr/docs/`.

## Releases

The app is built and packaged by `release.yml` when a tag matching `v*` is pushed:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow:

1. Checks out the tag on a macOS runner.
2. Runs `swift test`.
3. Runs `scripts/build-app.sh`.
4. Zips `dist/Optimizr.app`.
5. Creates a GitHub Release with the zip attached.

The marketing download button points at `releases/latest`. Until a release exists, users can build from source as documented. The bundle is ad-hoc signed, not notarized; the release notes say so.

## Rollback

- **Pages:** re-run the workflow for an earlier commit (`workflow_dispatch` on a branch, or revert the offending commit and push).
- **Release:** delete the release/tag or publish a corrected patch tag. Never move a published tag; publish a new one.

## Custom domain

To use a custom domain:

1. Add the domain in GitHub Pages settings.
2. Create a `CNAME` file in the assembled artifact.
3. Update `url`/`baseUrl` in `docusaurus.config.ts`, the marketing links, and the docs navigation.
4. Update this page.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| 404 on `/optimizr/docs/` | Pages source not set to Actions, or deploy failed | Check the Actions run and Pages settings |
| CSS/assets missing | `baseUrl` mismatch | Keep `baseUrl: '/optimizr/docs/'` |
| 404 on marketing `/` | Docs copied over root or `index.html` missing | Verify assembly order: marketing first, docs into `site/docs` |
| Deploy job skipped | Permissions or environment missing | Ensure `pages: write`, `id-token: write`, and the `github-pages` environment |
| Stale content | CDN/browser cache or superseded run | Check the latest run; hard refresh |
| Docusaurus build fails on links | `onBrokenLinks: 'throw'` | Fix links locally with `npm run build` |

## Security notes

- The workflow has read access to source and write access only to Pages.
- No personal tokens are stored in the repository; initial provisioning used the maintainer's token outside the repo.
- The app itself is not downloaded or executed by CI beyond the smoke test, which runs the code from the same commit.

## Deployment checklist

- [ ] `swift test` passes locally.
- [ ] `swift run optimizr-scan` produces a valid report.
- [ ] `./scripts/build-app.sh` succeeds.
- [ ] `cd docs-site && npm run build` succeeds with no broken links.
- [ ] Marketing links point to existing routes.
- [ ] Roadmap and changelog updated in the same commit.
- [ ] Push to `main`; verify the workflow and both public URLs.
