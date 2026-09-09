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

  it("estimate wizard large panel min-height is 95vh from open (Core 4.3.1 / 4.3.2 / 4.3.3)", () => {
    jest.spyOn(window, "requestAnimationFrame").mockImplementation((cb) => {
      cb();
      return 0;
    });

    const container = document.createElement("div");
    container.className = "slds-modal__container";
    const host = document.createElement("c-estimate-create-record-action");
    container.appendChild(host);
    document.body.appendChild(container);

    resizeQuickActionPanel({ template: { host } }, "large");

    expect(container.style.getPropertyValue("min-height")).toBe("95vh");
    expect(container.style.getPropertyValue("height")).toBe("95vh");
    const styleEl = document.getElementById("c-quick-action-panel-resize-style");
    expect(styleEl.textContent).toContain("c-estimate-create-record-action");
    expect(styleEl.textContent).toContain("min-height: 95vh");
  });

  it("order large panel does not lock min-height to 95vh", () => {
    jest.spyOn(window, "requestAnimationFrame").mockImplementation((cb) => {
      cb();
      return 0;
    });

    const container = document.createElement("div");
    container.className = "slds-modal__container";
    const host = document.createElement("c-order-create-record-action");
    container.appendChild(host);
    document.body.appendChild(container);

    resizeQuickActionPanel({ template: { host } }, "large");

    expect(container.style.getPropertyValue("min-height")).toBe("0");
    expect(container.style.getPropertyValue("height")).toBe("95vh");
  });

  it("invoice board host is pinned to the 95vh container", () => {
    jest.spyOn(window, "requestAnimationFrame").mockImplementation((cb) => {
      cb();
      return 0;
    });

    const container = document.createElement("div");
    container.className = "slds-modal__container";
    const clip = document.createElement("div");
    clip.style.overflow = "hidden";
    clip.style.height = "64px";
    const host = document.createElement(
      "c-order-invoice-preview-record-action"
    );
    clip.appendChild(host);
    container.appendChild(clip);
    document.body.appendChild(container);

    resizeQuickActionPanel({ template: { host } }, "large");

    expect(container.style.getPropertyValue("position")).toBe("relative");
    expect(host.style.getPropertyValue("position")).toBe("absolute");
    expect(host.style.getPropertyValue("top")).toBe("0px");
    expect(host.style.getPropertyValue("bottom")).toBe("0px");
    expect(clip.style.getPropertyValue("height")).toBe("100%");
    const styleEl = document.getElementById("c-quick-action-panel-resize-style");
    expect(styleEl.textContent).toContain("position: absolute");
    expect(styleEl.textContent).toContain("c-order-invoice-preview-wizard");
  });
});
