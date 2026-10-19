const fs = require("fs");
const path = require("path");

const css = fs.readFileSync(
  path.join(__dirname, "../estimateCreateModal3.css"),
  "utf8"
);

function ruleBody(selector) {
  const pattern = new RegExp(
    `${selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*\\{([^}]*)\\}`
  );
  const match = css.match(pattern);
  return match ? match[1] : "";
}

describe("invoice anchor is fully visible (Core 4.6)", () => {
  it("keeps the monthly anchor inside the invoice column without clipping it", () => {
    const column = ruleBody(".est-col-invoice");
    const cell = ruleBody(".est-td-invoice");
    const anchor = ruleBody(".est-td-invoice .est-invoice-anchor-meta");

    expect(column).toMatch(/width:\s*12%/);
    expect(cell).toMatch(/min-width:\s*0/);
    expect(cell).not.toMatch(/min-width:\s*19rem/);
    expect(cell).toMatch(/overflow:\s*visible/);
    expect(cell).not.toMatch(/overflow:\s*hidden/);
    expect(anchor).toMatch(/overflow:\s*visible/);
    expect(anchor).toMatch(/white-space:\s*normal/);
    expect(css).not.toMatch(/\.est-td-product,\s*\.est-td-invoice/);
  });

  it("keeps price and date shortcut buttons from stacking on one another", () => {
    const dateStack = ruleBody(".est-td-date .est-cell-stack");
    const dateSub = ruleBody(".est-td-date .est-cell-stack__sub");
    const shortcuts = ruleBody(".est-date-shortcuts_nowrap");
    const tableChip = ruleBody(".est-table .est-date-chip");

    expect(dateStack).toMatch(/auto/);
    expect(dateSub).toMatch(/overflow:\s*visible/);
    expect(shortcuts).toMatch(/grid-template-columns:\s*minmax\(0,\s*1fr\)/);
    expect(shortcuts).not.toMatch(/repeat\(2/);
    expect(shortcuts).toMatch(/gap:\s*0\.2rem/);
    expect(tableChip).toMatch(/white-space:\s*nowrap/);
    expect(tableChip).toMatch(/font-size:\s*0\.875rem/);
    expect(tableChip).toMatch(/height:\s*1\.75rem/);
    expect(tableChip).not.toMatch(/overflow:\s*hidden/);
  });

  it("shows the product name at the amount size, in the amount color, on one line", () => {
    const name = ruleBody(".est-product-name");

    expect(name).toMatch(/font-size:\s*var\(--est-font-control\)/);
    expect(name).toMatch(/font-weight:\s*700/);
    expect(name).toMatch(/color:\s*var\(--est-accent\)/);
    expect(name).toMatch(/white-space:\s*nowrap/);
    expect(name).toMatch(/text-overflow:\s*ellipsis/);
  });

  it("does not clip the amount meta or the revenue label (DESIGN-1101)", () => {
    expect(ruleBody(".est-td-amount .est-price-meta")).toMatch(
      /overflow:\s*visible/
    );
    expect(css).toMatch(
      /\.est-td-revenue \.est-cell-static\s*\{[^}]*overflow:\s*visible/
    );
  });
});
