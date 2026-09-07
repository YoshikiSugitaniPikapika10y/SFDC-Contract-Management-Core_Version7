import { createElement } from "lwc";
import OrderInvoicePreviewWizard from "c/orderInvoicePreviewWizard";
import resolvePreviewScope from "@salesforce/apex/OrderCreateController.resolvePreviewScope";
import getInvoicePreview from "@salesforce/apex/OrderCreateController.getInvoicePreview";
import getBillingAccountOptionsForPreview from "@salesforce/apex/OrderCreateController.getBillingAccountOptionsForPreview";

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
jest.mock(
  "lightning/uiRecordApi",
  () => ({ getRecordNotifyChange: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/navigation",
  () => ({
    NavigationMixin: (Base) =>
      class extends Base {
        [Symbol.for("NavigationMixin.Navigate")]() {}
      },
    CurrentPageReference: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "lightning/platformShowToastEvent",
  () => ({ ShowToastEvent: class ShowToastEvent {} }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/OrderCreateController.resolvePreviewScope",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.getInvoicePreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.updateInvoiceLineAmounts",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.updateInvoiceLineAcceptanceEndDate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.previewInvoiceLineAcceptanceEndDate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.splitInvoiceByDate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.splitInvoiceByBillingAccount",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.moveLinesToExistingInvoice",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.splitLinesInPlace",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.resetLatestVersionInvoicesToPostOrder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.getBillingAccountOptionsForPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.updateInvoiceHeaderAndDates",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.applyBillingAccountContent",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderCreateController.cancelConfirmedFromPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function flushPromises() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe("orderInvoicePreviewWizard reload (Core 4.3.11 / 7.7)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows the board title, and reload after a content load failure", async () => {
    resolvePreviewScope.mockRejectedValue({
      body: { message: "読込失敗" }
    });

    const element = createElement("c-order-invoice-preview-wizard", {
      is: OrderInvoicePreviewWizard
    });
    element.recordId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".preview-title").textContent.trim()
    ).toBe("請求ボード");
    const reload = [...element.shadowRoot.querySelectorAll("button")].find(
      (btn) => btn.textContent.trim() === "再読み込み"
    );
    expect(reload).toBeTruthy();
    expect(element.shadowRoot.textContent).toContain("読込失敗");

    resolvePreviewScope.mockResolvedValue({
      canOpen: true,
      contractHistoryId: "a0H000000000001AAA"
    });
    getInvoicePreview.mockResolvedValue({ invoices: [] });
    getBillingAccountOptionsForPreview.mockResolvedValue([]);

    reload.click();
    await flushPromises();
    await flushPromises();

    expect(resolvePreviewScope).toHaveBeenCalledTimes(2);
    expect(getInvoicePreview).toHaveBeenCalledTimes(1);
  });

  it("keeps the opened board table across invoiceopscomplete reload (Core 7.7.0)", async () => {
    resolvePreviewScope.mockResolvedValue({
      canOpen: true,
      contractHistoryId: "a0H000000000001AAA"
    });
    getInvoicePreview.mockResolvedValue({ invoices: [] });
    getBillingAccountOptionsForPreview.mockResolvedValue([]);

    const element = createElement("c-order-invoice-preview-wizard", {
      is: OrderInvoicePreviewWizard
    });
    element.recordId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    const table = element.shadowRoot.querySelector(
      "c-order-invoice-preview-table"
    );
    expect(table).toBeTruthy();
    table.dispatchEvent(new CustomEvent("invoiceopscomplete"));
    await flushPromises();
    await flushPromises();

    const tableAfter = element.shadowRoot.querySelector(
      "c-order-invoice-preview-table"
    );
    expect(tableAfter).toBe(table);
    expect(getInvoicePreview).toHaveBeenCalledTimes(2);
  });

  it("does not show reload when the board is refused for business reasons", async () => {
    resolvePreviewScope.mockResolvedValue({
      canOpen: false,
      blockReason:
        "Latest Ordered がない契約サービスでは請求ボードを開けません。"
    });

    const element = createElement("c-order-invoice-preview-wizard", {
      is: OrderInvoicePreviewWizard
    });
    element.recordId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain(
      "Latest Ordered がない契約サービスでは請求ボードを開けません。"
    );
    expect(element.shadowRoot.textContent).not.toContain("再読み込み");
  });
});
