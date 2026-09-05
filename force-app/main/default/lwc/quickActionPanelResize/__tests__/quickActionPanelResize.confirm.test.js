import { resizeQuickActionPanel } from "c/quickActionPanelResize";

describe("quickActionPanelResize confirm (Core 4.3.1 / 5.2 / 5.3)", () => {
  afterEach(() => {
    const styleEl = document.getElementById("c-quick-action-panel-resize-style");
    if (styleEl && styleEl.parentNode) {
      styleEl.parentNode.removeChild(styleEl);
    }
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.restoreAllMocks();
  });

  it("confirm is landscape rem width and height auto, not 95vw", () => {
    jest.spyOn(window, "requestAnimationFrame").mockImplementation((cb) => {
      cb();
      return 0;
    });

    const host = document.createElement("div");
    document.body.appendChild(host);

    resizeQuickActionPanel({ template: { host } }, "confirm");

    const styleEl = document.getElementById("c-quick-action-panel-resize-style");
    expect(styleEl).toBeTruthy();
    expect(styleEl.textContent).toContain("c-order-revert-record-action");
    expect(styleEl.textContent).toContain("min(100% - 2rem, 48rem)");
    expect(styleEl.textContent).toContain("height: auto");
  });
});
