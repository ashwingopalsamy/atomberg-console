// Two small things: the tile turns its blades once per tap, and one button copies the install command.
const logo = document.querySelector<HTMLElement>(".logo");
let turns = 0;
logo?.addEventListener("click", () => {
  turns += 1;
  logo.style.setProperty("--r", `${turns * 360}deg`);
});

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
