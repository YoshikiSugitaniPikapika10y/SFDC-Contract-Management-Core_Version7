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

const apexMethods = [
  "OrderCreateController.resolvePreviewScope",
  "OrderCreateController.getInvoicePreview",
  "OrderCreateController.updateInvoiceLineAmounts",
  "OrderCreateController.updateInvoiceLineAcceptanceEndDate",
  "OrderCreateController.previewInvoiceLineAcceptanceEndDate",
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

function flushPromises() {
  return new Promise((resolve) => {
    setImmediate(resolve);
  });
}

describe("orderInvoicePreviewWizard reload (Core 4.3.11)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("読込失敗時に再読み込みを出し、押すと再取得する", async () => {
    resolvePreviewScope.mockRejectedValue(new Error("読込失敗"));

    const element = createElement("c-order-invoice-preview-wizard", {
      is: OrderInvoicePreviewWizard
    });
    element.recordId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    const reload = [...element.shadowRoot.querySelectorAll("button")].find(
      (btn) => btn.textContent.trim() === "再読み込み"
    );
    expect(reload).toBeTruthy();

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

  it("開けない業務拒否では再読み込みを出さない", async () => {
    resolvePreviewScope.mockResolvedValue({
      canOpen: false,
      blockReason: "請求ボードを開けません。"
    });

    const element = createElement("c-order-invoice-preview-wizard", {
      is: OrderInvoicePreviewWizard
    });
    element.recordId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    expect(element.shadowRoot.textContent).toContain("請求ボードを開けません。");
    expect(element.shadowRoot.textContent).not.toContain("再読み込み");
  });
});
