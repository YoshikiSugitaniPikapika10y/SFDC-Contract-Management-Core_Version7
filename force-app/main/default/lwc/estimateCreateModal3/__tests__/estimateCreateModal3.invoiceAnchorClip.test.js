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

    expect(column).toMatch(/width:\s*22rem/);
    expect(cell).toMatch(/min-width:\s*22rem/);
    expect(cell).toMatch(/overflow:\s*visible/);
    expect(cell).not.toMatch(/overflow:\s*hidden/);
    expect(anchor).toMatch(/overflow:\s*visible/);
    expect(anchor).toMatch(/white-space:\s*nowrap/);
    expect(css).not.toMatch(/\.est-td-product,\s*\.est-td-invoice/);
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
