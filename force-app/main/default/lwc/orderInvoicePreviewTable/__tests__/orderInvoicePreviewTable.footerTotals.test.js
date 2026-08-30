import { createElement } from "lwc";
import OrderInvoicePreviewTable from "c/orderInvoicePreviewTable";
import getOpsBundle from "@salesforce/apex/InvoicePreviewOpsController.getOpsBundle";

jest.mock(
  "@salesforce/customPermission/Loop_16_Can_LockJournal",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_17_Can_UnlockJournal",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_10_Can_EditDraftInvoice",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_11_Can_ConfirmInvoice",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_12_Can_SendInvoice",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_13_Can_InvoicePayment",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_14_Can_ManualJournal",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_15_Can_CancelInvoice",
  () => ({ default: true }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/OrderCreateController.getSplitThresholdDateOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoiceSendBoardController.getBoardContext",
  () => ({
    default: jest.fn().mockResolvedValue({
      featureEnabled: false,
      canSend: true,
      documentTemplateOptions: [],
      emailTemplateOptions: []
    })
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoiceSendBoardController.confirmInvoiceFromPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoiceBoardDocumentService.sendFromPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoiceBoardDocumentService.issueFromPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoiceBoardDocumentService.previewIssueFromPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoicePreviewOpsController.lockJournalsForInvoice",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoicePreviewOpsController.unlockJournalsForInvoice",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoicePreviewOpsController.updateJournalMemo",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoiceOpsFieldService.getDefinitions",
  () => ({ default: jest.fn().mockResolvedValue([]) }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoicePreviewOpsController.updatePaymentFromPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoiceOpsController.updateInvoiceMemo",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoicePreviewOpsController.getOpsBundle",
  () => ({ default: jest.fn().mockResolvedValue(null) }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoicePreviewOpsController.savePaymentFromPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoicePreviewOpsController.cancelPaymentFromPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoicePreviewOpsController.previewCancelPaymentFromPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoicePreviewOpsController.previewRegisterFromPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/OrderCreateController.previewInvoiceLineAcceptanceEndDate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/OrderCreateController.previewCancelConfirmed",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "c/estimateLineItemUtils",
  () => ({
    resolveScaledNumericInput: jest.fn(),
    roundUnitPrice: jest.fn((value) => Number(value)),
    setAmountCalculationRoundingModes: jest.fn()
  }),
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
    taxRoundingMode: "DOWN",
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
    getOpsBundle.mockResolvedValue(null);
  });

  it("does not drop unset quantity rounding to 0 (Core 11.9 / 1.1.10)", () => {
    const { roundUnitPrice } = require("c/estimateLineItemUtils");
    roundUnitPrice.mockReturnValueOnce(Number.NaN);
    expect(
      OrderInvoicePreviewTable.prototype.roundMoney2.call({}, 10.55)
    ).toBeNaN();
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
    // 請求前 / 請求金額未処理 / 請求金額処理済み / 請求金額外Net / 差額
    expect(statusValues).toEqual([8, 8, 0, 0, -8]);
    expect(element.shadowRoot.textContent).toContain("請求金額未処理（回収）");
  });

  it("shows absolute unprocessed remaining with 返金 direction when net is negative", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    const preview = buildPreview({
      amountTotal: 7,
      taxTotal: 1,
      clearedAmount: 7,
      taxPercent: 10,
      sourceHistoryVersion: "1"
    });
    preview.invoices[0].taxInclusiveAmount = 8;
    preview.invoices[0].invoicePaymentNet = 16;
    preview.invoices[0].invoiceTransactionStatus = "Confirmed";
    element.preview = preview;
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();

    const statusValues = Array.from(
      element.shadowRoot.querySelectorAll(
        "footer.invoice-footer .summary-row_status lightning-formatted-number"
      )
    ).map((node) => Number(node.value));
    // 未処理は|8-16|=8、方向は返金
    expect(statusValues).toContain(8);
    expect(element.shadowRoot.textContent).toContain("請求金額未処理（返金）");
  });

  it("keeps Version totals for the selected invoice when parent is all versions", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.initialVersion = "ALL";
    element.initialInvoiceId = "a00INV000000002";
    element.preview = {
      canEdit: false,
      taxRoundingMode: "DOWN",
      sourceHistoryVersion: "1",
      periodLineAmountTotal: 6000,
      invoiceAmountTotal: 6000,
      versionOptions: [
        {
          label: "V1",
          value: "1",
          periodLineAmountTotal: 1000,
          invoiceAmountTotal: 1000
        },
        {
          label: "V2",
          value: "2",
          periodLineAmountTotal: 5000,
          invoiceAmountTotal: 5000
        }
      ],
      invoices: [
        {
          invoiceId: "a00INV000000001",
          invoiceName: "INV-1",
          historyVersion: 1,
          amountTotal: 1000,
          taxTotal: 100,
          taxPercent: 10,
          taxInclusiveAmount: 1100,
          locked: false,
          lines: [
            {
              lineId: "a01LINE00000001",
              productName: "A",
              amount: 1000,
              historyVersionLabel: "V1",
              isRecurring: true,
              unitPrice: 1000,
              quantity: 1
            }
          ]
        },
        {
          invoiceId: "a00INV000000002",
          invoiceName: "INV-2",
          historyVersion: 2,
          amountTotal: 5000,
          taxTotal: 500,
          taxPercent: 10,
          taxInclusiveAmount: 5500,
          locked: false,
          lines: [
            {
              lineId: "a01LINE00000002",
              productName: "B",
              amount: 5000,
              historyVersionLabel: "V2",
              isRecurring: true,
              unitPrice: 5000,
              quantity: 1
            }
          ]
        }
      ]
    };
    document.body.appendChild(element);
    await Promise.resolve();

    const compareValues = Array.from(
      element.shadowRoot.querySelectorAll(
        ".amount-compare lightning-formatted-number"
      )
    ).map((node) => Number(node.value));
    expect(compareValues[0]).toBe(5000);
    expect(compareValues[1]).toBe(5000);
  });

  it("enables confirm only for the invoice Version when parent is all versions", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.initialVersion = "ALL";
    element.preview = {
      canEdit: true,
      taxRoundingMode: "DOWN",
      sourceHistoryVersion: "1",
      periodLineAmountTotal: 6000,
      periodLineTaxInclusiveTotal: 6600,
      invoiceAmountTotal: 5900,
      invoiceTaxInclusiveTotal: 6490,
      versionOptions: [
        {
          label: "V1",
          value: "1",
          periodLineAmountTotal: 1000,
          periodLineTaxInclusiveTotal: 1100,
          invoiceAmountTotal: 900,
          invoiceTaxInclusiveTotal: 990
        },
        {
          label: "V2",
          value: "2",
          periodLineAmountTotal: 5000,
          periodLineTaxInclusiveTotal: 5500,
          invoiceAmountTotal: 5000,
          invoiceTaxInclusiveTotal: 5500
        }
      ],
      invoices: [
        {
          invoiceId: "a00INV000000001",
          invoiceName: "INV-1",
          historyVersion: 1,
          amountTotal: 900,
          taxTotal: 90,
          taxPercent: 10,
          taxInclusiveAmount: 990,
          canConfirm: true,
          invoiceTransactionStatus: "Draft",
          locked: false,
          lines: [
            {
              lineId: "a01LINE00000001",
              productName: "A",
              amount: 900,
              historyVersionLabel: "V1",
              historyVersions: ["1"],
              isRecurring: true,
              unitPrice: 900,
              quantity: 1
            }
          ]
        },
        {
          invoiceId: "a00INV000000002",
          invoiceName: "INV-2",
          historyVersion: 2,
          amountTotal: 5000,
          taxTotal: 500,
          taxPercent: 10,
          taxInclusiveAmount: 5500,
          canConfirm: true,
          invoiceTransactionStatus: "Draft",
          locked: false,
          lines: [
            {
              lineId: "a01LINE00000002",
              productName: "B",
              amount: 5000,
              historyVersionLabel: "V2",
              historyVersions: ["2"],
              isRecurring: true,
              unitPrice: 5000,
              quantity: 1
            }
          ]
        }
      ]
    };
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();

    const buttons = Array.from(
      element.shadowRoot.querySelectorAll('button.solid-btn[data-invoice-id]')
    ).filter((button) => button.textContent.trim() === "確定する");
    expect(buttons).toHaveLength(2);
    const byId = Object.fromEntries(
      buttons.map((button) => [button.dataset.invoiceId, button.disabled])
    );
    expect(byId.a00INV000000001).toBe(true);
    expect(byId.a00INV000000002).toBe(false);
    expect(element.shadowRoot.querySelector(".amount-compare-status").textContent).toBe(
      "端数あり"
    );
  });

  it("disables confirm when tax-inclusive totals differ even if tax-excl matches", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.initialVersion = "1";
    element.preview = {
      canEdit: true,
      taxRoundingMode: "DOWN",
      sourceHistoryVersion: "1",
      periodLineAmountTotal: 1000,
      periodLineTaxInclusiveTotal: 1100,
      invoiceAmountTotal: 1000,
      invoiceTaxInclusiveTotal: 1099,
      versionOptions: [
        {
          label: "V1",
          value: "1",
          periodLineAmountTotal: 1000,
          periodLineTaxInclusiveTotal: 1100,
          invoiceAmountTotal: 1000,
          invoiceTaxInclusiveTotal: 1099
        }
      ],
      invoices: [
        {
          invoiceId: "a00INV000000001",
          invoiceName: "INV-1",
          historyVersion: 1,
          amountTotal: 1000,
          taxTotal: 99,
          taxPercent: 10,
          taxInclusiveAmount: 1099,
          canConfirm: true,
          invoiceTransactionStatus: "Draft",
          locked: false,
          lines: [
            {
              lineId: "a01LINE00000001",
              productName: "A",
              amount: 1000,
              historyVersionLabel: "V1",
              historyVersions: ["1"],
              isRecurring: true,
              unitPrice: 1000,
              quantity: 1
            }
          ]
        }
      ]
    };
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();

    const button = Array.from(
      element.shadowRoot.querySelectorAll("button.solid-btn")
    ).find((node) => node.textContent.trim() === "確定する");
    expect(button).toBeTruthy();
    expect(button.disabled).toBe(true);
    expect(element.shadowRoot.querySelector(".amount-compare-status").textContent).toBe(
      "端数あり"
    );
  });

  it("hides invoice cards that do not belong to the parent Version", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.initialVersion = "1";
    element.preview = {
      canEdit: false,
      taxRoundingMode: "DOWN",
      sourceHistoryVersion: "1",
      periodLineAmountTotal: 1000,
      invoiceAmountTotal: 1000,
      versionOptions: [
        { label: "V1", value: "1", periodLineAmountTotal: 1000, invoiceAmountTotal: 1000 },
        { label: "V2", value: "2", periodLineAmountTotal: 5000, invoiceAmountTotal: 5000 }
      ],
      invoices: [
        {
          invoiceId: "a00INV000000001",
          invoiceName: "INV-1",
          historyVersion: 1,
          amountTotal: 1000,
          taxTotal: 100,
          taxPercent: 10,
          taxInclusiveAmount: 1100,
          locked: false,
          lines: [
            {
              lineId: "a01LINE00000001",
              productName: "A",
              amount: 1000,
              historyVersionLabel: "V1",
              isRecurring: true,
              unitPrice: 1000,
              quantity: 1
            }
          ]
        },
        {
          invoiceId: "a00INV000000002",
          invoiceName: "INV-2",
          historyVersion: 2,
          amountTotal: 5000,
          taxTotal: 500,
          taxPercent: 10,
          taxInclusiveAmount: 5500,
          locked: false,
          lines: [
            {
              lineId: "a01LINE00000002",
              productName: "B",
              amount: 5000,
              historyVersionLabel: "V2",
              isRecurring: true,
              unitPrice: 5000,
              quantity: 1
            }
          ]
        }
      ]
    };
    document.body.appendChild(element);
    await Promise.resolve();

    const text = element.shadowRoot.textContent;
    expect(text).toContain("INV-1");
    expect(text).not.toContain("INV-2");
  });

  it("shows signed payment-net minus tax-inclusive as 差額 and does not invert negative invoices", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = {
      canEdit: false,
      taxRoundingMode: "DOWN",
      sourceHistoryVersion: "1",
      versionOptions: [{ label: "V1", value: "1" }],
      invoices: [
        {
          invoiceId: "a00INV000000NEG",
          invoiceName: "INV-NEG",
          historyVersion: 1,
          amountTotal: -1000,
          taxTotal: -100,
          taxInclusiveAmount: -1100,
          paymentNetTotal: 0,
          invoicePaymentNet: 0,
          invoiceTransactionStatus: "Confirmed",
          locked: false,
          lines: [
            {
              lineId: "a01LINE000000NEG",
              productName: "Neg",
              amount: -1000,
              historyVersionLabel: "V1",
              isRecurring: true,
              unitPrice: -1000,
              quantity: 1
            }
          ]
        }
      ]
    };
    document.body.appendChild(element);
    await Promise.resolve();

    const diffItem = Array.from(
      element.shadowRoot.querySelectorAll("footer.invoice-footer .money-item")
    ).find((item) =>
      item.querySelector(".money-label")?.textContent.includes("差額")
    );
    expect(diffItem).toBeTruthy();
    expect(
      Number(diffItem.querySelector("lightning-formatted-number").value)
    ).toBe(1100);
  });

  it("filters invoices by 差額あり and 差額なし", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = {
      canEdit: false,
      taxRoundingMode: "DOWN",
      sourceHistoryVersion: "1",
      versionOptions: [{ label: "V1", value: "1" }],
      invoices: [
        {
          invoiceId: "a00INV000000HAS",
          invoiceName: "INV-HAS",
          historyVersion: 1,
          amountTotal: 1000,
          taxTotal: 100,
          taxInclusiveAmount: 1100,
          paymentNetTotal: 0,
          invoicePaymentNet: 0,
          invoiceTransactionStatus: "Confirmed",
          locked: false,
          lines: [
            {
              lineId: "a01LINEHAS",
              productName: "Has",
              amount: 1000,
              historyVersionLabel: "V1",
              isRecurring: true,
              unitPrice: 1000,
              quantity: 1
            }
          ]
        },
        {
          invoiceId: "a00INV000000NONE",
          invoiceName: "INV-NONE",
          historyVersion: 1,
          amountTotal: 1000,
          taxTotal: 100,
          taxInclusiveAmount: 1100,
          paymentNetTotal: 1100,
          invoicePaymentNet: 1100,
          invoiceTransactionStatus: "Confirmed",
          locked: false,
          lines: [
            {
              lineId: "a01LINENONE",
              productName: "None",
              amount: 1000,
              historyVersionLabel: "V1",
              isRecurring: true,
              unitPrice: 1000,
              quantity: 1
            }
          ]
        }
      ]
    };
    document.body.appendChild(element);
    await Promise.resolve();

    expect(element.shadowRoot.textContent).toContain("INV-HAS");
    expect(element.shadowRoot.textContent).toContain("INV-NONE");

    const filter = element.shadowRoot.querySelector(
      'lightning-combobox[name="differenceFilter"]'
    );
    filter.dispatchEvent(
      new CustomEvent("change", { detail: { value: "HAS" } })
    );
    await Promise.resolve();
    expect(element.shadowRoot.textContent).toContain("INV-HAS");
    expect(element.shadowRoot.textContent).not.toContain("INV-NONE");

    filter.dispatchEvent(
      new CustomEvent("change", { detail: { value: "NONE" } })
    );
    await Promise.resolve();
    expect(element.shadowRoot.textContent).not.toContain("INV-HAS");
    expect(element.shadowRoot.textContent).toContain("INV-NONE");
  });

  it("shows acceptance end date input only for 一括計上 lines when Accounting is ON (Core 7.6)", async () => {
    getOpsBundle.mockResolvedValue({ accountingEnabled: true });
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = {
      canEdit: true,
      taxRoundingMode: "DOWN",
      sourceHistoryVersion: "1",
      versionOptions: [{ label: "V1", value: "1" }],
      invoices: [
        {
          invoiceId: "a00INV000000001",
          invoiceName: "INV-1",
          amountTotal: 2000,
          taxTotal: 200,
          taxPercent: 10,
          taxInclusiveAmount: 2200,
          locked: false,
          lines: [
            {
              lineId: "a01LINE00000001",
              productName: "Monthly",
              amount: 1000,
              historyVersionLabel: "V1",
              isRecurring: true,
              unitPrice: 1000,
              quantity: 1,
              revenueRecognitionBasis: "月次計上"
            },
            {
              lineId: "a01LINE00000002",
              productName: "Lump",
              amount: 1000,
              historyVersionLabel: "V1",
              isRecurring: false,
              unitPrice: 1000,
              quantity: 1,
              revenueRecognitionBasis: "一括計上",
              acceptanceEndDate: "2027-03-31"
            }
          ]
        }
      ]
    };
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();

    const dateInputs = element.shadowRoot.querySelectorAll(
      'td.acceptance-col lightning-input[type="date"]'
    );
    expect(dateInputs).toHaveLength(1);
    expect(dateInputs[0].dataset.lineId).toBe("a01LINE00000002");
    const cells = element.shadowRoot.querySelectorAll("td.acceptance-col");
    expect(cells).toHaveLength(2);
    expect(cells[0].textContent).toContain("—");
  });

  it("hides 検収終了日 when Accounting is OFF (Core 7.6)", async () => {
    getOpsBundle.mockResolvedValue({ accountingEnabled: false });
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = {
      canEdit: true,
      taxRoundingMode: "DOWN",
      sourceHistoryVersion: "1",
      versionOptions: [{ label: "V1", value: "1" }],
      invoices: [
        {
          invoiceId: "a00INV000000001",
          invoiceName: "INV-1",
          amountTotal: 1000,
          taxTotal: 100,
          taxPercent: 10,
          taxInclusiveAmount: 1100,
          locked: false,
          lines: [
            {
              lineId: "a01LINE00000002",
              productName: "Lump",
              amount: 1000,
              historyVersionLabel: "V1",
              isRecurring: false,
              unitPrice: 1000,
              quantity: 1,
              revenueRecognitionBasis: "一括計上",
              acceptanceEndDate: "2027-03-31"
            }
          ]
        }
      ]
    };
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();

    expect(
      element.shadowRoot.querySelectorAll("th.acceptance-col")
    ).toHaveLength(0);
    expect(
      element.shadowRoot.querySelectorAll("td.acceptance-col")
    ).toHaveLength(0);
    expect(
      element.shadowRoot.querySelectorAll(
        'td.acceptance-col lightning-input[type="date"]'
      )
    ).toHaveLength(0);
  });

  it("shows DueStatus and OverdueDays from preview (Core 7.11)", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = {
      canEdit: false,
      taxRoundingMode: "DOWN",
      sourceHistoryVersion: "1",
      versionOptions: [{ label: "版1", value: "1" }],
      invoices: [
        {
          invoiceId: "a00INV000000001",
          invoiceName: "INV-DUE",
          historyVersion: 1,
          amountTotal: 1000,
          taxTotal: 100,
          taxInclusiveAmount: 1100,
          invoiceTransactionStatus: "Confirmed",
          dueStatus: "遅延",
          overdueDays: 5,
          locked: false,
          lines: [
            {
              lineId: "a01LINE00000001",
              productName: "A",
              amount: 1000,
              historyVersionLabel: "版1",
              isRecurring: true,
              unitPrice: 1000,
              quantity: 1
            }
          ]
        }
      ]
    };
    document.body.appendChild(element);
    await Promise.resolve();

    const text = element.shadowRoot.textContent;
    expect(text).toContain("期限");
    expect(text).toContain("遅延");
    expect(text).toContain("5");
    expect(text).not.toContain("入金済");
    expect(text).not.toContain("延滞");
    expect(text).not.toContain("本日入金予定");
    expect(text).not.toContain("期限まで");
  });

  it("shows 端数調整実績 separately from ずれ (Core 7.8.5)", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = {
      canEdit: false,
      taxRoundingMode: "DOWN",
      sourceHistoryVersion: "1",
      periodLineAmountTotal: 10000,
      invoiceAmountTotal: 10003,
      manualAdjustmentAmount: 3,
      versionOptions: [
        {
          label: "版1",
          value: "1",
          periodLineAmountTotal: 10000,
          invoiceAmountTotal: 10003,
          manualAdjustmentAmount: 3
        }
      ],
      invoices: [
        {
          invoiceId: "a00INV000000001",
          invoiceName: "INV-1",
          historyVersion: 1,
          amountTotal: 10003,
          taxTotal: 1000,
          taxPercent: 10,
          taxInclusiveAmount: 11003,
          locked: false,
          lines: [
            {
              lineId: "a01LINE00000001",
              productName: "A",
              amount: 10003,
              historyVersionLabel: "版1",
              isRecurring: true,
              unitPrice: 10003,
              quantity: 1
            }
          ]
        }
      ]
    };
    document.body.appendChild(element);
    await Promise.resolve();

    const labels = Array.from(
      element.shadowRoot.querySelectorAll(".amount-compare-k")
    ).map((node) => node.textContent.trim());
    expect(labels).toEqual(["見積額", "調整後請求額", "ずれ", "端数調整実績"]);
    const compareValues = Array.from(
      element.shadowRoot.querySelectorAll(
        ".amount-compare lightning-formatted-number"
      )
    ).map((node) => Number(node.value));
    expect(compareValues[3]).toBe(3);
  });

  it("uses 版N when version option label is missing (Core 0.1)", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = {
      canEdit: false,
      taxRoundingMode: "DOWN",
      sourceHistoryVersion: "1",
      versionOptions: [{ value: "1" }],
      invoices: [
        {
          invoiceId: "a00INV000000001",
          invoiceName: "INV-1",
          historyVersion: 1,
          amountTotal: 1000,
          taxTotal: 100,
          taxInclusiveAmount: 1100,
          locked: false,
          lines: [
            {
              lineId: "a01LINE00000001",
              productName: "A",
              amount: 1000,
              historyVersionLabel: "版1",
              isRecurring: true,
              unitPrice: 1000,
              quantity: 1
            }
          ]
        }
      ]
    };
    document.body.appendChild(element);
    await Promise.resolve();

    const filter = element.shadowRoot.querySelector(
      'lightning-combobox[name="versionFilter"]'
    );
    expect(filter.options.map((option) => option.label)).toEqual([
      "全版",
      "版1"
    ]);
  });
});

describe("orderInvoicePreviewTable footer inclusive draft (Core 7.4 / 7.7.0)", () => {
  const proto = OrderInvoicePreviewTable.prototype;

  it("端数ドラフト中も請求書の税抜合計へ税率を1回適用し、明細ごと税の差は足さない", () => {
    const ctx = {
      preview: {
        taxRoundingMode: "DOWN",
        invoices: [
          {
            invoiceId: "a00INV000000001",
            historyVersion: "1",
            isCancelled: false,
            amountTotal: 10,
            taxTotal: 1,
            taxInclusiveAmount: 11,
            taxPercent: 10,
            lines: [
              { lineId: "a01LINE00000001", amount: 7 },
              { lineId: "a01LINE00000002", amount: 3 }
            ]
          }
        ]
      },
      amountDrafts: { a01LINE00000001: 6 },
      isCancelledInvoice: proto.isCancelledInvoice,
      isLineDrafted: proto.isLineDrafted,
      versionKeyForInvoice: proto.versionKeyForInvoice,
      computeInclusive: proto.computeInclusive,
      calculateTaxAmount: proto.calculateTaxAmount,
      roundTaxRaw: proto.roundTaxRaw,
      normalizeTaxPercent: proto.normalizeTaxPercent
    };
    // 保存 10+1=11。ドラフト税抜 9 へ税率1回 → 税0・税込9。差は -2。
    // 明細ごとなら (6+0)-(7+0) = -1 になり第7.4節が破れる。
    expect(proto.draftInclusiveDeltaForVersion.call(ctx, "ALL")).toBe(-2);
    expect(proto.draftInclusiveDeltaForVersion.call(ctx, "1")).toBe(-2);
  });
});

describe("orderInvoicePreviewTable lock note (Core 7.8 / 7.8.2 / 7.11)", () => {
  it("確定済みカードは確定済み・取消済みと書き、連携済または消込済とは書かない", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = {
      canEdit: true,
      taxRoundingMode: "DOWN",
      sourceHistoryVersion: "1",
      versionOptions: [{ label: "V1", value: "1" }],
      invoices: [
        {
          invoiceId: "a00INV000000001",
          invoiceName: "INV-1",
          locked: true,
          invoiceTransactionStatus: "Confirmed",
          amountTotal: 1000,
          taxTotal: 100,
          taxPercent: 10,
          taxInclusiveAmount: 1100,
          lines: [
            {
              lineId: "a01LINE00000001",
              productName: "Product",
              amount: 1000,
              historyVersionLabel: "V1"
            }
          ]
        }
      ]
    };
    document.body.appendChild(element);
    await Promise.resolve();
    expect(element.shadowRoot.textContent).toContain(
      "確定済み・取消済みの請求は編集できません。"
    );
    expect(element.shadowRoot.textContent).not.toContain("連携済または消込済");
  });
});
