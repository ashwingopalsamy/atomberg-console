// The bar persists across pages, so the underline can travel from the old page to the new one.
// It rests on the current page and follows the pointer or focus.
const nav = document.querySelector<HTMLElement>(".nav");
const pill = nav?.querySelector<HTMLElement>(".pill");

if (nav && pill) {
  const links = [...nav.querySelectorAll<HTMLAnchorElement>("a")];
  let current: HTMLAnchorElement | undefined;

  const place = (a?: HTMLAnchorElement) => {
    if (!a) {
      pill.style.opacity = "0";
      return;
    }
    pill.style.opacity = "1";
    pill.style.width = `${a.offsetWidth}px`;
    pill.style.transform = `translateX(${a.offsetLeft}px)`;
  };
  const sync = () => {
    current = links.find((a) => new URL(a.href).pathname === location.pathname);
    links.forEach((a) => (a === current ? a.setAttribute("aria-current", "page") : a.removeAttribute("aria-current")));
    place(current);
  };

  nav.classList.add("js");
  links.forEach((a) => {
    a.addEventListener("pointerenter", () => place(a));
    a.addEventListener("focus", () => place(a));
  });
  nav.addEventListener("pointerleave", () => place(current));
  nav.addEventListener("focusout", () => place(current));
  document.addEventListener("astro:page-load", sync);
  addEventListener("resize", () => place(current));
  document.fonts?.ready.then(() => place(current));
  sync();
}
