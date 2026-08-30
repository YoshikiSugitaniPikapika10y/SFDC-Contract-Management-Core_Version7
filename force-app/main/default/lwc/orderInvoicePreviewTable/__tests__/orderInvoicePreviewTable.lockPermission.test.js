import { createElement } from "lwc";
import OrderInvoicePreviewTable from "c/orderInvoicePreviewTable";

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

function mount(preview, permissionOverrides) {
  const element = createElement("c-order-invoice-preview-table", {
    is: OrderInvoicePreviewTable
  });
  if (permissionOverrides && Object.prototype.hasOwnProperty.call(permissionOverrides, "canLockJournal")) {
    Object.defineProperty(element, "canLockJournal", {
      get: () => permissionOverrides.canLockJournal
    });
  }
  if (permissionOverrides && Object.prototype.hasOwnProperty.call(permissionOverrides, "canUnlockJournal")) {
    Object.defineProperty(element, "canUnlockJournal", {
      get: () => permissionOverrides.canUnlockJournal
    });
  }
  element.accountingEnabledOnBoard = true;
  element.preview = preview;
  document.body.appendChild(element);
  return element;
}

describe("orderInvoicePreviewTable journal lock permissions (Accounting 第9.5節 / 共通基盤 第10.4節 / Core 第7.7.3節)", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows Lock and Unlock when each dedicated permission is present", async () => {
    const element = mount(buildPreview());
    await flush();
    const card = element.invoiceCards[0];
    expect(card.showJournalLockButton).toBe(true);
    expect(card.showJournalUnlockButton).toBe(true);
    expect(card.showJournalLockActions).toBe(true);
  });

  it("hides Lock when Loop_16 is absent and does not let Unlock stand in", async () => {
    const element = mount(buildPreview(), {
      canLockJournal: false,
      canUnlockJournal: true
    });
    await flush();
    const card = element.invoiceCards[0];
    expect(card.showJournalLockButton).toBe(false);
    expect(card.showJournalUnlockButton).toBe(true);
    expect(card.showJournalLockActions).toBe(true);
  });

  it("hides Unlock when Loop_17 is absent and does not let Lock stand in", async () => {
    const element = mount(buildPreview(), {
      canLockJournal: true,
      canUnlockJournal: false
    });
    await flush();
    const card = element.invoiceCards[0];
    expect(card.showJournalLockButton).toBe(true);
    expect(card.showJournalUnlockButton).toBe(false);
    expect(card.showJournalLockActions).toBe(true);
  });

  it("hides Lock and Unlock when neither dedicated permission is present", async () => {
    const element = mount(buildPreview(), {
      canLockJournal: false,
      canUnlockJournal: false
    });
    await flush();
    const card = element.invoiceCards[0];
    expect(card.showJournalLockButton).toBe(false);
    expect(card.showJournalUnlockButton).toBe(false);
    expect(card.showJournalLockActions).toBe(false);
  });

  it("hides Lock and Unlock on cancelled invoices even with both permissions", async () => {
    const element = mount(
      buildPreview({
        invoiceTransactionStatus: "Cancelled",
        isCancelled: true
      })
    );
    await flush();
    const card = element.invoiceCards[0];
    expect(card.showJournalLockButton).toBe(false);
    expect(card.showJournalUnlockButton).toBe(false);
    expect(card.showJournalLockActions).toBe(false);
  });

  it("hides Lock and Unlock when Accounting is OFF", async () => {
    const element = mount(buildPreview());
    element.accountingEnabledOnBoard = false;
    await flush();
    const card = element.invoiceCards[0];
    expect(card.accountingEnabled).toBe(false);
    expect(card.showJournalLockButton).toBe(false);
    expect(card.showJournalUnlockButton).toBe(false);
    expect(card.showJournalLockActions).toBe(false);
  });
});
