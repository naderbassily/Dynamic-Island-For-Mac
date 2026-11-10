/* ============================================================
   Dynamic Island for Mac — landing page
   ------------------------------------------------------------
   EDIT THESE TWO LINES after you publish on GitHub:
   ============================================================ */
const GITHUB_REPO = "naderbassily/Dynamic-Island-For-Mac";
const FALLBACK_VERSION = "2.1.0";

/* Download link: GitHub always serves the newest release's file at this address.
   If you'd rather host the .dmg on this site, put it in /downloads/ and use:
   const DOWNLOAD_URL = "/downloads/DynamicIsland.dmg";                        */
const DOWNLOAD_URL = `https://github.com/${GITHUB_REPO}/releases/latest/download/DynamicIsland.dmg`;
const REPO_URL = `https://github.com/${GITHUB_REPO}`;

const prefersReduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/* ---------- Links & version ---------- */
/* ---------- Analytics (Google Tag Manager dataLayer) ----------
   Events you can use as GTM "Custom Event" triggers:
     file_download   – a Download button was clicked
     generate_lead   – the contact form was sent successfully
     outbound_click  – GitHub / release-notes links                       */
window.dataLayer = window.dataLayer || [];
let currentVersion = FALLBACK_VERSION;
function track(event, params) {
  try { window.dataLayer.push({ event, ...params }); } catch (_) {}
}

document.querySelectorAll("[data-download]").forEach((a, i) => {
  a.href = DOWNLOAD_URL;
  const where = a.closest("section")?.id || a.closest("section")?.className || "page";
  a.addEventListener("click", () => {
    track("file_download", {
      file_name: "DynamicIsland.dmg",
      file_extension: "dmg",
      link_url: DOWNLOAD_URL,
      link_text: a.textContent.trim().replace(/\s+/g, " "),
      download_location: where === "hero" ? "hero" : where,
      app_version: currentVersion,
    });
    // Show the first-launch steps right after the download starts.
    setTimeout(() => document.getElementById("download")?.scrollIntoView({ behavior: "smooth" }), 400);
  });
});
document.querySelectorAll("[data-source], [data-release-notes]").forEach((a) =>
  a.addEventListener("click", () => track("outbound_click", { link_url: a.href, link_text: a.textContent.trim() })));
document.querySelectorAll("[data-source]").forEach((a) => (a.href = REPO_URL));
document.querySelectorAll("[data-release-notes]").forEach((a) => (a.href = `${REPO_URL}/releases/latest`));
document.getElementById("year").textContent = new Date().getFullYear();

function setVersion(v) {
  currentVersion = v;
  document.querySelectorAll("[data-version]").forEach((el) => (el.textContent = `v${v}`));
}
setVersion(FALLBACK_VERSION);
if (!GITHUB_REPO.startsWith("YOUR-")) {
  fetch(`https://api.github.com/repos/${GITHUB_REPO}/releases/latest`)
    .then((r) => (r.ok ? r.json() : null))
    .then((d) => d?.tag_name && setVersion(d.tag_name.replace(/^v/, "")))
    .catch(() => {});
}

/* ---------- Nav shadow ---------- */
const nav = document.querySelector(".nav");
addEventListener("scroll", () => nav.classList.toggle("scrolled", scrollY > 20), { passive: true });

/* ---------- Reveal on scroll ---------- */
const io = new IntersectionObserver(
  (entries) => entries.forEach((e) => {
    if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
  }),
  { threshold: 0.12, rootMargin: "0px 0px -40px 0px" }
);
document.querySelectorAll(".reveal").forEach((el, i) => {
  el.style.transitionDelay = `${Math.min((i % 4) * 70, 210)}ms`;
  io.observe(el);
});

/* ---------- Card spotlight follows the cursor ---------- */
document.querySelectorAll(".card").forEach((card) => {
  card.addEventListener("pointermove", (e) => {
    const r = card.getBoundingClientRect();
    card.style.setProperty("--mx", `${e.clientX - r.left}px`);
    card.style.setProperty("--my", `${e.clientY - r.top}px`);
  });
});

/* ---------- The animated island ---------- */
const island = document.getElementById("island");
const dots = document.getElementById("stateDots");
const states = [
  { id: "idle", ms: 2200 },
  { id: "music", ms: 3200 },
  { id: "charge", ms: 3400 },
  { id: "timer", ms: 2800 },
  { id: "meet", ms: 3600 },
  { id: "pods", ms: 2600 },
  { id: "msg", ms: 3400 },
];
let idx = 0, timer = null, paused = false;

states.forEach((s, i) => {
  const b = document.createElement("button");
  b.setAttribute("aria-label", `Show ${s.id}`);
  b.addEventListener("click", () => { go(i); });
  dots.appendChild(b);
});

function go(i) {
  idx = (i + states.length) % states.length;
  island.dataset.state = states[idx].id;
  [...dots.children].forEach((d, j) => d.classList.toggle("on", j === idx));
  // restart the charging bar animation each time
  if (states[idx].id === "charge") {
    const bar = island.querySelector(".bar span");
    bar.style.animation = "none"; void bar.offsetWidth; bar.style.animation = "";
  }
  clearTimeout(timer);
  if (!paused && !prefersReduced) timer = setTimeout(() => go(idx + 1), states[idx].ms);
}
island.addEventListener("mouseenter", () => { paused = true; clearTimeout(timer); });
island.addEventListener("mouseleave", () => { paused = false; go(idx + 1); });
island.addEventListener("click", () => go(idx + 1));
go(0);

/* Focus timer ticking inside the pill */
let secs = 24 * 60 + 59;
const tm = document.getElementById("tm");
setInterval(() => {
  secs = secs <= 0 ? 25 * 60 : secs - 1;
  tm.textContent = `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, "0")}`;
}, 1000);

/* Live clock in the fake menu bar */
function clock() {
  const d = new Date();
  const t = d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  document.querySelector(".t-clock").textContent = t;
  document.querySelector(".mb-clock").textContent =
    d.toLocaleDateString([], { weekday: "short" }) + " " + t;
}
clock(); setInterval(clock, 15000);

/* ---------- Typing terminal ---------- */
const lines = [
  ["c", "# Ping yourself when a long job finishes"],
  ["p", "$ "], ["", "make release && island notify \"Build finished\" \"All tests passed\" hammer.fill\n\n"],
  ["c", "# Start a focus session"],
  ["p", "$ "], ["", "island timer pomodoro\n\n"],
  ["c", "# From Home Assistant, cron or any script"],
  ["p", "$ "], ["", "curl \"http://127.0.0.1:7787/notify?title=Doorbell&icon=bell.fill\"\n\n"],
  ["c", "# Or from Apple Shortcuts / Raycast"],
  ["p", "$ "], ["s", "open -g \"dynamicisland://timer?minutes=10\""],
];
const pre = document.getElementById("typed");
let typedStarted = false;
function typeAll() {
  if (typedStarted) return; typedStarted = true;
  if (prefersReduced) { pre.innerHTML = lines.map(([c, t]) => span(c, t) + (c === "c" ? "\n" : "")).join(""); return; }
  let li = 0, ci = 0, html = "";
  const cursor = '<span class="cursor"></span>';
  (function step() {
    if (li >= lines.length) { pre.innerHTML = html + cursor; return; }
    const [cls, text] = lines[li];
    const full = cls === "c" ? text + "\n" : text;
    ci += cls === "p" ? full.length : 2;
    const part = full.slice(0, ci);
    pre.innerHTML = html + span(cls, part) + cursor;
    if (ci >= full.length) { html += span(cls, full); li++; ci = 0; setTimeout(step, cls === "c" ? 120 : 260); }
    else setTimeout(step, 18);
  })();
}
function span(cls, t) {
  const esc = t.replace(/&/g, "&amp;").replace(/</g, "&lt;");
  return cls ? `<span class="${cls}">${esc}</span>` : esc;
}
new IntersectionObserver((e, obs) => {
  if (e[0].isIntersecting) { typeAll(); obs.disconnect(); }
}, { threshold: 0.3 }).observe(pre);

/* ---------- Contact form ---------- */
const form = document.getElementById("contactForm");
const statusEl = form.querySelector(".form-status");
form.addEventListener("submit", async (e) => {
  e.preventDefault();
  statusEl.className = "form-status"; statusEl.textContent = "";
  const data = Object.fromEntries(new FormData(form).entries());

  // Simple validation
  let bad = false;
  form.querySelectorAll("[required]").forEach((el) => {
    const ok = el.value.trim() && (el.type !== "email" || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(el.value.trim()));
    el.classList.toggle("invalid", !ok); if (!ok) bad = true;
  });
  if (bad) { statusEl.classList.add("err"); statusEl.textContent = "Please fill in your name, a valid email and a message."; return; }

  form.classList.add("sending");
  form.querySelector("button").disabled = true;
  try {
    const res = await fetch("/api/contact", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...data, page: location.href }),
    });
    const out = await res.json().catch(() => ({}));
    if (!res.ok || !out.ok) throw new Error(out.error || "Something went wrong.");
    track("generate_lead", { form_name: "contact", form_topic: data.topic || "Other" });
    form.reset();
    form.classList.add("done");
    statusEl.classList.add("ok");
    statusEl.textContent = "Thanks! Your message is on its way — I’ll reply by email.";
  } catch (err) {
    statusEl.classList.add("err");
    statusEl.textContent = `${err.message} You can also open an issue on GitHub.`;
  } finally {
    form.classList.remove("sending");
    form.querySelector("button").disabled = false;
    setTimeout(() => form.classList.remove("done"), 700);
  }
});
form.querySelectorAll("input, textarea").forEach((el) =>
  el.addEventListener("input", () => el.classList.remove("invalid")));
