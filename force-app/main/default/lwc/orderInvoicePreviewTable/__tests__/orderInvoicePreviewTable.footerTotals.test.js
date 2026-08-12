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

function buildPreview({
  amountTotal,
  taxTotal,
  clearedAmount,
  taxPercent = 10,
  versionLabel = "V1",
  sourceHistoryVersion = "1"
}) {
  return {
    canEdit: false,
    sourceHistoryVersion,
    versionOptions: [
      { label: "すべて", value: "ALL" },
      { label: "V1", value: "1" },
      { label: "V2", value: "2" }
    ],
    invoices: [
      {
        invoiceId: "a00INV000000001",
        invoiceName: "INV-1",
        amountTotal,
        taxTotal,
        taxPercent,
        clearedAmount,
        integratedAmount: 0,
        openAmount: 0,
        locked: false,
        lines: [
          {
            lineId: "a01LINE00000001",
            productName: "Product",
            amount: amountTotal,
            clearedAmount,
            integratedAmount: 0,
            openAmount: 0,
            historyVersionLabel: versionLabel,
            isRecurring: true,
            unitPrice: amountTotal,
            quantity: 1
          }
        ]
      }
    ]
  };
}

describe("orderInvoicePreviewTable footer totals", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("maps full clearedAmount to header taxInclusive under Version filter (avoids ¥1 drift)", async () => {
    // 税抜7・税1 → ヘッダ税込8。行再計算は 7+trunc(7*0.1)=7 で ¥1 ずれる。
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview({
      amountTotal: 7,
      taxTotal: 1,
      clearedAmount: 7,
      taxPercent: 10,
      sourceHistoryVersion: "1"
    });
    document.body.appendChild(element);
    await Promise.resolve();

    const statusValues = Array.from(
      element.shadowRoot.querySelectorAll(
        "footer.invoice-footer .summary-row_status lightning-formatted-number"
      )
    ).map((node) => Number(node.value));
    // 請求前 / 請求済 / 入金消込（税込）
    expect(statusValues).toEqual([0, 0, 8]);
  });
});
