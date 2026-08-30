import { createElement } from "lwc";
import OrderInvoicePreviewTable from "c/orderInvoicePreviewTable";
import getOpsBundle from "@salesforce/apex/InvoicePreviewOpsController.getOpsBundle";
import getInvoiceOpsFieldDefinitions from "@salesforce/apex/InvoiceOpsFieldService.getDefinitions";

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
      accountingEnabled: true,
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
  "@salesforce/apex/InvoiceBoardDocumentService.previewFromPreview",
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
  "@salesforce/apex/InvoiceOpsController.updateInvoiceMemo",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoicePreviewOpsController.issueInvoiceOperationKey",
  () => ({ default: jest.fn().mockResolvedValue("op-key-1") }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoicePreviewOpsController.getOpsBundle",
  () => ({ default: jest.fn() }),
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
  "@salesforce/apex/InvoicePreviewOpsController.updatePaymentFromPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/InvoiceOpsFieldService.getDefinitions",
  () => ({ default: jest.fn().mockResolvedValue([]) }),
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

function buildPreview(invoiceOverrides) {
  return {
    canEdit: true,
    sourceHistoryVersion: "1",
    operationDay: "2026-08-29",
    taxRoundingMode: "DOWN",
    versionOptions: [{ label: "V1", value: "1" }],
    invoices: [
      {
        invoiceId: "a00INV000000001",
        invoiceName: "INV-1",
        invoiceDate: "2026-06-01",
        paymentScheduledDate: "2026-07-31",
        amountTotal: 1000,
        taxTotal: 100,
        taxPercent: 10,
        taxInclusiveAmount: 1100,
        invoicePaymentNet: 0,
        invoiceTransactionStatus: "Confirmed",
        invoiceDeliveryMethod: "Email",
        locked: true,
        isCancelled: false,
        lines: [],
        ...invoiceOverrides
      }
    ]
  };
}

async function flush() {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

describe("orderInvoicePreviewTable extra fields (Core 11.4.4 / 7.8 / Accounting 9.1.1)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("確定済みでも請求情報編集ボタンを出す (Core 7.8 / 11.4.4)", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    const buttons = Array.from(element.shadowRoot.querySelectorAll("button"));
    const billing = buttons.find(
      (button) => button.textContent.trim() === "請求情報編集"
    );
    expect(billing).toBeTruthy();
    const split = buttons.find(
      (button) => button.textContent.trim() === "別の請求へ分ける"
    );
    expect(split).toBeFalsy();
  });

  it("取消済み請求は請求情報編集を出さない (Core 7.8 / 11.4.4)", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview({
      invoiceTransactionStatus: "Cancelled",
      isCancelled: true
    });
    document.body.appendChild(element);
    await flush();
    const includeCancelled = element.shadowRoot.querySelector(
      'lightning-input[label="取消済みを含める"]'
    );
    includeCancelled.checked = true;
    includeCancelled.dispatchEvent(new CustomEvent("change"));
    await flush();
    const billing = Array.from(element.shadowRoot.querySelectorAll("button")).find(
      (button) => button.textContent.trim() === "請求情報編集"
    );
    expect(billing).toBeFalsy();
  });

  it("仕訳タブの表列に確認用を常時出さない (Accounting 9.1.1 / Core 11.4.4)", async () => {
    getInvoiceOpsFieldDefinitions.mockResolvedValue([]);
    getOpsBundle.mockResolvedValue({
      accountingEnabled: true,
      paymentAllowed: true,
      taxInclusiveAmount: 1100,
      invoicePaymentNet: 0,
      paymentNetTotal: 0,
      invoiceDate: "2026-06-01",
      invoiceToken: "token",
      hasLockedJournals: false,
      payments: [],
      paymentLines: [],
      journals: [
        {
          journalId: "a03JNL000000001",
          eventKey: "BILLING_CONFIRMED",
          eventName: "請求確定",
          amount: 1100,
          postingDate: "2026-06-01",
          transactionStatus: "Active",
          isLocked: false,
          memo: "",
          confirmationText: "明細税抜 1,100円"
        }
      ],
      manualJournals: []
    });
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    const journalsTab = Array.from(
      element.shadowRoot.querySelectorAll("button[data-tab='journals']")
    )[0];
    journalsTab.click();
    await flush();
    const headerText = Array.from(
      element.shadowRoot.querySelectorAll(".ops-table thead th")
    )
      .map((th) => th.textContent.trim())
      .join(" ");
    expect(headerText).not.toContain("確認用");
    expect(element.shadowRoot.textContent).not.toContain("明細税抜 1,100円");
  });
});
