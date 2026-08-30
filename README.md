# oracy

Public site for Oracy (home, privacy, terms) — used for Google OAuth consent links and store listings.

| Page | Path |
|------|------|
| Home | `/` |
| Privacy | `/privacy` |
| Terms | `/terms` |
| Admin invites | `/admin/invites` |

Deploy this folder as the site root (Vercel).

## Invite email (Resend)

Invites stay **Not Sent** until Resend accepts the message. Set these on the Vercel project (**Settings → Environment Variables**), for Production (and Preview if you test there), then **redeploy**:

| Variable | Example |
|----------|---------|
| `EMAIL_PROVIDER` | `resend` (also set in `vercel.json`) |
| `RESEND_API_KEY` | `re_...` from [resend.com](https://resend.com) |
| `EMAIL_FROM` | `Oracy <hello@your-verified-domain>` |
| `INVITE_CTA_URL` | `https://oracy.heyayush.in` (optional) |

`EMAIL_FROM` must use a domain verified in Resend. After the vars are live, `/admin/services` should show Invite email as ready.
