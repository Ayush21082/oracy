# Oracy public site (OAuth / store links)

Static pages for Google OAuth consent screen (and App Store / Play where needed):

| Field | URL (after you host) |
|-------|----------------------|
| Application home page | `https://oracy.app/` |
| Privacy policy | `https://oracy.app/privacy` |
| Terms of service | `https://oracy.app/terms` |

## Host (pick one)

**Netlify / Vercel / Cloudflare Pages**
1. Deploy the `web/` folder as the site root.
2. Add redirects so clean paths work:

```
/privacy  /privacy.html  200
/terms    /terms.html    200
```

**GitHub Pages**
1. Push `web/` to a `gh-pages` branch or `/docs`.
2. Same redirects via `404.html` or host config if needed.

**Domain you already own (`oracy.app`)**
Point DNS to the host, then paste the three HTTPS URLs into Google Cloud → APIs & Services → OAuth consent screen.

Until the domain is live, you can temporarily use the host’s default URL (e.g. `https://oracy-xxx.netlify.app/...`) in the consent screen.
