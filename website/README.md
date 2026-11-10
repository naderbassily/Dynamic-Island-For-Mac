# dynamicislandmac.com

This folder is the website. In Vercel, import the **Dynamic-Island-For-Mac** repository and set **Root Directory** to `website`.

Landing page for **Dynamic Island for Mac**: a single static page with animations, a download button and a contact form. It's hosted on **Vercel**.

```
index.html        the page
styles.css        design and animations
script.js         island animation, typing terminal, download link, contact form
api/contact.js    serverless function that emails you contact-form messages (via Resend)
assets/           icon, favicon, social preview image
vercel.json       headers and redirects
robots.txt, sitemap.xml
```

---

## 1. Set your download link (1 minute)

`script.js` already points at the repository:

```js
const GITHUB_REPO = "naderbassily/Dynamic-Island-For-Mac";
```

The Download buttons then always point to
`https://github.com/<repo>/releases/latest/download/DynamicIsland.dmg`, the newest release. The version number on the page updates automatically from GitHub.

**Prefer to host the .dmg yourself?** Create a `downloads` folder, put `DynamicIsland.dmg` in it, and in `script.js` set:
```js
const DOWNLOAD_URL = "/downloads/DynamicIsland.dmg";
```

## 2. Put it on Vercel (5 minutes)

**Option A: GitHub (recommended, updates automatically)**
1. Go to [vercel.com](https://vercel.com) ▸ **Add New… ▸ Project** ▸ import **naderbassily/Dynamic-Island-For-Mac**.
2. **Root Directory:** `website`. Framework preset: **Other**. Leave the build command empty. Click **Deploy**.

Every time you push a change, Vercel redeploys.

**Option B: drag and drop.** On vercel.com ▸ **Add New… ▸ Project**, drag this folder onto the page.

## 3. Connect your domain

1. In Vercel ▸ your project ▸ **Settings ▸ Domains**, add `dynamicislandmac.com` and also `www.dynamicislandmac.com`.
2. Vercel shows the DNS records to add. At the company you bought the domain from, add:
   - **A** record, host `@` → `76.76.21.21`
   - **CNAME** record, host `www` → `cname.vercel-dns.com`

   (Use whatever Vercel shows if it differs.) Alternatively, switch the domain's nameservers to Vercel's.
3. Wait from a few minutes up to a few hours. Vercel adds HTTPS automatically.

## 4. Turn on the contact form (5 minutes)

The form sends messages to your email through [Resend](https://resend.com), which is free for up to 3,000 emails a month.

1. Sign up at resend.com and create an **API key**.
2. In Vercel ▸ your project ▸ **Settings ▸ Environment Variables**, add:

   | Name | Value |
   |---|---|
   | `RESEND_API_KEY` | the key from Resend (starts with `re_`) |
   | `CONTACT_TO` | the email that should receive messages |
   | `CONTACT_FROM` | *(optional, see below)* `Dynamic Island <support@dynamicislandmac.com>` |

3. **Redeploy** (Deployments ▸ ⋯ ▸ Redeploy) so the new variables take effect.
4. Test the form on your site.

**About `CONTACT_FROM`:** until you verify your domain, Resend sends from `onboarding@resend.dev` and only delivers to the email you signed up to Resend with. To send from `support@dynamicislandmac.com` to any inbox, go to Resend ▸ **Domains ▸ Add Domain**, add the DNS records it shows (in Vercel ▸ Domains ▸ DNS, or at your registrar), then set `CONTACT_FROM`.

When you get a message, just click **Reply**. It goes straight to the person who wrote.

Spam protection: a hidden honeypot field, plus a limit of 5 messages per 10 minutes per visitor.

## Editing the page

- **Text:** edit `index.html`.
- **Colours:** edit the variables at the top of `styles.css` (`--accent`, `--accent2`…).
- **Island animation:** the `states` list in `script.js` sets the order and timing. Each state's look is in `index.html` (`.st-…`) and `styles.css` (`.island[data-state="…"]`).
- **Social preview image:** `assets/og.jpg` (1200 × 630).

Preview locally by opening `index.html`, or run `npx vercel dev` to test the contact form too.
