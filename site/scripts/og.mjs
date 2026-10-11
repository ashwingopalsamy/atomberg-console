// 1200x630 share cards, dark and monochrome like the site. One per page, drawn with satori and rasterised with resvg.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import satori from "satori";
import { Resvg } from "@resvg/resvg-js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dist = join(root, "dist");
const knowledge = JSON.parse(readFileSync(join(root, "src/generated/knowledge.json"), "utf8"));
const font = (weight) =>
  readFileSync(join(root, `node_modules/@fontsource/geist-sans/files/geist-sans-latin-${weight}-normal.woff`));
const fonts = [
  { name: "Geist", data: font(400), weight: 400, style: "normal" },
  { name: "Geist", data: font(600), weight: 600, style: "normal" },
];
const png = (file) => `data:image/png;base64,${readFileSync(join(root, "public/brand", file)).toString("base64")}`;
const tile = png("tile.png");
const glyph = png("glyph.png");

const el = (type, style, children) => ({ type, props: { style, children } });
const row = (style, children) => el("div", { display: "flex", ...style }, children);

function card({ title, description, big }) {
  return row(
    { width: 1056, height: 486, background: "#0e0f10", padding: 72, flexDirection: "column", justifyContent: "space-between", fontFamily: "Geist" },
    [
      row({ alignItems: "center", gap: 20 }, [
        row({ position: "relative", width: 72, height: 72 }, [
          { type: "img", props: { src: tile, width: 72, height: 72, style: { position: "absolute", left: 0, top: 0 } } },
          { type: "img", props: { src: glyph, width: 72, height: 72, style: { position: "absolute", left: 0, top: 0 } } },
        ]),
        el("div", { display: "flex", fontSize: 30, fontWeight: 600, color: "#f5f5f7", letterSpacing: -0.5 }, "Atomberg Console"),
      ]),
      row({ flexDirection: "column", gap: 22, maxWidth: 1040 }, [
        el("div", { display: "flex", flexDirection: "column", fontSize: big ? 76 : 72, fontWeight: 600, color: "#f5f5f7", letterSpacing: big ? -3.2 : -3, lineHeight: 1.06 }, title.split("|").map((line, i) => el("div", { display: "flex", color: i === 0 ? "#f5f5f7" : "#a4a7ae" }, line))),
        el("div", { display: "flex", fontSize: 32, color: "#8b8b95", lineHeight: 1.35 }, description),
      ]),
      el("div", { display: "flex", fontSize: 24, color: "#5e5e68" }, "apps.ashwingopalsamy.in/atomberg-console"),
    ],
  );
}

const items = [
  { slug: "home", title: "All your Atomberg devices,|in the menu bar.", description: "Fans, purifiers and locks, one click away.", big: true },
];

mkdirSync(join(dist, "og"), { recursive: true });
for (const item of items) {
  const svg = await satori(card(item), { width: 1200, height: 630, fonts });
  const image = new Resvg(svg, { fitTo: { mode: "width", value: 1200 } }).render().asPng();
  writeFileSync(join(dist, "og", `${item.slug}.png`), image);
}
console.log(`og: ${items.length} cards`);
