import { createElement } from "lwc";
import OrderInvoicePreviewTable from "c/orderInvoicePreviewTable";
import LightningConfirm from "lightning/confirm";
import { openContentDocumentFilePreview } from "c/orderWizardNavigation";
import getOpsBundle from "@salesforce/apex/InvoicePreviewOpsController.getOpsBundle";
import issueInvoiceOperationKey from "@salesforce/apex/InvoicePreviewOpsController.issueInvoiceOperationKey";
import confirmInvoice from "@salesforce/apex/InvoiceSendBoardController.confirmInvoiceFromPreview";
import issueInvoiceDocument from "@salesforce/apex/InvoiceBoardDocumentService.issueFromPreview";
import previewIssueInvoice from "@salesforce/apex/InvoiceBoardDocumentService.previewIssueFromPreview";
import sendInvoice from "@salesforce/apex/InvoiceBoardDocumentService.sendFromPreview";
import previewInvoiceSend from "@salesforce/apex/InvoiceBoardDocumentService.previewFromPreview";
import updateInvoiceMemo from "@salesforce/apex/InvoiceOpsController.updateInvoiceMemo";
import savePaymentFromPreview from "@salesforce/apex/InvoicePreviewOpsController.savePaymentFromPreview";
import lockJournalsForInvoice from "@salesforce/apex/InvoicePreviewOpsController.lockJournalsForInvoice";
import unlockJournalsForInvoice from "@salesforce/apex/InvoicePreviewOpsController.unlockJournalsForInvoice";
import updateJournalMemo from "@salesforce/apex/InvoicePreviewOpsController.updateJournalMemo";
import previewCancelConfirmed from "@salesforce/apex/OrderCreateController.previewCancelConfirmed";
import previewCancelPaymentFromPreview from "@salesforce/apex/InvoicePreviewOpsController.previewCancelPaymentFromPreview";
import updatePaymentFromPreview from "@salesforce/apex/InvoicePreviewOpsController.updatePaymentFromPreview";
import previewInvoiceLineAcceptanceEndDate from "@salesforce/apex/OrderCreateController.previewInvoiceLineAcceptanceEndDate";
import getInvoiceOpsContext from "@salesforce/apex/InvoiceSendBoardController.getBoardContext";
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
  () => ({ default: jest.fn().mockResolvedValue({}) }),
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
    resolveScaledNumericInput: jest.fn((value) => Number(value)),
    roundUnitPrice: jest.fn((value) => Number(value)),
    setAmountCalculationRoundingModes: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardNavigation",
  () => ({
    NavigationMixin: (Base) => class extends Base {},
    openContentDocumentFilePreview: jest.fn()
  }),
  { virtual: true }
);

function confirmMock() {
  return LightningConfirm.open;
}

const proto = OrderInvoicePreviewTable.prototype;
const CONFIRMED = "a00INV000000001";
const DRAFT = "a00INV000000002";
const CANCELLED = "a00INV000000003";
const LINE_A = "a01LINE00000001";
const LINE_B = "a01LINE00000002";

function bind(overrides = {}) {
  const ctx = {
    selectedVersion: "ALL",
    selectedInvoiceId: "ALL",
    includeCancelled: false,
    includeCancelledPayments: false,
    invoiceCancelState: null,
    memoDrafts: {},
    journalMemoDrafts: {},
    journalLockSelected: {},
    journalLockAnchorByInvoice: {},
    journalUnlockReasonByInvoice: {},
    journalViewFilterByInvoice: {},
    journalFilterMenuByInvoice: {},
    journalToggleOpen: {},
    journalExtraDrafts: {},
    invoiceOpsFieldDefinitions: [],
    invoiceOpsFieldConfigError: "",
    invoiceSendState: null,
    invoiceIssueState: null,
    invoiceOpsProcessingId: null,
    invoiceOpsProcessingMode: null,
    invoiceUiState: {},
    amountDrafts: {},
    unitPriceFormulaLineId: null,
    unitPriceFormulaDraft: "",
    unitPriceFormulaError: "",
    unitPriceFormulaHint: "",
    billingEditState: null,
    invoiceSplitState: null,
    invoiceMoveState: null,
    invoiceDestinationChoiceState: null,
    lineSplitState: null,
    paymentEditState: null,
    isSaving: false,
    hideResetPostOrder: false,
    accountingEnabledOnBoard: true,
    invoiceSendFeatureEnabled: true,
    invoiceDocumentTemplateOptions: [{ label: "標準", value: "STD" }],
    invoiceEmailTemplateOptions: [{ label: "請求メール", value: "EM1" }],
    defaultInvoiceDocumentTemplateKey: "STD",
    defaultInvoiceEmailTemplateApiName: "EM1",
    companyBlockedReason: "",
    orgFromResolved: true,
    invoiceOpsContextError: "",
    billingAccountOptions: [{ id: "ba1", name: "BA1" }],
    contractHistoryId: "a0H000000000001AAA",
    completionNote: "",
    surfaceError: "",
    editProcessingInvoiceId: null,
    preview: null,
    dispatchEvent: jest.fn(),
    template: {
      addEventListener: jest.fn(),
      removeEventListener: jest.fn(),
      querySelector: jest.fn(() => null),
      host: {}
    },
    ...overrides
  };
  Object.getOwnPropertyNames(proto).forEach((name) => {
    if (name === "constructor" || name === "dispatchEvent") {
      return;
    }
    const desc = Object.getOwnPropertyDescriptor(proto, name);
    if (!desc || (desc.get && desc.set)) {
      return;
    }
    if (Object.prototype.hasOwnProperty.call(ctx, name)) {
      return;
    }
    if (desc.get && !desc.set) {
      Object.defineProperty(ctx, name, { get: desc.get, configurable: true });
    } else if (typeof desc.value === "function") {
      ctx[name] = desc.value;
    }
  });
  return ctx;
}

function line(id, extra = {}) {
  return {
    lineId: id,
    productName: extra.productName || "継続A",
    amount: 1000,
    historyVersions: [1],
    historyVersionLabel: "Version1",
    isRecurring: true,
    unitPrice: 1000,
    quantity: 1,
    unit: "式",
    periodLabel: "2026/4/1～2026/4/30",
    cycleCountLabel: "1",
    sourceAmountTotal: 1000,
    revenueRecognitionBasis: "一括計上",
    acceptanceEndDate: "2026-04-30",
    ...extra
  };
}

function preview() {
  return {
    canEdit: true,
    versionEditBlocked: false,
    invoiceSendMode: "PdfAndEmail",
    operationDay: "2026-09-11",
    taxRoundingMode: "DOWN",
    versionOptions: [
      {
        label: "Version1",
        value: "1",
        periodLineAmountTotal: 1000,
        invoiceAmountTotal: 1000
      },
      {
        label: "Version2",
        value: "2",
        periodLineAmountTotal: 2000,
        invoiceAmountTotal: 2000
      }
    ],
    invoices: [
      {
        invoiceId: CONFIRMED,
        invoiceName: "INV-1",
        invoiceDate: "2026-06-01",
        paymentScheduledDate: "2026-07-31",
        amountTotal: 1000,
        taxTotal: 100,
        taxPercent: 10,
        taxInclusiveAmount: 1100,
        invoicePaymentNet: 0,
        paymentNetTotal: 0,
        invoiceTransactionStatus: "Confirmed",
        invoiceDeliveryMethod: "Email",
        billingEmailTo: "to@example.com",
        billingEmailCc: "",
        billingEmailBcc: "",
        billingAccountId: "ba1",
        billingAccountName: "BA1",
        locked: true,
        isCancelled: false,
        historyVersion: 1,
        lastModifiedToken: "tok1",
        canConfirm: false,
        latestIssuedContentDocumentId: "069xxx",
        sentDate: "",
        lines: [line(LINE_A, { historyVersions: [1] })]
      },
      {
        invoiceId: DRAFT,
        invoiceName: "INV-2",
        invoiceDate: "2026-07-01",
        paymentScheduledDate: "2026-08-31",
        amountTotal: 2000,
        taxTotal: 200,
        taxPercent: 10,
        taxInclusiveAmount: 2200,
        invoicePaymentNet: 0,
        invoiceTransactionStatus: "Draft",
        invoiceDeliveryMethod: "Post",
        locked: false,
        isCancelled: false,
        historyVersion: 2,
        lastModifiedToken: "tok2",
        canConfirm: true,
        lines: [
          line(LINE_B, {
            productName: "継続B",
            historyVersions: [2],
            historyVersionLabel: "V2",
            sourceAmountTotal: 1990,
            isAmountAdjusted: true
          })
        ]
      },
      {
        invoiceId: CANCELLED,
        invoiceName: "INV-CXL",
        invoiceDate: "2026-05-01",
        amountTotal: 500,
        taxTotal: 50,
        taxPercent: 10,
        invoiceTransactionStatus: "Cancelled",
        isCancelled: true,
        historyVersion: 1,
        locked: true,
        lines: [line("a01LINE00000003", { historyVersionLabel: "Version1" })]
      }
    ]
  };
}

function journalBundle() {
  return {
    accountingEnabled: true,
    paymentAllowed: true,
    taxInclusiveAmount: 1100,
    invoicePaymentNet: 0,
    paymentNetTotal: 0,
    invoiceDate: "2026-06-01",
    invoiceToken: "token",
    hasLockedJournals: false,
    paymentLines: [
      { lineId: LINE_A, productName: "継続A", remainingInclusive: 1100 }
    ],
    payments: [
      {
        paymentId: "a0P000000000001",
        amount: 1100,
        paymentPurpose: "Invoice",
        paymentDate: "2026-07-01",
        paymentTransactionStatus: "Active",
        canCancel: true
      },
      {
        paymentId: "a0P000000000002",
        amount: -100,
        paymentPurpose: "NonInvoice",
        paymentDate: "2026-07-02",
        paymentTransactionStatus: "Cancelled",
        isCancelled: true
      }
    ],
    journals: [
      {
        journalId: "j1",
        postingDate: "2026-06-01",
        eventName: "売上",
        invoiceLineId: LINE_A,
        productName: "継続A",
        isLocked: false,
        transactionStatus: "Active",
        servicePeriodStartDate: "2026-04-01",
        servicePeriodEndDate: "2026-04-30"
      },
      {
        journalId: "j2",
        postingDate: "2026-07-01",
        eventName: "売上",
        invoiceLineId: LINE_A,
        productName: "継続A",
        isLocked: true,
        transactionStatus: "Active",
        servicePeriodStartDate: "2026-05-01",
        servicePeriodEndDate: "2026-05-31"
      },
      {
        journalId: "j3",
        postingDate: "2026-08-01",
        eventName: "入金",
        invoiceLineId: null,
        productName: "",
        isLocked: false,
        transactionStatus: "Reversal"
      }
    ],
    manualJournals: [{ headerId: "mj1", transactionStatus: "Active" }]
  };
}

describe("orderInvoicePreviewTable uncovered (Core 0.1 / 7.7.0 / 7.10)", () => {
  beforeEach(() => {
    getOpsBundle.mockReset().mockResolvedValue(journalBundle());
    issueInvoiceOperationKey.mockReset().mockResolvedValue("op-key-1");
    confirmInvoice.mockReset().mockResolvedValue({});
    issueInvoiceDocument.mockReset().mockResolvedValue({});
    previewIssueInvoice.mockReset().mockResolvedValue({
      fileName: "INV.pdf",
      documentTemplateKey: "STD"
    });
    sendInvoice.mockReset().mockResolvedValue({});
    previewInvoiceSend.mockReset().mockResolvedValue({
      toAddresses: "to@example.com",
      ccAddresses: "",
      bccAddresses: "",
      subject: "請求書",
      body: "本文",
      fileName: "INV.pdf",
      attachmentId: "NEW",
      attachmentOptions: [{ value: "NEW", fileName: "INV.pdf" }],
      newIssueFileName: "INV.pdf"
    });
    updateInvoiceMemo.mockReset().mockResolvedValue({});
    savePaymentFromPreview.mockReset().mockResolvedValue({});
    lockJournalsForInvoice.mockReset().mockResolvedValue({});
    unlockJournalsForInvoice.mockReset().mockResolvedValue({});
    previewCancelConfirmed.mockReset().mockResolvedValue({});
    updateJournalMemo.mockReset().mockResolvedValue({});
    previewCancelPaymentFromPreview.mockReset().mockResolvedValue({
      reverseCount: 0
    });
    updatePaymentFromPreview.mockReset().mockResolvedValue({});
    previewInvoiceLineAcceptanceEndDate.mockReset().mockResolvedValue({
      reverseCount: 0
    });
    getInvoiceOpsContext.mockReset().mockResolvedValue({
      featureEnabled: true,
      canSend: true,
      accountingEnabled: true,
      documentTemplateOptions: [{ label: "標準", value: "STD" }],
      emailTemplateOptions: [{ label: "請求メール", value: "EM1" }],
      defaultDocumentTemplateKey: "STD",
      defaultEmailTemplateApiName: "EM1",
      companyBlockedReason: "",
      orgFromResolved: true
    });
    getInvoiceOpsFieldDefinitions.mockReset().mockResolvedValue([]);
    if (!jest.isMockFunction(LightningConfirm.open)) {
      jest.spyOn(LightningConfirm, "open");
    }
    LightningConfirm.open.mockReset().mockResolvedValue(true);
    openContentDocumentFilePreview.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("印付き最新PDFがない請求には「最新のPDFを見る」を表示しない (Core 7.7.3 / 7.10)", () => {
    const data = preview();
    data.invoices.forEach((invoice) => {
      invoice.latestIssuedContentDocumentId = "";
    });
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = data;
    document.body.appendChild(element);

    const buttons = Array.from(
      element.shadowRoot.querySelectorAll("button")
    ).filter((button) => button.textContent.trim() === "最新のPDFを見る");
    expect(buttons).toHaveLength(0);
  });

  it("印付き最新PDFがある請求だけに正しいラベルを表示し、そのContentDocumentを標準Filesオーバーレイへ渡す (Core 7.7.3 / 7.10)", () => {
    const expectedDocumentId = "069000000000119AAA";
    const data = preview();
    data.invoices[0].latestIssuedContentDocumentId = expectedDocumentId;
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = data;
    document.body.appendChild(element);

    const buttons = Array.from(
      element.shadowRoot.querySelectorAll("button")
    ).filter((button) => button.textContent.trim() === "最新のPDFを見る");
    expect(buttons).toHaveLength(1);
    expect(buttons[0].dataset.invoiceId).toBe(CONFIRMED);

    buttons[0].click();

    expect(openContentDocumentFilePreview).toHaveBeenCalledTimes(1);
    expect(openContentDocumentFilePreview.mock.calls[0][1]).toBe(
      expectedDocumentId
    );
  });

  it("preview.invoiceOpsContext があるとき帳票設定を取り直さない (Core 第12.4節)", async () => {
    getInvoiceOpsContext.mockClear();
    const ctx = bind({
      preview: {
        invoiceOpsContext: {
          featureEnabled: true,
          accountingEnabled: true,
          documentTemplateOptions: [{ label: "標準", value: "STD" }],
          emailTemplateOptions: [{ label: "請求メール", value: "EM1" }],
          defaultDocumentTemplateKey: "STD",
          defaultEmailTemplateApiName: "EM1",
          companyBlockedReason: "",
          orgFromResolved: true
        }
      },
      invoiceSendFeatureEnabled: false,
      accountingEnabledOnBoard: false
    });
    await ctx.loadInvoiceOpsContext();
    expect(getInvoiceOpsContext).not.toHaveBeenCalled();
    expect(ctx.invoiceSendFeatureEnabled).toBe(true);
    expect(ctx.accountingEnabledOnBoard).toBe(true);
    expect(ctx.defaultInvoiceDocumentTemplateKey).toBe("STD");
  });

  it("版フィルタは全Versionと請求書がある VersionN。明細 Version 列は番号だけ (Core 0.1 / 7.7.0)", () => {
    const ctx = bind({ preview: preview() });
    const options = ctx.versionOptions;
    expect(options[0]).toEqual({ label: "全Version", value: "ALL" });
    expect(options.map((row) => row.label)).toEqual([
      "全Version",
      "Version1",
      "Version2"
    ]);
    expect(options.map((row) => row.label).join()).not.toMatch(/バージョン/);
    expect(ctx.formatLineVersionCell({ historyVersions: [1] })).toBe("1");
    expect(ctx.formatLineVersionCell({ historyVersionLabel: "Version2" })).toBe(
      "2"
    );
    expect(ctx.formatLineVersionCell({ historyVersionLabel: "V3" })).toBe("3");
    expect(ctx.formatLineVersionCell({})).toBe("—");
    const cards = ctx.invoiceCards;
    const confirmed = cards.find((card) => card.invoiceId === CONFIRMED);
    expect(confirmed.lines[0].versionLabel).toBe("1");
    expect(confirmed.lines[0].versionLabel).not.toBe("Version1");
    expect(confirmed.lines[0].versionLabel).not.toBe("V1");
    expect(cards.some((card) => card.invoiceId === CANCELLED)).toBe(false);
  });

  it("親 Version を変えると子は全請求書へ戻す。未保存端数中は切替を止める (Core 7.7.0 / 7.7.1)", () => {
    const ctx = bind({
      preview: preview(),
      selectedVersion: "ALL",
      selectedInvoiceId: CONFIRMED
    });
    ctx.handleVersionChange({ detail: { value: "1" } });
    expect(ctx.selectedVersion).toBe("1");
    expect(ctx.selectedInvoiceId).toBe("ALL");
    ctx.amountDrafts = { [LINE_B]: 1999 };
    ctx.handleVersionChange({ detail: { value: "2" } });
    expect(ctx.selectedVersion).toBe("1");
    expect(ctx.surfaceError).toContain("未保存の端数調整があります");
  });

  it("取消済みは明示したときだけ出し、カードに差額フィルタは出さない (Core 7.7.0)", () => {
    const ctx = bind({ preview: preview(), includeCancelled: true });
    const cards = ctx.invoiceCards;
    const cancelled = cards.find((card) => card.invoiceId === CANCELLED);
    expect(cancelled).toBeTruthy();
    expect(ctx.transactionStatusLabel("Cancelled")).toBe("取消済み");
    expect(ctx.transactionStatusLabel("Confirmed")).toBe("確定済み");
    expect(ctx.transactionStatusLabel("Draft")).toBe("未確定");
    expect(ctx.invoiceFilterOptions.map((row) => row.label)).toContain(
      "全請求書"
    );
    ctx.handleIncludeCancelledChange({ target: { checked: false } });
    expect(ctx.includeCancelled).toBe(false);
  });

  it("仕訳・入金付きカードと発行送付ゲートを組み立てる (Core 7.10 / 7.11 / Accounting 10.3)", () => {
    const data = preview();
    const ctx = bind({
      preview: data,
      accountingEnabledOnBoard: true,
      includeCancelledPayments: true,
      invoiceUiState: {
        [CONFIRMED]: {
          activeTab: "journals",
          bundle: journalBundle(),
          loading: false,
          error: "",
          paymentDraft: {
            invoiceId: CONFIRMED,
            amount: "1100",
            purpose: "Invoice",
            paymentDate: "2026-09-11",
            memo: "",
            extraFieldValues: {},
            allocations: [
              { lineId: LINE_A, productName: "継続A", amount: 1100 }
            ]
          }
        }
      },
      journalLockSelected: { [CONFIRMED]: { j1: true } },
      journalViewFilterByInvoice: {
        [CONFIRMED]: { postingMonth: ["2026-06"], eventName: [], lineKey: [] }
      },
      invoiceIssueState: { invoiceId: CONFIRMED, documentTemplateKey: "STD" },
      invoiceSendState: {
        invoiceId: CONFIRMED,
        documentTemplateKey: "STD",
        attachmentId: "NEW",
        fileName: "INV.pdf"
      }
    });
    const cards = ctx.invoiceCards;
    const confirmed = cards.find((card) => card.invoiceId === CONFIRMED);
    expect(confirmed).toBeTruthy();
    expect(ctx.deliveryStatusLabel("Sent")).toBe("送付済");
    expect(ctx.deliveryStatusLabel("Unsent")).toBe("未送付");
    expect(ctx.deliveryStatusLabel("NotApplicable")).toBe("対象外");
    expect(ctx.sentDateDisplay("", "Unsent")).toBe("未送付");
    expect(ctx.paymentPurposeLabel("Invoice")).toBe("請求金額");
    expect(ctx.paymentPurposeLabel("NonInvoice")).toBe("請求金額以外");
    expect(ctx.journalTransactionStatusLabel("Active")).toBeTruthy();
    expect(ctx.manualJournalStatusLabel("Active")).toBe("有効");
    expect(ctx.manualJournalStatusLabel("Cancelled")).toBe("取消済");
    expect(ctx.invoiceIssueUnavailableReason(true, false)).toBe("");
    expect(ctx.invoiceSendUnavailableReason(data.invoices[0], true, false)).toBe(
      ""
    );
  });

  it("同一請求内分割のカード枝と数式ラベル (Core 7.8)", () => {
    const ctx = bind({
      preview: preview(),
      selectedVersion: "2",
      lineSplitState: {
        invoiceId: DRAFT,
        loadingThresholds: false,
        rows: {
          [LINE_B]: {
            selected: true,
            kind: "unitPrice",
            moveUnitPrice: "500",
            moveQuantity: ""
          }
        },
        thresholdsByLineId: { [LINE_B]: [] }
      }
    });
    const cards = ctx.invoiceCards;
    const draft = cards.find((card) => card.invoiceId === DRAFT);
    expect(draft.lines[0].splitSelected).toBe(true);
    expect(draft.lines[0].versionLabel).toBe("2");
    expect(ctx.isSplitOrMoveUiOpen).toBe(true);
  });

  it("受注直後に戻す確認は Accounting ON だけ検収終了日を名指しする (Core 7.7.2 / 0.2)", async () => {
    const data = preview();
    data.invoices[1].invoiceTransactionStatus = "Draft";
    const ctx = bind({
      preview: data,
      selectedVersion: "2",
      accountingEnabledOnBoard: true
    });
    expect(ctx.resetPostOrderConfirmMessage()).toContain("検収終了日");
    const off = bind({
      preview: data,
      selectedVersion: "2",
      accountingEnabledOnBoard: false,
      invoiceUiState: {}
    });
    expect(off.resetPostOrderConfirmMessage()).not.toContain("検収終了日");
    expect(off.resetPostOrderConfirmMessage()).toContain("受注直後の状態に作り直します");
    await ctx.handleResetPostOrderClick();
    expect(confirmMock()).toHaveBeenCalled();
    expect(ctx.dispatchEvent).toHaveBeenCalled();
  });

  it("確定は実行前確認を出さない。発行は確定済みだけ (Core 0.2 / 7.9 / 7.10)", async () => {
    const data = preview();
    data.invoices[1].canConfirm = true;
    const ctx = bind({
      preview: data,
      invoiceUiState: {
        [DRAFT]: { pendingOperationKey: "", bundle: journalBundle() }
      }
    });
    await ctx.handleConfirmInvoice({
      currentTarget: { dataset: { invoiceId: DRAFT } }
    });
    expect(confirmMock()).not.toHaveBeenCalled();
    expect(confirmInvoice).toHaveBeenCalled();
    ctx.invoiceIssueState = {
      invoiceId: CONFIRMED,
      documentTemplateKey: "STD"
    };
    await ctx.handleSubmitInvoiceIssue();
    expect(issueInvoiceDocument).toHaveBeenCalled();
    expect(ctx.completionNote).toBe("請求書を発行しました。");
  });

  it("初回送付は重ねず、再送だけ確認する (Core 0.2 / 7.10)", async () => {
    const data = preview();
    const ctx = bind({
      preview: data,
      orgFromResolved: true,
      invoiceSendState: {
        invoiceId: CONFIRMED,
        documentTemplateKey: "STD",
        emailTemplateApiName: "EM1",
        toAddresses: "to@example.com",
        ccAddresses: "",
        bccAddresses: "",
        subject: "請求",
        body: "本文",
        fileName: "INV.pdf",
        attachmentId: "NEW"
      }
    });
    await ctx.handleSendInvoice();
    expect(confirmMock()).not.toHaveBeenCalled();
    expect(sendInvoice).toHaveBeenCalled();
    ctx.invoiceOpsProcessingId = null;
    ctx.invoiceSendState = {
      invoiceId: CONFIRMED,
      documentTemplateKey: "STD",
      emailTemplateApiName: "EM1",
      toAddresses: "to@example.com",
      ccAddresses: "",
      bccAddresses: "",
      subject: "請求",
      body: "本文",
      fileName: "INV.pdf",
      attachmentId: "NEW"
    };
    data.invoices[0].sentDate = "2026-09-01";
    confirmMock().mockResolvedValue(true);
    await ctx.handleSendInvoice();
    expect(confirmMock()).toHaveBeenCalled();
    expect(confirmMock().mock.calls[0][0].message).toContain(
      "失敗のあと送り直すと、先のメールが届いていることがある"
    );
  });

  it("発行PDFはダウンロードURLを出し、権限不足は編集拒否文 (Core 7.10 / 7.7.0)", () => {
    const ctx = bind({ preview: preview() });
    ctx.openIssuedFilePreview("069xxx");
    expect(ctx.issuedPdfDownloadUrl("069x")).toContain("069x");
    const blocked = bind({
      preview: { ...preview(), canEdit: false }
    });
    expect(blocked.editBlockedMessage).toBe("この操作の権限がありません。");
  });

  it("読み直しでメモ・入金取消・請求取消の未保存下書きを戻さない (Core 7.7.0)", () => {
    const ctx = bind({
      memoDrafts: { [CONFIRMED]: "下書きメモ" },
      journalMemoDrafts: { a03JOURNAL: "未保存の仕訳メモ" },
      invoiceCancelState: {
        invoiceId: CONFIRMED,
        cancellationReason: "Duplicate"
      },
      invoiceUiState: {
        [CONFIRMED]: {
          activeTab: "payments",
          bundle: null,
          loading: false,
          error: "",
          paymentDraft: null,
          cancelDraft: {
            paymentId: "a02PAY000000001",
            cancellationReason: "Duplicate"
          }
        }
      },
      invoiceSendState: { invoiceId: CONFIRMED },
      invoiceIssueState: { invoiceId: CONFIRMED },
      amountDrafts: { a01: 1 },
      loadOpsBundle: jest.fn()
    });
    ctx._preview = preview();
    ctx.resetPreviewDraftState();
    ctx.initializeInvoiceUiState();
    expect(ctx.memoDrafts).toEqual({});
    expect(ctx.journalMemoDrafts).toEqual({});
    expect(ctx.invoiceCancelState).toBeNull();
    expect(ctx.invoiceSendState).toBeNull();
    expect(ctx.invoiceIssueState).toBeNull();
    expect(ctx.amountDrafts).toEqual({});
    expect(ctx.invoiceUiState[CONFIRMED].cancelDraft).toBeNull();
    expect(ctx.invoiceUiState[CONFIRMED].paymentDraft).toEqual(
      expect.objectContaining({ purpose: "Invoice" })
    );
  });

  it("メモ保存・タブ・フィルタ・入金割当の未踏経路 (Core 7.7.3 / 8.3)", async () => {
    const ctx = bind({
      preview: preview(),
      invoiceUiState: {
        [CONFIRMED]: {
          bundle: journalBundle(),
          paymentDraft: {
            invoiceId: CONFIRMED,
            amount: "500",
            purpose: "Invoice",
            paymentDate: "2026-09-11",
            extraFieldValues: {},
            allocations: []
          }
        }
      },
      memoDrafts: { [CONFIRMED]: "メモ" }
    });
    await ctx.handleSaveMemo({
      currentTarget: { dataset: { invoiceId: CONFIRMED } }
    });
    expect(updateInvoiceMemo).toHaveBeenCalled();
    expect(ctx.completionNote).toBe("メモを保存しました。");
    ctx.handleInvoiceTabClick({
      currentTarget: { dataset: { invoiceId: CONFIRMED, tab: "payments" } }
    });
    expect(ctx.invoiceUiState[CONFIRMED].activeTab).toBe("payments");
    ctx.handleInvoiceFilterChange({ detail: { value: CONFIRMED } });
    expect(ctx.selectedInvoiceId).toBe(CONFIRMED);
    ctx.handleIncludeCancelledPaymentsChange({ target: { checked: true } });
    expect(ctx.includeCancelledPayments).toBe(true);
    await ctx.loadOpsBundle(CONFIRMED);
    expect(getOpsBundle).toHaveBeenCalled();
    ctx.handlePaymentDraftChange({
      target: { dataset: { invoiceId: CONFIRMED, field: "amount" } },
      detail: { value: "400" }
    });
    expect(ctx.invoiceUiState[CONFIRMED].paymentDraft.amount).toBe("400");
    ctx.handleOpenInvoiceRedirect({
      currentTarget: { dataset: { invoiceId: DRAFT } }
    });
    expect(ctx.invoiceSplitState.invoiceId).toBe(DRAFT);
    ctx.handleInvoiceSplitDateChange({ detail: { value: "2026-10-01" } });
    ctx.handleInvoiceSplitPaymentChange({ detail: { value: "2026-10-31" } });
    expect(ctx.invoiceSplitState.newInvoiceDate).toBe("2026-10-01");
    ctx.handleCloseInvoiceSplit();
    expect(ctx.invoiceSplitState).toBe(null);
  });

  it("ラベル・丸め・税のヘルパ (Core 0.1 / 11.9)", () => {
    const ctx = bind({ preview: preview() });
    expect(ctx.formatSignedYen(100)).toBe("+¥100");
    expect(ctx.formatSignedYen(-3)).toBe("-¥3");
    expect(ctx.formatSignedYen(0)).toBe("¥0");
    expect(ctx.formatYen(1000)).toMatch(/1,000|¥/);
    expect(ctx.formatThresholdDateLabel("2026-06-01")).toBe("2026/6/1");
    expect(ctx.truncTowardZero(1.9)).toBe(1);
    expect(ctx.truncTowardZero(-1.9)).toBe(-1);
    expect(ctx.isWithinLineRemaining(10, 10)).toBe(true);
    expect(ctx.hasInvalidEmailList("bad")).toBe(true);
    expect(ctx.hasInvalidEmailList("ok@example.com")).toBe(false);
    expect(ctx.isBlankReasonText("")).toBe(true);
    expect(ctx.documentTemplateLabel("STD")).toBe("標準");
    expect(ctx.emailTemplateLabel("EM1")).toBe("請求メール");
    expect(ctx.calculateTaxAmount(1000, 10)).toBe(100);
    ctx.handleSurfaceErrorReload();
    expect(ctx.dispatchEvent).toHaveBeenCalled();
    ctx.disconnectedCallback();
  });

  it("発行送付パネル・入金・Lock・分割・請求情報の未踏経路 (Core 7.10 / 8.3 / 7.8)", async () => {
    const ctx = bind({
      preview: preview(),
      invoiceUiState: {
        [CONFIRMED]: {
          bundle: journalBundle(),
          paymentDraft: {
            invoiceId: CONFIRMED,
            amount: "1100",
            purpose: "Invoice",
            paymentDate: "2026-09-11",
            memo: "",
            extraFieldValues: {},
            allocations: [
              { lineId: LINE_A, productName: "継続A", amount: 1100 }
            ]
          },
          pendingOperationKey: "op-existing"
        }
      },
      journalLockSelected: { [CONFIRMED]: { j1: true } }
    });
    await ctx.handleIssueInvoice({
      currentTarget: { dataset: { invoiceId: CONFIRMED } }
    });
    expect(previewIssueInvoice).toHaveBeenCalled();
    ctx.handleCloseInvoiceIssue();
    await ctx.handleOpenInvoiceSend({
      currentTarget: { dataset: { invoiceId: CONFIRMED } }
    });
    expect(previewInvoiceSend).toHaveBeenCalled();
    ctx.handleInvoiceSendDraftChange({
      target: { name: "subject", value: "件名" },
      detail: { value: "件名" }
    });
    ctx.handleInvoiceAttachmentChange({ detail: { value: "NEW" } });
    await ctx.handleInvoiceEmailTemplateChange({
      detail: { value: "EM1" },
      target: {}
    });
    await ctx.handlePaymentSave({
      currentTarget: { dataset: { invoiceId: CONFIRMED } }
    });
    expect(savePaymentFromPreview).toHaveBeenCalled();
    await ctx.lockSelectedOrRefuse(CONFIRMED, ["j1"]);
    expect(lockJournalsForInvoice).toHaveBeenCalled();
    ctx.handleOpenBillingEdit({
      currentTarget: { dataset: { invoiceId: DRAFT } }
    });
    expect(ctx.billingEditState.invoiceId).toBe(DRAFT);
    ctx.handleBillingFieldChange({
      target: { dataset: { field: "invoiceDate" } },
      detail: { value: "2026-08-01" }
    });
    ctx.handleCloseBillingEdit();
    ctx.invoiceSplitState = {
      invoiceId: DRAFT,
      newInvoiceDate: "2026-10-01",
      newPaymentDate: "2026-10-31",
      newBillingAccountId: "ba1",
      selected: { [LINE_B]: true }
    };
    await ctx.handleConfirmInvoiceSplit();
    expect(ctx.dispatchEvent).toHaveBeenCalled();
    ctx.handleJournalFilterBulk({
      currentTarget: {
        dataset: { invoiceId: CONFIRMED, filter: "eventName", bulk: "all" }
      }
    });
    ctx.handleJournalViewFilterToggle({
      currentTarget: {
        dataset: { invoiceId: CONFIRMED, filter: "eventName", value: "売上" }
      },
      target: { dataset: {}, checked: false },
      detail: { checked: true }
    });
    ctx.handleJournalBarUnlockReasonChange({
      target: { dataset: { invoiceId: CONFIRMED } },
      detail: { value: "監査" }
    });
    expect(ctx.journalUnlockReasonByInvoice[CONFIRMED]).toBe("監査");
    await ctx.loadInvoiceOpsContext();
    await ctx.loadInvoiceOpsFieldDefinitions();
    expect(getInvoiceOpsContext).toHaveBeenCalled();
    ctx.handleOpenPaymentEdit({
      currentTarget: {
        dataset: { invoiceId: CONFIRMED, paymentId: "a0P000000000001" }
      }
    });
    ctx.handleClosePaymentEdit();
    ctx.handleAdjustAmount({
      currentTarget: { dataset: { lineId: LINE_B, delta: "1" } }
    });
    ctx.handleDiscardAmountDrafts();
    ctx.handleManualJournalComplete();
    ctx.lineSplitState = {
      invoiceId: DRAFT,
      loadingThresholds: false,
      rows: {
        [LINE_B]: {
          selected: true,
          kind: "unitPrice",
          moveUnitPrice: "500",
          moveQuantity: ""
        }
      },
      thresholdsByLineId: { [LINE_B]: [] }
    };
    await ctx.handleConfirmLineSplit();
    ctx.invoiceMoveState = {
      invoiceId: DRAFT,
      targetInvoiceId: CONFIRMED,
      selected: { [LINE_B]: true }
    };
    await ctx.handleConfirmInvoiceMove();
    ctx.journalLockSelected = { [CONFIRMED]: { j2: true } };
    await ctx.unlockSelectedFromBar(CONFIRMED, ["j2"]);
    ctx.invoiceUiState = {
      ...ctx.invoiceUiState,
      [CONFIRMED]: {
        ...(ctx.invoiceUiState[CONFIRMED] || {}),
        bundle: {
          payments: [],
          manualJournals: [],
          journals: []
        }
      }
    };
    ctx.invoiceCancelState = {
      invoiceId: CONFIRMED,
      cancellationReason: "AmountOrDateError",
      cancellationReasonText: "",
      cancellationDate: ""
    };
    await ctx.handleConfirmInvoiceCancel();
    expect(previewCancelConfirmed).toHaveBeenCalled();
    ctx.invoiceUiState = {
      ...ctx.invoiceUiState,
      [CONFIRMED]: {
        ...(ctx.invoiceUiState[CONFIRMED] || {}),
        bundle: journalBundle()
      }
    };
    ctx.handleJournalMemoChange({
      target: { dataset: { journalId: "j1" } },
      detail: { value: "メモ" }
    });
    ctx.handleToggleJournalExtras({
      currentTarget: { dataset: { journalId: "j1" } }
    });
    expect(ctx.journalToggleOpen.j1).toBe(true);
    ctx.handleJournalExtraChange({
      target: { dataset: { journalId: "j1", field: "Note__c" } },
      detail: { value: "x" }
    });
    ctx.handleJournalLockPointer({ shiftKey: false });
    ctx.handleJournalLockToggle({
      currentTarget: {
        dataset: { invoiceId: CONFIRMED, journalId: "j1" }
      },
      target: { dataset: {}, checked: false },
      detail: { checked: true }
    });
    await ctx.handleSaveJournalMemo({
      currentTarget: { dataset: { journalId: "j1", invoiceId: CONFIRMED } }
    });
    ctx.handleOpenBillingEdit({
      currentTarget: { dataset: { invoiceId: DRAFT } }
    });
    ctx.billingEditState = {
      ...ctx.billingEditState,
      invoiceDate: "2026-08-01",
      paymentScheduledDate: "2026-08-31"
    };
    await ctx.handleSaveBillingHeader();
  });

  it("分割・移動・入金取消・検収・帳票変更の未踏経路 (Core 7.8 / 7.6 / 7.10)", async () => {
    const draftB = "a00INV000000004";
    const data = preview();
    data.invoices[1].billingAccountId = "ba1";
    data.invoices.push({
      invoiceId: draftB,
      invoiceName: "INV-3",
      invoiceDate: "2026-08-01",
      paymentScheduledDate: "2026-09-30",
      amountTotal: 500,
      taxTotal: 50,
      taxPercent: 10,
      taxInclusiveAmount: 550,
      invoicePaymentNet: 0,
      invoiceTransactionStatus: "Draft",
      invoiceDeliveryMethod: "Email",
      locked: false,
      isCancelled: false,
      historyVersion: 2,
      lastModifiedToken: "tok3",
      canConfirm: true,
      billingAccountId: "ba1",
      lines: [
        line("a01LINE00000004", {
          productName: "継続C",
          historyVersions: [2],
          amount: 500,
          sourceAmountTotal: 500
        })
      ]
    });
    const ctx = bind({
      preview: data,
      amountDrafts: {},
      invoiceOpsProcessingId: null,
      invoiceUiState: {
        [CONFIRMED]: {
          bundle: journalBundle(),
          paymentDraft: {
            invoiceId: CONFIRMED,
            amount: "100",
            purpose: "Invoice",
            paymentDate: "2026-09-11",
            extraFieldValues: {},
            allocations: []
          }
        },
        [DRAFT]: { bundle: null, paymentDraft: null },
        [draftB]: { bundle: null, paymentDraft: null }
      },
      journalUnlockReasonByInvoice: { [CONFIRMED]: "監査のためUnlock" },
      journalLockSelected: { [CONFIRMED]: { j2: true } },
      journalMemoDrafts: { j1: "仕訳メモ" }
    });

    expect(ctx.formatJournalAmount(1234)).toMatch(/1,234|¥/);
    expect(ctx.formatJournalAmount(null)).toBe("");
    expect(ctx.selectedJournalIds(CONFIRMED)).toEqual(["j2"]);
    await ctx.unlockSelectedFromBar(CONFIRMED, ["j2"]);
    expect(unlockJournalsForInvoice).toHaveBeenCalled();

    await ctx.handleSaveJournalMemo({
      currentTarget: { dataset: { journalId: "j1", invoiceId: CONFIRMED } }
    });
    expect(updateJournalMemo).toHaveBeenCalled();

    ctx.invoiceSendState = {
      invoiceId: CONFIRMED,
      documentTemplateKey: "STD",
      emailTemplateApiName: "EM1",
      attachmentId: "NEW",
      fileName: "INV.pdf"
    };
    await ctx.handleInvoiceDocumentTemplateChange({
      detail: { value: "STD2" },
      target: {}
    });
    expect(previewInvoiceSend).toHaveBeenCalled();

    ctx.paymentEditState = {
      invoiceId: CONFIRMED,
      paymentId: "a0P000000000001",
      memo: "旧",
      paymentPurpose: "Invoice",
      storedExtraFieldValues: {},
      extraFieldValues: {}
    };
    ctx.handlePaymentEditFieldChange({
      target: { dataset: {} },
      detail: { value: "新メモ" }
    });
    await ctx.handleSavePaymentEdit();
    expect(updatePaymentFromPreview).toHaveBeenCalled();

    await ctx.handlePaymentCancel({
      currentTarget: {
        dataset: { invoiceId: CONFIRMED, paymentId: "a0P000000000001" }
      }
    });
    expect(previewCancelPaymentFromPreview).toHaveBeenCalled();
    ctx.handlePaymentCancelDraftChange({
      target: { dataset: { invoiceId: CONFIRMED, field: "cancellationReason" } },
      detail: { value: "Duplicate" }
    });
    ctx.handlePaymentCancelClose({
      currentTarget: { dataset: { invoiceId: CONFIRMED } }
    });

    ctx.invoiceOpsProcessingId = null;
    ctx.lineSplitState = null;
    ctx.invoiceSplitState = null;
    ctx.invoiceMoveState = null;
    ctx.billingEditState = null;
    ctx.amountDrafts = {};
    ctx.lineSplitState = {
      invoiceId: DRAFT,
      loadingThresholds: false,
      rows: {
        [LINE_B]: {
          selected: true,
          kind: "unitPrice",
          moveUnitPrice: "400",
          moveQuantity: ""
        }
      },
      thresholdsByLineId: { [LINE_B]: [] }
    };
    ctx.handleLineSplitKindClick({
      currentTarget: { dataset: { lineId: LINE_B, kind: "quantity" } }
    });
    expect(ctx.lineSplitState.rows[LINE_B].kind).toBe("quantity");
    ctx.handleLineSplitMoveQuantityChange({
      target: { dataset: { lineId: LINE_B } },
      detail: { value: "0.5" }
    });
    await ctx.handleConfirmLineSplit();

    ctx.lineSplitState = null;
    ctx.amountDrafts = {};
    ctx.editProcessingInvoiceId = null;
    ctx.invoiceMoveState = {
      invoiceId: DRAFT,
      targetInvoiceId: draftB,
      selected: { [LINE_B]: true }
    };
    await ctx.handleConfirmInvoiceMove();
    expect(ctx.dispatchEvent).toHaveBeenCalled();

    ctx.invoiceMoveState = {
      invoiceId: DRAFT,
      targetInvoiceId: draftB,
      selected: {}
    };
    ctx.handleCloseInvoiceMove();
    expect(ctx.invoiceMoveState).toBe(null);

    ctx.invoiceOpsProcessingId = null;
    ctx.editProcessingInvoiceId = null;
    ctx.isSaving = false;
    ctx.billingEditState = null;
    ctx.invoiceSplitState = null;
    ctx.invoiceMoveState = null;
    ctx.lineSplitState = null;
    ctx.updateInvoiceUiState(DRAFT, {
      acceptanceDraft: {
        lineId: LINE_B,
        nextDate: "2026-05-31",
        cancellationDate: "2026-09-11",
        requiresDate: false
      }
    });
    ctx.handleAcceptanceCancelDraftChange({
      target: { dataset: { invoiceId: DRAFT } },
      detail: { value: "2026-09-12" }
    });
    await ctx.handleAcceptanceCancelSave({
      currentTarget: { dataset: { invoiceId: DRAFT } }
    });
    expect(previewInvoiceLineAcceptanceEndDate).toHaveBeenCalled();
    ctx.handleAcceptanceCancelClose({
      currentTarget: { dataset: { invoiceId: DRAFT } }
    });

    ctx.amountDrafts = { [LINE_B]: 2001 };
    await ctx.handleSaveAmountDrafts();
    ctx.handleDiscardAmountDrafts();
    expect(ctx.hasAmountDrafts).toBe(false);

    ctx.handleApplyBillingAccountContent({
      currentTarget: { dataset: { invoiceId: DRAFT } }
    });
    ctx.updateInvoiceUiState(CONFIRMED, {
      bundle: {
        payments: [],
        manualJournals: [],
        journals: [],
        hasLockedJournals: false
      }
    });
    await ctx.handleOpenInvoiceCancel({
      currentTarget: { dataset: { invoiceId: CONFIRMED } }
    });
    expect(ctx.invoiceCancelState.invoiceId).toBe(CONFIRMED);
    ctx.handleCancelFieldChange({
      target: { dataset: { field: "cancellationReason" } },
      detail: { value: "Duplicate" }
    });
    ctx.handleCloseInvoiceCancel();
  });
});
