// The docs nav: a white pill rests on the current page and slides to whatever the pointer or focus is on.
const nav = document.querySelector<HTMLElement>(".nav");
const pill = nav?.querySelector<HTMLElement>(".pill");
if (nav && pill) {
  const links = [...nav.querySelectorAll<HTMLAnchorElement>("a")];
  const current = links.find((a) => a.getAttribute("aria-current") === "page");
  const place = (a?: HTMLAnchorElement) => {
    links.forEach((l) => l.classList.toggle("on", l === a));
    if (!a) {
      pill.style.opacity = "0";
      return;
    }
    pill.style.opacity = "1";
    pill.style.width = `${a.offsetWidth}px`;
    pill.style.transform = `translateX(${a.offsetLeft}px)`;
  };
  nav.classList.add("js");
  place(current);
  links.forEach((a) => {
    a.addEventListener("pointerenter", () => place(a));
    a.addEventListener("focus", () => place(a));
  });
  nav.addEventListener("pointerleave", () => place(current));
  nav.addEventListener("focusout", () => place(current));
}
