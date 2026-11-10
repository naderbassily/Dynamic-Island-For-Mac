// Vercel serverless function: POST /api/contact
// Sends contact-form messages to your inbox using Resend (https://resend.com, free tier).
//
// Set these in Vercel ▸ Project ▸ Settings ▸ Environment Variables:
//   RESEND_API_KEY  – from resend.com ▸ API Keys
//   CONTACT_TO      – where messages go, e.g. you@gmail.com
//   CONTACT_FROM    – optional, e.g. "Dynamic Island <support@dynamicislandmac.com>"
//                     (needs your domain verified in Resend; until then it uses onboarding@resend.dev,
//                      which can only deliver to the email you signed up to Resend with)

const recent = new Map(); // basic per-instance rate limit: ip -> [timestamps]

const clean = (v, max) => String(v ?? "").replace(/\r/g, "").trim().slice(0, max);
const esc = (s) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ ok: false, error: "Method not allowed." });
  }

  let body = req.body;
  if (typeof body === "string") { try { body = JSON.parse(body); } catch { body = {}; } }
  body = body || {};

  // Honeypot: real people never fill this hidden field.
  if (body.website) return res.status(200).json({ ok: true });

  const name = clean(body.name, 100);
  const email = clean(body.email, 200);
  const topic = clean(body.topic, 40) || "Other";
  const system = clean(body.system, 120);
  const message = clean(body.message, 5000);

  if (!name || !message || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(400).json({ ok: false, error: "Please fill in your name, a valid email and a message." });
  }

  // Rate limit: 5 messages per 10 minutes per IP (per server instance).
  const ip = String(req.headers["x-forwarded-for"] || "").split(",")[0].trim() || "unknown";
  const now = Date.now();
  const hits = (recent.get(ip) || []).filter((t) => now - t < 10 * 60 * 1000);
  if (hits.length >= 5) return res.status(429).json({ ok: false, error: "Too many messages — please try again in a few minutes." });
  hits.push(now); recent.set(ip, hits);

  const key = process.env.RESEND_API_KEY;
  const to = process.env.CONTACT_TO;
  if (!key || !to) {
    console.error("Contact form not configured: set RESEND_API_KEY and CONTACT_TO");
    return res.status(500).json({ ok: false, error: "The contact form isn’t set up yet." });
  }
  const from = process.env.CONTACT_FROM || "Dynamic Island Website <onboarding@resend.dev>";

  const html = `
    <div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;font-size:15px;line-height:1.5;color:#111">
      <h2 style="margin:0 0 12px">New message from dynamicislandmac.com</h2>
      <table cellpadding="6" style="border-collapse:collapse">
        <tr><td style="color:#666">Name</td><td><b>${esc(name)}</b></td></tr>
        <tr><td style="color:#666">Email</td><td><a href="mailto:${esc(email)}">${esc(email)}</a></td></tr>
        <tr><td style="color:#666">Topic</td><td>${esc(topic)}</td></tr>
        <tr><td style="color:#666">Mac / macOS</td><td>${esc(system || "—")}</td></tr>
      </table>
      <div style="margin-top:16px;padding:14px 16px;background:#f4f4f7;border-radius:10px;white-space:pre-wrap">${esc(message)}</div>
      <p style="color:#999;font-size:12px;margin-top:16px">Reply to this email to answer ${esc(name)} directly.</p>
    </div>`;

  try {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from,
        to: to.split(",").map((s) => s.trim()).filter(Boolean),
        reply_to: email,
        subject: `[Dynamic Island] ${topic}: ${name}`,
        html,
        text: `Name: ${name}\nEmail: ${email}\nTopic: ${topic}\nMac/macOS: ${system || "-"}\n\n${message}`,
      }),
    });
    if (!r.ok) {
      console.error("Resend error", r.status, await r.text());
      return res.status(502).json({ ok: false, error: "Couldn’t send right now." });
    }
    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error(err);
    return res.status(502).json({ ok: false, error: "Couldn’t send right now." });
  }
}
