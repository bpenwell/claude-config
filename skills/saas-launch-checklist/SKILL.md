---
name: saas-launch-checklist
description: Interactive SaaS website launch checklist. Walks through every section, marks items done, and provides implementation guidance. Use when launching or auditing any SaaS product.
argument-hint: "[optional: section name to jump to — e.g. 'productionalization', 'security', 'seo']"
allowed-tools: [Bash, Read, WebFetch]
---

Walk the user through the SaaS launch checklist interactively. If an `argument-hint` section name was passed, jump directly to that section. Otherwise start from the top.

For each item:
- Ask if it's done, in progress, or not started
- If not done and the user wants help, provide step-by-step guidance or implement it
- Mark ✅ done, 🔄 in progress, ⬜ not started, ⏭️ skipped

At the end of each section, summarize what's done vs. outstanding before moving to the next.

---

## Section 1 — Domain & DNS

- [ ] Custom domain registered and pointed to hosting
- [ ] www → apex redirect configured (or vice versa, consistently)
- [ ] SSL/TLS certificate issued and auto-renewing (ACM, Let's Encrypt, etc.)
- [ ] HTTPS enforced — HTTP redirects to HTTPS

## Section 2 — Hosting & Infrastructure

- [ ] Production environment separate from staging/beta
- [ ] CDN in front of all static assets (CloudFront, Cloudflare, etc.)
- [ ] Static assets served with long-lived immutable cache headers (`max-age=31536000, immutable`)
- [ ] HTML/API responses served with `no-cache` or short TTLs
- [ ] Default root object set on CDN (e.g. `index.html`)
- [ ] 404/error pages return correct HTTP status codes (not 200)

## Section 3 — CI/CD Pipeline

- [ ] Automated deployments wired to `main` branch pushes
- [ ] CI/CD billing/limits checked — pipeline will not silently fail
- [ ] Billing alerts configured on CI provider (GitHub, CircleCI, etc.) so payment failures surface immediately
- [ ] Deployment smoke test runs after each deploy (hits the live URL, checks for 200)
- [ ] Rollback plan documented — know how to revert a bad deploy in under 5 minutes

## Section 4 — Productionalization (Monitoring & Alerting)

- [ ] **Uptime monitor** — set up UptimeRobot (free) or CloudWatch Synthetics to ping the root URL every 5 minutes
  - UptimeRobot free tier: uptimerobot.com → Add Monitor → HTTPS → your domain
  - Alert on any non-2xx response
- [ ] **Push notifications to phone** — install UptimeRobot mobile app, enable push alerts for the monitor
- [ ] **CI/CD billing alert** — in GitHub Settings → Billing → set a spending limit or enable email alerts so a payment failure surfaces within 24 hours (not 38 days)
- [ ] **Beta/staging monitor** — add a second UptimeRobot monitor for the staging URL
- [ ] Lambda/backend error alarms — CloudWatch alarm on `Errors` metric for each Lambda, SNS email on breach
- [ ] On-call contact documented — who gets paged, what's their phone/email

## Section 5 — Security

- [ ] Authentication in place (Auth0, Cognito, Clerk, etc.)
- [ ] All secrets in environment variables or a secrets manager — none hardcoded in source
- [ ] Security response headers set: `Strict-Transport-Security`, `X-Frame-Options`, `X-Content-Type-Options`
- [ ] CORS locked down — not `*` in production
- [ ] Rate limiting on API endpoints (WAF, API Gateway throttling, or middleware)
- [ ] Dependency audit clean — `npm audit` / `pip-audit` passes with no high/critical issues

## Section 6 — SEO & Discoverability

- [ ] `robots.txt` present and correct — auth-gated routes marked `noindex`
- [ ] `sitemap.xml` generated and submitted to Google Search Console
- [ ] Canonical URLs set on all pages
- [ ] Open Graph / Twitter card meta tags on key pages
- [ ] Page titles and meta descriptions unique per page
- [ ] Core Web Vitals passing — LCP < 2.5s, CLS < 0.1, INP < 200ms (check PageSpeed Insights)
- [ ] Google Search Console verified and showing no crawl errors

## Section 7 — Analytics & Error Tracking

- [ ] Analytics wired up (PostHog, Plausible, GA4, etc.)
- [ ] Key conversion events tracked (signup, upgrade, first meaningful action)
- [ ] Frontend error tracking in place (Sentry, PostHog exceptions, etc.)
- [ ] Backend errors logged to CloudWatch or equivalent with alerting on spikes

## Section 8 — Payments & Business

- [ ] Stripe (or payment provider) in live mode — not test keys
- [ ] Webhook endpoint verified and handling all relevant events (payment failure, subscription cancel, etc.)
- [ ] Failed payment handling implemented — grace period, dunning emails, access revocation
- [ ] Pricing page live with accurate feature comparison
- [ ] Subscription tiers gating features correctly in both frontend and backend

## Section 9 — Legal & Compliance

- [ ] Privacy policy live and linked in footer
- [ ] Terms of service live and linked in footer
- [ ] Cookie consent banner if serving EU users (GDPR)
- [ ] Data retention policy defined — know what you store and for how long
- [ ] GDPR/CCPA delete-my-data flow implemented if applicable

## Section 10 — Launch Readiness

- [ ] Tested on mobile (iOS Safari, Android Chrome)
- [ ] Tested in dark mode and light mode
- [ ] Tested with a real payment (charge + refund yourself $1)
- [ ] Tested the full signup → onboarding → first value → upgrade flow end-to-end
- [ ] Feedback mechanism in place (feedback button, intercom, email)
- [ ] "In early access / beta" messaging if feature is not fully stable
- [ ] Support email or contact page live
