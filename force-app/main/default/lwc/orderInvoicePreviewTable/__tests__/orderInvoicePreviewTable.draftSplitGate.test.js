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

const LINE_ID = "a01LINE00000001";
const INVOICE_ID = "a00INV000000001";

function buildEditablePreview() {
  return {
    canEdit: true,
    taxRoundingMode: "DOWN",
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

async function flushMicrotasks(times = 5) {
  for (let i = 0; i < times; i++) {
    await Promise.resolve();
  }
}

describe("orderInvoicePreviewTable draft/split gate", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("disables ± after opening 別の請求へ分ける", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildEditablePreview();
    document.body.appendChild(element);
    await Promise.resolve();

    const openSplit = findButtonByText(element, "別の請求へ分ける");
    expect(openSplit).toBeTruthy();
    expect(openSplit.disabled).toBe(false);
    expect(findButtonByText(element, "請求を分ける")).toBeFalsy();
    expect(findButtonByText(element, "明細を移す")).toBeFalsy();
    openSplit.click();
    await Promise.resolve();

    const plus10 = element.shadowRoot.querySelector('button[data-delta="10"]');
    expect(plus10).toBeTruthy();
    expect(plus10.disabled).toBe(true);
  });

  it("新しい請求へ分けるパネルは元請求の日付・BAを埋めない (Core 7.8 / 1.1.10)", () => {
    const target = {
      updateInvoiceUiState() {},
      handleCloseLineSplit() {},
      invoiceMoveState: { keep: true },
      invoiceDestinationChoiceState: { keep: true }
    };
    OrderInvoicePreviewTable.prototype.openInvoiceSplitPanel.call(
      target,
      "a00INV000000001"
    );
    expect(target.invoiceSplitState).toEqual({
      invoiceId: "a00INV000000001",
      newInvoiceDate: "",
      newPaymentDate: "",
      newBillingAccountId: "",
      allowOtherAccountBilling: false,
      selected: {}
    });
  });

  it("blocks opening 別の請求へ分ける while unsaved ± drafts exist", async () => {
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

    const openSplit = findButtonByText(element, "別の請求へ分ける");
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
    await flushMicrotasks();

    let plus10 = element.shadowRoot.querySelector('button[data-delta="10"]');
    expect(plus10.disabled).toBe(true);

    splitChip.click();
    await Promise.resolve();

    plus10 = element.shadowRoot.querySelector('button[data-delta="10"]');
    expect(plus10.disabled).toBe(false);
  });

  it("shows new-or-existing choice when another draft exists in the same Version", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    const preview = buildEditablePreview();
    preview.invoices[0].historyVersion = "1";
    preview.invoices[0].invoiceTransactionStatus = "Draft";
    preview.invoices.push({
      ...preview.invoices[0],
      invoiceId: "a00INV000000002",
      invoiceName: "INV-2",
      invoiceDate: "2026-05-01"
    });
    element.preview = preview;
    document.body.appendChild(element);
    await Promise.resolve();

    findButtonByText(element, "別の請求へ分ける").click();
    await Promise.resolve();

    expect(findButtonByText(element, "新しい請求を作る")).toBeTruthy();
    expect(findButtonByText(element, "既存の未確定へ移す")).toBeTruthy();
    findButtonByText(element, "新しい請求を作る").click();
    await Promise.resolve();

    expect(element.shadowRoot.textContent).toContain("分割先の請求書");
    expect(findButtonByText(element, "新しい請求を作る")).toBeFalsy();
  });

  it("enables 新しい請求を作る when selected lines are negative (Core 7.8)", async () => {
    const preview = buildEditablePreview();
    preview.invoices[0].amountTotal = -10000;
    preview.invoices[0].paymentScheduledDate = "2026-05-01";
    preview.invoices[0].invoiceTransactionStatus = "Draft";
    preview.invoices[0].lines[0].amount = -10000;
    preview.invoices[0].lines[0].unitPrice = -10000;

    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = preview;
    document.body.appendChild(element);
    await Promise.resolve();

    findButtonByText(element, "別の請求へ分ける").click();
    await Promise.resolve();

    const saveBefore = [...element.shadowRoot.querySelectorAll("button")].find(
      (btn) => btn.textContent.trim() === "保存"
    );
    expect(saveBefore).toBeTruthy();
    expect(saveBefore.disabled).toBe(true);
    expect(
      element.shadowRoot.querySelector(
        `lightning-input[data-line-id="${LINE_ID}"]`
      )
    ).toBeTruthy();
  });
});
