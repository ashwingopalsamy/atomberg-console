// The icon is a real fan: drag it, flick it, and it keeps turning with the momentum, then settles to a slow idle.
// Fast blades leave a short trail. Everything here is decoration; the page reads the same without it.
function init() {
const fan = document.querySelector<HTMLButtonElement>(".fan");
const stage = document.querySelector<HTMLElement>(".stage");

if (fan && stage) {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const IDLE = reduce ? 0 : 45; // degrees per second at rest
  const TAU = 1.8; // seconds for a flick to settle
  const g0 = fan.querySelector<HTMLElement>(".g0")!;
  const g1 = fan.querySelector<HTMLElement>(".g1")!;
  const g2 = fan.querySelector<HTMLElement>(".g2")!;
  let angle = 0;
  let vel = IDLE;
  let last = performance.now();
  let raf = 0;
  let dragging = false;
  let moved = false;
  let pointerAngle = 0;
  let pointerTime = 0;
  let dragVel = 0;
  let startX = 0;
  let startY = 0;

  fan.classList.add("live");

  const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));
  const used = () => stage.classList.add("used");

  const paint = () => {
    const a = angle % 360;
    const speed = Math.abs(vel);
    g0.style.setProperty("--a", `${a}deg`);
    g1.style.setProperty("--a", `${a - vel * 0.02}deg`);
    g2.style.setProperty("--a", `${a - vel * 0.04}deg`);
    g1.style.setProperty("--o", speed > 140 ? String(clamp(speed / 2600, 0, 0.4)) : "0");
    g2.style.setProperty("--o", speed > 140 ? String(clamp(speed / 4200, 0, 0.22)) : "0");
  };

  const frame = (now: number) => {
    if (!fan.isConnected) {
      raf = 0; // the page was swapped out
      return;
    }
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    if (!dragging) {
      vel += (IDLE - vel) * (1 - Math.exp(-dt / TAU));
      angle += vel * dt;
    }
    paint();
    raf = dragging || IDLE !== 0 || Math.abs(vel) > 0.5 ? requestAnimationFrame(frame) : 0;
  };
  const wake = () => {
    if (raf) return;
    last = performance.now();
    raf = requestAnimationFrame(frame);
  };

  const angleAt = (e: PointerEvent) => {
    const r = fan.getBoundingClientRect();
    return (Math.atan2(e.clientY - (r.top + r.height / 2), e.clientX - (r.left + r.width / 2)) * 180) / Math.PI;
  };

  fan.addEventListener("pointerdown", (e) => {
    dragging = true;
    moved = false;
    dragVel = 0;
    startX = e.clientX;
    startY = e.clientY;
    pointerAngle = angleAt(e);
    pointerTime = e.timeStamp;
    fan.setPointerCapture(e.pointerId);
    used();
    wake();
  });
  fan.addEventListener("pointermove", (e) => {
    if (!dragging) return;
    const next = angleAt(e);
    let delta = next - pointerAngle;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    angle += delta;
    const dt = (e.timeStamp - pointerTime) / 1000;
    if (dt > 0) dragVel = 0.7 * dragVel + 0.3 * (delta / dt);
    pointerAngle = next;
    pointerTime = e.timeStamp;
    if (Math.hypot(e.clientX - startX, e.clientY - startY) > 4) moved = true;
    vel = dragVel;
  });
  const release = () => {
    if (!dragging) return;
    dragging = false;
    // a drag keeps its momentum; a plain tap gives the blades a push
    vel = moved ? clamp(dragVel, -2400, 2400) : Math.max(vel, 0) + 900;
    wake();
  };
  fan.addEventListener("pointerup", release);
  fan.addEventListener("pointercancel", release);
  // keyboard: Space or Enter gives the same push
  fan.addEventListener("click", (e) => {
    if (e.detail !== 0) return;
    used();
    vel = Math.max(vel, 0) + 900;
    wake();
  });

  wake();
}

const copy = document.querySelector<HTMLButtonElement>("[data-copy]");
const label = copy?.querySelector("span");
let timer: number | undefined;
copy?.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(copy.dataset.copy ?? "");
  } catch {
    return; // the command is in the docs; nothing else to do
  }
  copy.classList.add("done");
  if (label) label.textContent = "Copied";
  clearTimeout(timer);
  timer = window.setTimeout(() => {
    copy.classList.remove("done");
    if (label) label.textContent = "Copy brew command";
  }, 1600);
});
}

document.addEventListener("astro:page-load", init);
