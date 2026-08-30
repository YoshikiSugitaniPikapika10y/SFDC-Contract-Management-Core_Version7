import { createElement } from "lwc";
import OrderInvoicePreviewWizard from "c/orderInvoicePreviewWizard";

jest.mock(
  "lightning/actions",
  () => ({
    CloseActionScreenEvent: class CloseActionScreenEvent extends CustomEvent {
      constructor() {
        super("lightning__closeactionscreen");
      }
    }
  }),
  { virtual: true }
);

jest.mock(
  "lightning/refresh",
  () => ({
    RefreshEvent: class RefreshEvent extends CustomEvent {
      constructor() {
        super("lightning__refreshview");
      }
    }
  }),
  { virtual: true }
);

const apexMethods = [
  "OrderCreateController.resolvePreviewScope",
  "OrderCreateController.getInvoicePreview",
  "OrderCreateController.updateInvoiceLineAmounts",
  "OrderCreateController.splitInvoiceByDate",
  "OrderCreateController.splitInvoiceByBillingAccount",
  "OrderCreateController.moveLinesToExistingInvoice",
  "OrderCreateController.splitLinesInPlace",
  "OrderCreateController.resetLatestVersionInvoicesToPostOrder",
  "OrderCreateController.getBillingAccountOptionsForPreview",
  "OrderCreateController.updateInvoiceHeaderAndDates",
  "OrderCreateController.applyBillingAccountContent",
  "OrderCreateController.cancelConfirmedFromPreview"
];

apexMethods.forEach((method) => {
  jest.mock(
    `@salesforce/apex/${method}`,
    () => ({ default: jest.fn().mockResolvedValue(null) }),
    { virtual: true }
  );
});

function buildWizard() {
  const element = createElement("c-order-invoice-preview-wizard", {
    is: OrderInvoicePreviewWizard
  });
  document.body.appendChild(element);
  return element;
}

/** jsdom はレイアウトを持たないので、スクロール可能な状態を手で用意する */
function makeScrollable(el) {
  const state = { scrollTop: 0 };
  Object.defineProperty(el, "scrollTop", {
    configurable: true,
    get: () => state.scrollTop,
    set: (value) => {
      state.scrollTop = value;
    }
  });
  Object.defineProperty(el, "scrollHeight", {
    configurable: true,
    get: () => 2000
  });
  Object.defineProperty(el, "clientHeight", {
    configurable: true,
    get: () => 500
  });
  el.style.overflowY = "auto";
  return state;
}

function wheelOver(target, deltaY) {
  const event = new WheelEvent("wheel", {
    deltaY,
    bubbles: true,
    composed: true,
    cancelable: true
  });
  target.dispatchEvent(event);
  return event;
}

describe("orderInvoicePreviewWizard scroll", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("ビューポート実測値から自前スクローラの高さ上限を決める", async () => {
    const element = buildWizard();
    await Promise.resolve();

    const page = element.shadowRoot.querySelector(".preview-page");
    const limit = page.style.getPropertyValue("--preview-scroll-max");
    expect(limit).toMatch(/^\d+px$/);
    expect(parseInt(limit, 10)).toBeGreaterThan(0);
  });

  it("ヘッダ上でもホイールでルートスクローラが動く", async () => {
    const element = buildWizard();
    await Promise.resolve();

    const page = element.shadowRoot.querySelector(".preview-page");
    const state = makeScrollable(page);

    const event = wheelOver(
      element.shadowRoot.querySelector(".preview-header"),
      120
    );

    expect(state.scrollTop).toBe(120);
    expect(event.defaultPrevented).toBe(true);
  });

  it("スクローラを持たない余白上でもホイールが届く", async () => {
    const element = buildWizard();
    await Promise.resolve();

    const page = element.shadowRoot.querySelector(".preview-page");
    const state = makeScrollable(page);

    wheelOver(element.shadowRoot.querySelector(".preview-body"), 240);

    expect(state.scrollTop).toBe(240);
  });

  it("先頭で上方向ホイールは奪わない", async () => {
    const element = buildWizard();
    await Promise.resolve();

    const page = element.shadowRoot.querySelector(".preview-page");
    makeScrollable(page);

    const event = wheelOver(
      element.shadowRoot.querySelector(".preview-header"),
      -120
    );

    expect(event.defaultPrevented).toBe(false);
  });
});
