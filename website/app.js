/* ===========================================================
   Striche – Website interactions
   The phone demo mirrors the app's DrinksView booking flow.
   =========================================================== */

// ---- Real drink presets from the app (DrinkCatalog.presets) ----
const DRINKS = [
  { name: "Pils",         emoji: "🍺", price: "2,50 €", tint: "#E8A317", beer: true },
  { name: "Weizen",       emoji: "🍺", price: "ab 3,20 €", tint: "#D98A00", beer: true },
  { name: "Helles",       emoji: "🍺", price: "2,80 €", tint: "#F0B429", beer: true },
  { name: "Radler",       emoji: "🍻", price: "2,80 €", tint: "#C9D92E", beer: true },
  { name: "Sekt",         emoji: "🥂", price: "3,50 €", tint: "#F6C453", beer: false },
  { name: "Cola",         emoji: "🥤", price: "2,00 €", tint: "#9B3B2E", beer: false },
  { name: "Sprudel",      emoji: "💧", price: "1,50 €", tint: "#2EC4F0", beer: false },
  { name: "Kaffee",       emoji: "☕️", price: "1,50 €", tint: "#6F4E37", beer: false },
];

// numeric prices for the running balance (base price, ignores size modifiers)
const PRICE = { "Pils":2.5, "Weizen":3.2, "Helles":2.8, "Radler":2.8, "Sekt":3.5, "Cola":2.0, "Sprudel":1.5, "Kaffee":1.5 };

// ---- Build hex with alpha helper ----
function hexA(hex, alpha) {
  const h = hex.replace("#", "");
  const r = parseInt(h.substring(0, 2), 16);
  const g = parseInt(h.substring(2, 4), 16);
  const b = parseInt(h.substring(4, 6), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

const grid = document.getElementById("drinkGrid");
const counts = {};
let totalOwed = 0;
let totalBooked = 0;

// ---- Render drink tiles ----
DRINKS.forEach((d) => {
  counts[d.name] = 0;
  const tile = document.createElement("button");
  tile.type = "button";
  tile.className = "drink";
  tile.setAttribute("aria-label", `${d.name} buchen`);
  tile.style.setProperty("--tint-35", hexA(d.tint, 0.35));
  tile.style.setProperty("--tint-12", hexA(d.tint, 0.12));
  tile.style.setProperty("--tint-85", hexA(d.tint, 0.85));
  tile.style.setProperty("--tint-55", hexA(d.tint, 0.55));
  tile.style.setProperty("--tint-40", hexA(d.tint, 0.40));
  tile.innerHTML = `
    <span class="liquid"></span>
    <span class="count">0</span>
    <span class="emoji">${d.emoji}</span>
    <span class="dname">${d.name}</span>
    <span class="dprice">${d.price}</span>
  `;
  tile.addEventListener("click", () => book(d, tile));
  grid.appendChild(tile);
});

const balanceChip = document.getElementById("balanceChip");
const balanceLabel = document.getElementById("balanceLabel");
const balanceValue = document.getElementById("balanceValue");
const todayPill = document.getElementById("todayPill");
const todayCountEl = document.getElementById("todayCount");

// ---- Booking action ----
function book(d, tile) {
  counts[d.name] += 1;
  totalBooked += 1;
  totalOwed += PRICE[d.name] || 0;

  // count badge
  const badge = tile.querySelector(".count");
  badge.textContent = counts[d.name];
  badge.classList.add("show");

  // liquid fill rises with count (capped)
  const liquid = tile.querySelector(".liquid");
  const fill = Math.min(60, counts[d.name] * 9 + 18);
  liquid.style.height = fill + "%";

  // jiggle the emoji
  tile.classList.add("jiggle");
  setTimeout(() => tile.classList.remove("jiggle"), 200);

  // +1 floater
  const f = document.createElement("span");
  f.className = "floater";
  f.textContent = "+1";
  f.style.marginLeft = (Math.random() * 28 - 14) + "px";
  tile.appendChild(f);
  setTimeout(() => f.remove(), 850);

  // confetti for non-beer, foam splash handled by liquid for beer
  if (!d.beer) burstConfetti(tile, d.tint);

  // balance chip (always "Offen" / gold in this demo since we book)
  balanceLabel.textContent = "Offen";
  balanceValue.textContent = totalOwed.toFixed(2).replace(".", ",") + " €";
  balanceChip.classList.remove("is-credit");
  balanceChip.classList.add("pulse");
  setTimeout(() => balanceChip.classList.remove("pulse"), 260);

  // today pill
  todayPill.hidden = false;
  todayCountEl.textContent = totalBooked;

  // subtle haptic on supported devices
  if (navigator.vibrate) navigator.vibrate(d.beer ? 18 : 8);
}

// ---- Confetti burst ----
function burstConfetti(tile, tint) {
  const colors = [tint, "#F0B429", "#2EE6A6", "#FF5C7A", "#FFF4D6"];
  for (let i = 0; i < 10; i++) {
    const c = document.createElement("span");
    c.className = "confetti";
    c.style.background = colors[i % colors.length];
    c.style.setProperty("--cx", (Math.random() * 120 - 60) + "px");
    c.style.setProperty("--cy", (Math.random() * -90 - 20) + "px");
    c.style.setProperty("--cr", (Math.random() * 540 - 270) + "deg");
    tile.appendChild(c);
    setTimeout(() => c.remove(), 900);
  }
}

// ---- Category chips (visual only) ----
document.querySelectorAll(".chips .chip").forEach((chip) => {
  chip.addEventListener("click", () => {
    document.querySelectorAll(".chips .chip").forEach((c) => c.classList.remove("chip-active"));
    chip.classList.add("chip-active");
  });
});

// ---- Scroll reveal ----
const io = new IntersectionObserver(
  (entries) => {
    entries.forEach((e) => {
      if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
    });
  },
  { threshold: 0.12 }
);
document.querySelectorAll(".reveal").forEach((el) => io.observe(el));

// ---- Sticky nav style on scroll ----
const nav = document.getElementById("nav");
const onScroll = () => nav.classList.toggle("scrolled", window.scrollY > 20);
onScroll();
window.addEventListener("scroll", onScroll, { passive: true });

// ---- Footer year ----
document.getElementById("year").textContent = new Date().getFullYear();
