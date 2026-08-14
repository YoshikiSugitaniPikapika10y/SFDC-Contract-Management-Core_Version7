import { createElement } from "lwc";
import OrderInvoicePreviewTable from "c/orderInvoicePreviewTable";

jest.mock(
  "@salesforce/apex/OrderCreateController.getSplitThresholdDateOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "lightning/confirm",
  () => ({
    default: {
      open: jest.fn()
    }
  }),
  { virtual: true }
);

const LINE_ID = "a01LINE00000001";
const INVOICE_ID = "a00INV000000001";

function buildEditablePreview() {
  return {
    canEdit: true,
    sourceHistoryVersion: "1",
    versionOptions: [{ label: "V1", value: "1" }],
    invoices: [
      {
        invoiceId: INVOICE_ID,
        invoiceName: "INV-1",
        amountTotal: 10000,
        taxTotal: 1000,
        taxPercent: 10,
        clearedAmount: 0,
        integratedAmount: 0,
        openAmount: 10000,
        locked: false,
        billingAccountId: "a00BA0000000001",
        invoiceDate: "2026-04-01",
        lines: [
          {
            lineId: LINE_ID,
            productName: "Product",
            amount: 10000,
            clearedAmount: 0,
            integratedAmount: 0,
            openAmount: 10000,
            historyVersionLabel: "V1",
            historyVersions: ["1"],
            isRecurring: true,
            unitPrice: 10000,
            quantity: 1
          }
        ]
      }
    ]
  };
}

function findButtonByText(element, text) {
  return [...element.shadowRoot.querySelectorAll("button")].find(
    (btn) => btn.textContent.trim() === text
  );
}

describe("orderInvoicePreviewTable draft/split gate", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("disables ± after opening 請求を分ける", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildEditablePreview();
    document.body.appendChild(element);
    await Promise.resolve();

    const openSplit = findButtonByText(element, "請求を分ける");
    expect(openSplit).toBeTruthy();
    expect(openSplit.disabled).toBe(false);
    openSplit.click();
    await Promise.resolve();

    const plus10 = element.shadowRoot.querySelector('button[data-delta="10"]');
    expect(plus10).toBeTruthy();
    expect(plus10.disabled).toBe(true);
  });

  it("blocks opening 請求を分ける while unsaved ± drafts exist", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildEditablePreview();
    document.body.appendChild(element);
    await Promise.resolve();

    const plus10 = element.shadowRoot.querySelector('button[data-delta="10"]');
    expect(plus10.disabled).toBe(false);
    plus10.click();
    await Promise.resolve();

    const openSplit = findButtonByText(element, "請求を分ける");
    expect(openSplit.disabled).toBe(true);
  });

  it("re-enables ± after toggling 分割 chip off", async () => {
    const getSplitThresholdDateOptions = require("@salesforce/apex/OrderCreateController.getSplitThresholdDateOptions")
      .default;
    getSplitThresholdDateOptions.mockResolvedValue([
      { invoiceLineId: LINE_ID, options: [] }
    ]);

    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildEditablePreview();
    document.body.appendChild(element);
    await Promise.resolve();

    const splitChip = [...element.shadowRoot.querySelectorAll("button")].find(
      (btn) =>
        btn.dataset.invoiceId === INVOICE_ID &&
        btn.dataset.lineId === LINE_ID &&
        btn.textContent.trim() === "分割"
    );
    expect(splitChip).toBeTruthy();
    splitChip.click();
    await Promise.resolve();
    await Promise.resolve();

    let plus10 = element.shadowRoot.querySelector('button[data-delta="10"]');
    expect(plus10.disabled).toBe(true);

    splitChip.click();
    await Promise.resolve();

    plus10 = element.shadowRoot.querySelector('button[data-delta="10"]');
    expect(plus10.disabled).toBe(false);
  });
});
