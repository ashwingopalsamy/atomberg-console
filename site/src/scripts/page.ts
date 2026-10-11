// The page is calm until you move it. The fans turn with the scroll and with a tap; the island follows the
// section in view. Everything here is decoration: the document reads and works the same without it.
const root = document.documentElement;
let taps = 0;
let scrollTurn = 0;
let queued = false;

const paint = () => {
  queued = false;
  root.style.setProperty("--rot", `${(taps * 360 + scrollTurn).toFixed(1)}deg`);
};
const queue = () => {
  if (queued) return;
  queued = true;
  requestAnimationFrame(paint);
};

document.querySelector(".fan")?.addEventListener("click", () => {
  taps += 1;
  queue();
});

const island = document.querySelector<HTMLElement>(".island");
const hl = island?.querySelector<HTMLElement>(".hl");
const links = island ? [...island.querySelectorAll<HTMLAnchorElement>("a[data-s]")] : [];
const sections = links.map((a) => document.getElementById(a.dataset.s ?? ""));
let current: HTMLAnchorElement | undefined;
let hover: HTMLAnchorElement | undefined;

const place = () => {
  if (!hl) return;
  const a = hover ?? current;
  links.forEach((l) => {
    l.classList.toggle("on", l === a);
    if (l === current) l.setAttribute("aria-current", "true");
    else l.removeAttribute("aria-current");
  });
  if (!a) {
    hl.style.opacity = "0";
    return;
  }
  hl.style.opacity = "1";
  hl.style.width = `${a.offsetWidth}px`;
  hl.style.height = `${a.offsetHeight}px`;
  hl.style.transform = `translate(${a.offsetLeft}px, ${a.offsetTop}px)`;
};

const spy = () => {
  // the last section whose top has crossed 40% of the viewport
  const line = innerHeight * 0.4;
  let found: HTMLAnchorElement | undefined;
  sections.forEach((s, i) => {
    if (s && s.getBoundingClientRect().top <= line) found = links[i];
  });
  if (found !== current) {
    current = found;
    place();
  }
};

addEventListener(
  "scroll",
  () => {
    scrollTurn = scrollY * 0.35;
    queue();
    spy();
  },
  { passive: true },
);
links.forEach((a) => {
  a.addEventListener("pointerenter", () => {
    hover = a;
    place();
  });
  a.addEventListener("focus", () => {
    hover = a;
    place();
  });
  a.addEventListener("pointerleave", () => {
    hover = undefined;
    place();
  });
  a.addEventListener("blur", () => {
    hover = undefined;
    place();
  });
});
addEventListener("resize", place);
document.fonts?.ready.then(place);
// open the FAQ entry a link points at
const target = location.hash ? document.getElementById(location.hash.slice(1)) : null;
if (target instanceof HTMLDetailsElement) target.open = true;
spy();
paint();
