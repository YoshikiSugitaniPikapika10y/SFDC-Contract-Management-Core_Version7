import { createElement } from "lwc";
import OrderInvoicePreviewTable from "c/orderInvoicePreviewTable";
import getOpsBundle from "@salesforce/apex/InvoicePreviewOpsController.getOpsBundle";
import savePaymentFromPreview from "@salesforce/apex/InvoicePreviewOpsController.savePaymentFromPreview";
import updatePaymentFromPreview from "@salesforce/apex/InvoicePreviewOpsController.updatePaymentFromPreview";
import previewRegisterFromPreview from "@salesforce/apex/InvoicePreviewOpsController.previewRegisterFromPreview";
import previewCancelConfirmed from "@salesforce/apex/OrderCreateController.previewCancelConfirmed";
import previewCancelPaymentFromPreview from "@salesforce/apex/InvoicePreviewOpsController.previewCancelPaymentFromPreview";
import previewInvoiceLineAcceptanceEndDate from "@salesforce/apex/OrderCreateController.previewInvoiceLineAcceptanceEndDate";
import getBoardContext from "@salesforce/apex/InvoiceSendBoardController.getBoardContext";
import LightningConfirm from "lightning/confirm";

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
  "@salesforce/apex/OrderCreateController.previewInvoiceLineAcceptanceEndDate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/ManualJournalController.register",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/ManualJournalController.cancel",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/ManualJournalController.previewCancel",
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
  () => {
    const open = jest.fn();
    return {
      __esModule: true,
      default: { open },
      open
    };
  },
  { virtual: true }
);

function buildPreview() {
  return {
    canEdit: false,
    sourceHistoryVersion: "1",
    operationDay: "2026-08-29",
    taxRoundingMode: "DOWN",
    versionOptions: [{ label: "V1", value: "1" }],
    invoices: [
      {
        invoiceId: "a00INV000000001",
        invoiceName: "INV-1",
        invoiceDate: "2026-06-01",
        amountTotal: 1000,
        taxTotal: 100,
        taxPercent: 10,
        taxInclusiveAmount: 1100,
        invoicePaymentNet: 0,
        invoiceTransactionStatus: "Confirmed",
        invoiceDeliveryMethod: "Email",
        locked: false,
        lines: [
          {
            lineId: "a01LINE00000001",
            productName: "Product",
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
}

function mockBundle({
  hasLockedJournals = false,
  accountingEnabled = false,
  payments,
  journals,
  manualJournals
} = {}) {
  return {
    accountingEnabled,
    paymentAllowed: true,
    taxInclusiveAmount: 1100,
    invoicePaymentNet: 0,
    paymentNetTotal: 0,
    invoiceDate: "2026-06-01",
    invoiceToken: "token",
    hasLockedJournals,
    payments: payments || [
      {
        paymentId: "a02PAY000000001",
        amount: 200,
        displayAmount: 200,
        paymentPurpose: "Invoice",
        paymentDate: "2026-06-10",
        memo: "",
        canCancel: true,
        lastModifiedToken: "pay-token"
      }
    ],
    paymentLines: [
      {
        lineId: "a01LINE00000001",
        productName: "Product",
        remainingInclusive: 1100
      }
    ],
    journals: journals || [],
    manualJournals: manualJournals || []
  };
}

async function flush() {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

async function waitUntil(predicate, attempts = 50) {
  let last;
  for (let i = 0; i < attempts; i += 1) {
    last = predicate();
    if (last) {
      return last;
    }
    await Promise.resolve();
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  return last;
}

async function openPaymentsTab(element) {
  const tab = await waitUntil(
    () => element.shadowRoot.querySelector("button[data-tab='payments']")
  );
  tab.click();
  await flush();
}

async function openJournalsTab(element) {
  const tab = await waitUntil(
    () => element.shadowRoot.querySelector("button[data-tab='journals']")
  );
  tab.click();
  await flush();
}

describe("orderInvoicePreviewTable payment form", () => {
  beforeEach(() => {
    savePaymentFromPreview.mockClear();
    previewRegisterFromPreview.mockClear();
    updatePaymentFromPreview.mockClear();
    previewCancelPaymentFromPreview.mockClear();
    previewCancelConfirmed.mockClear();
    previewInvoiceLineAcceptanceEndDate.mockClear();
    LightningConfirm.open.mockClear();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("defaults Purpose Invoice, signed unpaid net, and locks final-settlement allocations", async () => {
    getOpsBundle.mockResolvedValue(mockBundle());
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    const amountInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="amount"]'
    );
    const purposeInput = element.shadowRoot.querySelector(
      'lightning-combobox[data-field="purpose"]'
    );
    expect(purposeInput.value).toBe("Invoice");
    expect(String(amountInput.value)).toBe("1100");
    const allocationInput = element.shadowRoot.querySelector(
      'lightning-input[data-line-id="a01LINE00000001"]'
    );
    expect(allocationInput).toBeTruthy();
    expect(allocationInput.disabled).toBe(true);
    expect(element.shadowRoot.textContent).not.toContain("削除");
  });

  it("shows overflow guidance and does not auto-change Purpose", async () => {
    getOpsBundle.mockResolvedValue(mockBundle());
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    const amountInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="amount"]'
    );
    amountInput.dispatchEvent(
      new CustomEvent("change", { detail: { value: "1500" } })
    );
    await flush();

    expect(element.shadowRoot.textContent).toContain("登録上限を超えています");
    expect(element.shadowRoot.textContent).toContain("請求金額以外");
    expect(element.shadowRoot.textContent).toContain("目的:");
    expect(element.shadowRoot.textContent).not.toContain("Purpose:");
    const saveButton = Array.from(
      element.shadowRoot.querySelectorAll("button.solid-btn")
    ).find((button) => button.textContent.trim() === "追加");
    expect(saveButton.disabled).toBe(true);
    const purposeInput = element.shadowRoot.querySelector(
      'lightning-combobox[data-field="purpose"]'
    );
    expect(purposeInput.value).toBe("Invoice");
  });

  it("shows sign mismatch on the payment form, not as a hover title", async () => {
    getOpsBundle.mockResolvedValue(mockBundle());
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    const amountInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="amount"]'
    );
    amountInput.dispatchEvent(
      new CustomEvent("change", { detail: { value: "-100" } })
    );
    await flush();

    expect(element.shadowRoot.textContent).toContain(
      "金額の符号が登録可能額と一致していません"
    );
    expect(element.shadowRoot.textContent).toContain("目的:");
    expect(element.shadowRoot.textContent).toContain("登録可能額:");
    expect(element.shadowRoot.textContent).toContain("入力額:");
    expect(element.shadowRoot.textContent).not.toContain("超過額:");
    const saveButton = Array.from(
      element.shadowRoot.querySelectorAll("button.solid-btn")
    ).find((button) => button.textContent.trim() === "追加");
    expect(saveButton.disabled).toBe(true);
    expect(saveButton.title).toBeFalsy();
  });

  it("does not note empty or zero payment amount", async () => {
    getOpsBundle.mockResolvedValue(mockBundle());
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    const amountInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="amount"]'
    );
    amountInput.dispatchEvent(
      new CustomEvent("change", { detail: { value: "" } })
    );
    await flush();
    expect(element.shadowRoot.textContent).not.toContain(
      "金額の符号が登録可能額と一致していません"
    );
    amountInput.dispatchEvent(
      new CustomEvent("change", { detail: { value: "0" } })
    );
    await flush();
    expect(element.shadowRoot.textContent).not.toContain(
      "未処理額が0のため"
    );
    expect(element.shadowRoot.textContent).not.toContain(
      "金額の符号が登録可能額と一致していません"
    );
  });

  it("notes Invoice purpose when unpaid net is 0 and amount is filled", async () => {
    getOpsBundle.mockResolvedValue({
      ...mockBundle(),
      invoicePaymentNet: 1100
    });
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    const preview = buildPreview();
    preview.invoices[0].invoicePaymentNet = 1100;
    element.preview = preview;
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    const amountInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="amount"]'
    );
    amountInput.dispatchEvent(
      new CustomEvent("change", { detail: { value: "100" } })
    );
    await flush();
    expect(element.shadowRoot.textContent).toContain(
      "未処理額が0のため、目的「請求金額」では登録できません"
    );
    expect(element.shadowRoot.textContent).not.toContain("超過額:");
    const saveButton = Array.from(
      element.shadowRoot.querySelectorAll("button.solid-btn")
    ).find((button) => button.textContent.trim() === "追加");
    expect(saveButton.disabled).toBe(true);
    expect(saveButton.title).toBeFalsy();
  });

  it("shows cancel date only when locked journals exist", async () => {
    getOpsBundle.mockResolvedValue(mockBundle({ hasLockedJournals: false }));
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    element.shadowRoot
      .querySelector("button[data-payment-id='a02PAY000000001']")
      .click();
    await flush();

    expect(element.shadowRoot.textContent).toContain("入出金を取消");
    expect(element.shadowRoot.textContent).toContain("INV-1");
    expect(
      element.shadowRoot.querySelector('lightning-input[data-field="cancelDate"]')
    ).toBeNull();
  });

  it("hides cancelled payments by default and shows 有効／取消済み／取消 when included", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({
        payments: [
          {
            paymentId: "a02PAY000000001",
            amount: 200,
            displayAmount: 200,
            paymentPurpose: "Invoice",
            paymentDate: "2026-06-10",
            memo: "active",
            paymentTransactionStatus: "Active",
            canCancel: true,
            lastModifiedToken: "pay-token"
          },
          {
            paymentId: "a02PAY000000002",
            amount: 200,
            displayAmount: 200,
            paymentPurpose: "Invoice",
            paymentDate: "2026-06-11",
            memo: "cancelled-original",
            paymentTransactionStatus: "Cancelled",
            isCancelled: true,
            canCancel: false,
            lastModifiedToken: "pay-token-2"
          },
          {
            paymentId: "a02PAY000000003",
            amount: -200,
            displayAmount: -200,
            paymentPurpose: "Invoice",
            paymentDate: "2026-06-11",
            memo: "reversal",
            paymentTransactionStatus: "Reversal",
            isCancellation: true,
            canCancel: false,
            lastModifiedToken: "pay-token-3"
          }
        ]
      })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    let rows = element.shadowRoot.querySelectorAll(
      ".ops-table-wrap .ops-table tbody tr"
    );
    expect(rows).toHaveLength(1);
    expect(rows[0].textContent).toContain("有効");
    expect(element.shadowRoot.textContent).not.toContain("cancelled-original");
    expect(element.shadowRoot.textContent).not.toContain("reversal");

    const include = element.shadowRoot.querySelector(
      ".ops-panel lightning-input"
    );
    include.checked = true;
    include.dispatchEvent(new CustomEvent("change"));
    await flush();

    rows = element.shadowRoot.querySelectorAll(
      ".ops-table-wrap .ops-table tbody tr"
    );
    expect(rows).toHaveLength(3);
    const statusLabels = Array.from(rows).map((row) =>
      row.querySelectorAll("td")[4].textContent.trim()
    );
    expect(statusLabels).toEqual(["有効", "取消済み", "取消"]);
  });

  it("shows journal event names and Japanese transaction statuses", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({
        accountingEnabled: true,
        journals: [
          {
            journalId: "a03JNL000000001",
            eventKey: "BILLING_CONFIRMED",
            eventName: "請求確定",
            debitAccountName: "売掛金",
            creditAccountName: "売上",
            amount: 1100,
            postingDate: "2026-06-01",
            transactionStatus: "Active",
            isLocked: false,
            memo: ""
          },
          {
            journalId: "a03JNL000000002",
            eventKey: "BILLING_CANCELLED",
            eventName: "請求取消",
            debitAccountName: "売上",
            creditAccountName: "売掛金",
            amount: 1100,
            postingDate: "2026-06-02",
            transactionStatus: "Reversal",
            isLocked: false,
            memo: ""
          },
          {
            journalId: "a03JNL000000003",
            eventKey: "PAYMENT_RECORDED",
            eventName: "請求入出金登録（Purpose=Invoice／NonInvoiceと符号付きAmountを含む）",
            debitAccountName: "現預金",
            creditAccountName: "売掛金",
            amount: 1100,
            postingDate: "2026-06-03",
            transactionStatus: "LogicallyDeleted",
            isLocked: false,
            memo: ""
          },
          {
            journalId: "a03JNL000000004",
            eventKey: "MANUAL_JOURNAL",
            eventName: "手動仕訳",
            debitAccountName: "費用",
            creditAccountName: "現預金",
            amount: 100,
            postingDate: "2026-06-04",
            transactionStatus: "Cancelled",
            isLocked: false,
            memo: ""
          }
        ]
      })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openJournalsTab(element);

    const text = element.shadowRoot.textContent;
    expect(text).toContain("請求確定");
    expect(text).not.toContain("BILLING_CONFIRMED");
    const journalRows = () =>
      element.shadowRoot.querySelectorAll(
        ".ops-panel .ops-table-wrap .ops-table tbody tr"
      );
    const statuses = Array.from(journalRows()).map((row) =>
      row.querySelectorAll("td")[8].textContent.trim()
    );
    expect(statuses).toEqual(["有効", "取消", "取消済"]);
    const periods = Array.from(journalRows()).map((row) =>
      row.querySelectorAll("td")[7].textContent.trim()
    );
    expect(periods).toEqual(["到来済み", "到来済み", "到来済み"]);
    expect(
      element.shadowRoot.querySelector(".journal-filters")
    ).toBeNull();
    const journalHeads = Array.from(
      element.shadowRoot.querySelectorAll(
        ".ops-panel .ops-table_journals thead th"
      )
    ).map((head) => head.textContent.trim());
    expect(journalHeads).toContain("イベント");
    expect(journalHeads).not.toContain("パターン");
    expect(element.shadowRoot.textContent).toContain("計上時期");
    expect(element.shadowRoot.textContent).not.toContain("確認用");
    expect(journalRows()[1].className).toContain("journal-row_audit");
    expect(journalRows()[2].className).toContain("journal-row_audit");
  });

  it("shows Lock selection checkbox only for Active journals", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({
        accountingEnabled: true,
        journals: [
          {
            journalId: "a03JNL000000001",
            eventKey: "BILLING_CONFIRMED",
            eventName: "請求確定",
            debitAccountName: "売掛金",
            creditAccountName: "売上",
            amount: 1100,
            postingDate: "2026-06-01",
            transactionStatus: "Active",
            isLocked: false,
            memo: ""
          },
          {
            journalId: "a03JNL000000005",
            eventKey: "BILLING_CONFIRMED",
            eventName: "請求確定",
            debitAccountName: "売掛金",
            creditAccountName: "売上",
            amount: 200,
            postingDate: "2026-06-01",
            transactionStatus: "Active",
            isLocked: false,
            memo: ""
          },
          {
            journalId: "a03JNL000000002",
            eventKey: "BILLING_CANCELLED",
            eventName: "請求取消",
            debitAccountName: "売上",
            creditAccountName: "売掛金",
            amount: 1100,
            postingDate: "2026-06-02",
            transactionStatus: "Reversal",
            isLocked: true,
            memo: ""
          },
          {
            journalId: "a03JNL000000003",
            eventKey: "PAYMENT_RECORDED",
            eventName: "請求入出金登録",
            debitAccountName: "現預金",
            creditAccountName: "売掛金",
            amount: 1100,
            postingDate: "2026-06-03",
            transactionStatus: "LogicallyDeleted",
            isLocked: false,
            memo: ""
          },
          {
            journalId: "a03JNL000000004",
            eventKey: "MANUAL_JOURNAL",
            eventName: "手動仕訳",
            debitAccountName: "費用",
            creditAccountName: "現預金",
            amount: 100,
            postingDate: "2026-06-04",
            transactionStatus: "Cancelled",
            isLocked: true,
            memo: ""
          }
        ]
      })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openJournalsTab(element);

    const rows = Array.from(
      element.shadowRoot.querySelectorAll(
        ".ops-panel .ops-table-wrap .ops-table tbody tr"
      )
    );
    expect(rows).toHaveLength(4);
    const checkboxes = rows.map((row) =>
      row.querySelector("td.split-select-col lightning-input")
    );
    expect(checkboxes[0]).toBeTruthy();
    expect(checkboxes[0].dataset.journalId).toBe("a03JNL000000001");
    expect(checkboxes[1]).toBeTruthy();
    expect(checkboxes[1].dataset.journalId).toBe("a03JNL000000005");
    expect(checkboxes[2]).toBeNull();
    expect(checkboxes[3]).toBeNull();
  });

  it("labels journal posting period against organization operation day", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({
        accountingEnabled: true,
        journals: [
          {
            journalId: "a03JNL000000001",
            eventKey: "BILLING_CONFIRMED",
            eventName: "請求確定",
            debitAccountName: "売掛金",
            creditAccountName: "売上",
            amount: 1100,
            postingDate: "2020-01-16",
            transactionStatus: "Active",
            isLocked: false,
            memo: ""
          },
          {
            journalId: "a03JNL000000002",
            eventKey: "BILLING_CONFIRMED",
            eventName: "請求確定",
            debitAccountName: "売掛金",
            creditAccountName: "売上",
            amount: 1100,
            postingDate: "2020-01-15",
            transactionStatus: "Active",
            isLocked: false,
            memo: ""
          }
        ]
      })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    const preview = buildPreview();
    preview.operationDay = "2020-01-15";
    element.preview = preview;
    document.body.appendChild(element);
    await flush();
    await openJournalsTab(element);

    const periods = Array.from(
      element.shadowRoot.querySelectorAll(
        ".ops-panel .ops-table-wrap .ops-table tbody tr"
      )
    ).map((row) => row.querySelectorAll("td")[7].textContent.trim());
    expect(periods).toEqual(["到来済み", "将来"]);
  });

  it("does not filter journals by accounting event", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({
        accountingEnabled: true,
        journals: [
          {
            journalId: "a03JNL000000001",
            eventKey: "BILLING_CONFIRMED",
            eventName: "請求確定",
            debitAccountName: "売掛金",
            creditAccountName: "売上",
            amount: 1100,
            postingDate: "2026-06-01",
            transactionStatus: "Active",
            isLocked: false,
            memo: ""
          },
          {
            journalId: "a03JNL000000002",
            eventKey: "MANUAL_JOURNAL",
            eventName: "手動仕訳",
            debitAccountName: "費用",
            creditAccountName: "現預金",
            amount: 100,
            postingDate: "2026-06-04",
            transactionStatus: "Active",
            isLocked: false,
            memo: ""
          }
        ]
      })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openJournalsTab(element);

    const rows = element.shadowRoot.querySelectorAll(
      ".ops-panel .ops-table-wrap .ops-table tbody tr"
    );
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain("請求確定");
    expect(rows[1].textContent).toContain("手動仕訳");
  });

  it("seeds invoice cancel date to the operation day when locked journals exist", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ hasLockedJournals: true, payments: [] })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();

    const cancelButton = Array.from(
      element.shadowRoot.querySelectorAll("button.ghost-btn")
    ).find(
      (button) =>
        button.textContent.trim() === "取消" && button.dataset.invoiceId
    );
    cancelButton.click();
    await flush();

    const dateInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="cancellationDate"]'
    );
    expect(dateInput).not.toBeNull();
    expect(dateInput.label).toBe("取消基準日");
    expect(dateInput.value).toBe("2026-08-29");
  });

  it("omits invoice cancel date when there are no locked journals", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ hasLockedJournals: false, payments: [] })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();

    const cancelButton = Array.from(
      element.shadowRoot.querySelectorAll("button.ghost-btn")
    ).find(
      (button) =>
        button.textContent.trim() === "取消" && button.dataset.invoiceId
    );
    cancelButton.click();
    await flush();

    expect(
      element.shadowRoot.querySelector(
        'lightning-input[data-field="cancellationDate"]'
      )
    ).toBeNull();
  });

  it("omits payment register cancel date when the invoice only has other locked journals", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: true, hasLockedJournals: true })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    expect(
      element.shadowRoot.querySelector(
        'lightning-input[data-field="cancellationDate"]'
      )
    ).toBeNull();
  });

  it("omits payment register cancel date when Accounting is off even if locked journals exist", async () => {
    getBoardContext.mockResolvedValue({
      featureEnabled: false,
      canSend: true,
      accountingEnabled: false,
      documentTemplateOptions: [],
      emailTemplateOptions: []
    });
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: false, hasLockedJournals: true })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    expect(
      element.shadowRoot.querySelector(
        'lightning-input[data-field="cancellationDate"]'
      )
    ).toBeNull();
  });

  it("hides journals tab when Accounting is off", async () => {
    getBoardContext.mockResolvedValue({
      featureEnabled: false,
      canSend: true,
      accountingEnabled: false,
      documentTemplateOptions: [],
      emailTemplateOptions: []
    });
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: false })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();

    const journalsTab = Array.from(
      element.shadowRoot.querySelectorAll("button.invoice-tab")
    ).find((button) => button.textContent.trim() === "仕訳");
    expect(journalsTab).toBeUndefined();
    expect(element.shadowRoot.textContent).not.toContain(
      "仕訳連携は停止中です"
    );
  });

  it("omits payment register cancel date when there are no locked journals", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: true, hasLockedJournals: false })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    expect(
      element.shadowRoot.querySelector(
        'lightning-input[data-field="cancellationDate"]'
      )
    ).toBeNull();
  });

  it("asks for payment register cancel date after preview finds reversals", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: true, hasLockedJournals: true })
    );
    previewRegisterFromPreview.mockResolvedValue({
      reverseCount: 1,
      displayText: "逆仕訳件数: 1"
    });
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    const saveButton = Array.from(
      element.shadowRoot.querySelectorAll("button.solid-btn")
    ).find((button) => button.textContent.trim() === "追加");
    saveButton.click();
    await flush();
    await flush();

    expect(savePaymentFromPreview).not.toHaveBeenCalled();
    const dateInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="cancellationDate"]'
    );
    expect(dateInput).not.toBeNull();
    expect(dateInput.label).toBe("逆仕訳基準日");
    expect(dateInput.value).toBe("2026-08-29");
    expect(element.shadowRoot.textContent).toContain(
      "ロック済み仕訳を打ち消すときの基準日です。仕訳に付く日付は、ここで指定した日と元の仕訳の日付のうち遅い方になります。"
    );
  });

  it("omits invoice cancel date when only cancelled locked journals exist", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({
        hasLockedJournals: true,
        payments: [],
        journals: [
          {
            journalId: "a03JRN000000001",
            isLocked: true,
            transactionStatus: "Cancelled"
          }
        ]
      })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();

    const cancelButton = Array.from(
      element.shadowRoot.querySelectorAll("button.ghost-btn")
    ).find(
      (button) =>
        button.textContent.trim() === "取消" && button.dataset.invoiceId
    );
    cancelButton.click();
    await flush();

    expect(
      element.shadowRoot.querySelector(
        'lightning-input[data-field="cancellationDate"]'
      )
    ).toBeNull();
  });

  it("does not open invoice cancel confirm and still previews cancel (Core 0.2)", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ hasLockedJournals: false, payments: [] })
    );
    previewCancelConfirmed.mockClear();
    LightningConfirm.open.mockClear();
    previewCancelConfirmed.mockResolvedValue({
      logicalDeleteCount: 1,
      reverseCount: 2,
      hasFutureReverseDate: true,
      displayText:
        "論理削除件数: 1\n逆仕訳件数: 2\n実際の逆仕訳日:\n2026-08-28: 2件\n将来日付: あり"
    });
    LightningConfirm.open.mockResolvedValue(true);
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();

    const cancelButton = Array.from(
      element.shadowRoot.querySelectorAll("button.ghost-btn")
    ).find(
      (button) =>
        button.textContent.trim() === "取消" && button.dataset.invoiceId
    );
    cancelButton.click();
    await flush();

    const reason = element.shadowRoot.querySelector(
      'lightning-combobox[data-field="cancellationReason"]'
    );
    reason.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Duplicate" } })
    );
    await flush();

    Array.from(element.shadowRoot.querySelectorAll("button.solid-btn"))
      .find((button) => button.textContent.trim() === "取り消す")
      .click();
    await flush();
    await flush();

    expect(previewCancelConfirmed).toHaveBeenCalled();
    expect(LightningConfirm.open).not.toHaveBeenCalled();
  });

  it("shows customer cancel notice for sent invoices before and on the cancel panel", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ hasLockedJournals: false, payments: [] })
    );
    previewCancelConfirmed.mockClear();
    LightningConfirm.open.mockClear();
    previewCancelConfirmed.mockResolvedValue({
      displayText: "論理削除件数: 0\n逆仕訳件数: 0\n実際の逆仕訳日:\nなし\n将来日付: なし"
    });
    LightningConfirm.open.mockResolvedValue(false);
    const preview = buildPreview();
    preview.invoices[0].deliveryStatus = "Sent";
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = preview;
    document.body.appendChild(element);
    await flush();

    const cancelButton = Array.from(
      element.shadowRoot.querySelectorAll("button.ghost-btn")
    ).find(
      (button) =>
        button.textContent.trim() === "取消" && button.dataset.invoiceId
    );
    cancelButton.click();
    await flush();

    expect(element.shadowRoot.textContent).toContain(
      "顧客への取消連絡が必要です。"
    );

    const reason = element.shadowRoot.querySelector(
      'lightning-combobox[data-field="cancellationReason"]'
    );
    reason.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Duplicate" } })
    );
    await flush();
    Array.from(element.shadowRoot.querySelectorAll("button.solid-btn"))
      .find((button) => button.textContent.trim() === "取り消す")
      .click();
    await flush();
    await flush();

    expect(LightningConfirm.open).not.toHaveBeenCalled();
  });

  it("hides manual journal entry on draft invoices even when Accounting is on", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: true })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    const preview = buildPreview();
    preview.invoices[0].invoiceTransactionStatus = "Draft";
    element.preview = preview;
    document.body.appendChild(element);
    await flush();
    await openJournalsTab(element);

    expect(
      element.shadowRoot.querySelector("c-manual-journal-entry")
    ).toBeNull();
  });

  it("shows manual journal entry only on confirmed invoices when Accounting is on", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: true })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    element.contractHistoryId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await flush();
    await openJournalsTab(element);

    expect(
      element.shadowRoot.querySelector("c-manual-journal-entry")
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector("c-manual-journal-entry").operationDay
    ).toBe("2026-08-29");
    expect(
      element.shadowRoot.querySelector("c-manual-journal-entry").contractHistoryId
    ).toBe("a0H000000000001AAA");
    expect(
      element.shadowRoot.querySelector("c-manual-journal-entry").hasLockedJournals
    ).toBe(false);
  });

  it("passes the open contract history to payment cancel preview", async () => {
    getOpsBundle.mockResolvedValue(mockBundle());
    previewCancelPaymentFromPreview.mockResolvedValue({ displayText: "" });
    LightningConfirm.open.mockResolvedValue(false);
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    element.contractHistoryId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    element.shadowRoot
      .querySelector("button[data-payment-id='a02PAY000000001']")
      .click();
    await flush();
    await flush();

    const reason = element.shadowRoot.querySelector(
      'lightning-combobox[data-field="cancellationReason"]'
    );
    reason.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Duplicate" } })
    );
    await flush();

    Array.from(element.shadowRoot.querySelectorAll("button.solid-btn"))
      .find((button) => button.textContent.trim() === "取消する")
      .click();
    await flush();
    await flush();

    expect(previewCancelPaymentFromPreview).toHaveBeenCalled();
    const lastPreview =
      previewCancelPaymentFromPreview.mock.calls[
        previewCancelPaymentFromPreview.mock.calls.length - 1
      ][0];
    expect(lastPreview.contractHistoryId).toBe("a0H000000000001AAA");
  });

  it("hides acceptance end date input without invoice board edit permission", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: true, hasLockedJournals: false })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    const preview = buildPreview();
    preview.canEdit = false;
    preview.invoices[0].lines[0].revenueRecognitionBasis = "一括計上";
    preview.invoices[0].lines[0].acceptanceEndDate = "2026-06-30";
    element.preview = preview;
    document.body.appendChild(element);
    await flush();
    await flush();

    expect(
      element.shadowRoot.querySelector(
        'lightning-input[data-line-id="a01LINE00000001"]'
      )
    ).toBeNull();
  });

  it("passes the open contract history to acceptance date preview", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: true, hasLockedJournals: true })
    );
    previewInvoiceLineAcceptanceEndDate.mockResolvedValue({ displayText: "" });
    LightningConfirm.open.mockResolvedValue(false);
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    const preview = buildPreview();
    preview.canEdit = true;
    preview.invoices[0].lines[0].revenueRecognitionBasis = "一括計上";
    preview.invoices[0].lines[0].acceptanceEndDate = "2026-06-30";
    element.preview = preview;
    element.contractHistoryId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await flush();
    await flush();

    const dateInput = element.shadowRoot.querySelector(
      'lightning-input[data-line-id="a01LINE00000001"]'
    );
    dateInput.dispatchEvent(
      new CustomEvent("change", { detail: { value: "2026-08-31" } })
    );
    await flush();
    await flush();

    expect(
      previewInvoiceLineAcceptanceEndDate.mock.calls[0][0].contractHistoryId
    ).toBe("a0H000000000001AAA");
  });

  it("does not open acceptance-date confirm and still saves (Core 0.2)", async () => {
    previewInvoiceLineAcceptanceEndDate.mockClear();
    LightningConfirm.open.mockClear();
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: true, hasLockedJournals: false })
    );
    previewInvoiceLineAcceptanceEndDate.mockResolvedValue({
      reverseCount: 0,
      displayText: "論理削除件数: 2\n逆仕訳件数: 0"
    });
    LightningConfirm.open.mockResolvedValue(true);
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    const preview = buildPreview();
    preview.canEdit = true;
    preview.invoices[0].lines[0].revenueRecognitionBasis = "一括計上";
    preview.invoices[0].lines[0].acceptanceEndDate = "2026-06-30";
    element.preview = preview;
    element.contractHistoryId = "a0H000000000001AAA";
    const dispatchSpy = jest.spyOn(element, "dispatchEvent");
    document.body.appendChild(element);
    const dateInput = await waitUntil(() =>
      element.shadowRoot.querySelector(
        'lightning-input[data-line-id="a01LINE00000001"]'
      )
    );
    dateInput.dispatchEvent(
      new CustomEvent("change", { detail: { value: "2026-08-31" } })
    );
    await flush();
    await flush();

    expect(previewInvoiceLineAcceptanceEndDate).toHaveBeenCalled();
    expect(
      previewInvoiceLineAcceptanceEndDate.mock.calls[0][0].cancellationDate
    ).toBeNull();
    expect(LightningConfirm.open).not.toHaveBeenCalled();
    const saveEvent = dispatchSpy.mock.calls
      .map((call) => call[0])
      .find((event) => event.type === "saveacceptanceenddate");
    expect(saveEvent.detail.cancellationDate).toBeNull();
    expect(saveEvent.detail.journalPreviewText).toBeUndefined();
  });

  it("does not open payment register confirm and still saves (Core 0.2)", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: true, hasLockedJournals: false })
    );
    previewRegisterFromPreview.mockResolvedValue({
      reverseCount: 0,
      displayText: "論理削除件数: 2\n逆仕訳件数: 0"
    });
    savePaymentFromPreview.mockResolvedValue("a02PAY000000099");
    LightningConfirm.open.mockResolvedValue(true);
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    element.contractHistoryId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    const amountInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="amount"]'
    );
    amountInput.dispatchEvent(
      new CustomEvent("change", { detail: { value: "100" } })
    );
    await flush();
    Array.from(element.shadowRoot.querySelectorAll("button.solid-btn"))
      .find((button) => button.textContent.trim() === "追加")
      .click();
    await flush();

    expect(previewRegisterFromPreview).toHaveBeenCalled();
    expect(LightningConfirm.open).not.toHaveBeenCalled();
    expect(savePaymentFromPreview).toHaveBeenCalled();
    expect(savePaymentFromPreview.mock.calls[0][0].cancellationDate).toBeNull();
    expect(savePaymentFromPreview.mock.calls[0][0].allocations).toEqual([
      { invoiceLineId: "a01LINE00000001", amount: 100 }
    ]);
  });

  it("sends invoice operation token when saving payment memo", async () => {
    updatePaymentFromPreview.mockResolvedValue(undefined);
    getOpsBundle.mockResolvedValue(
      mockBundle({
        payments: [
          {
            paymentId: "a02PAY000000001",
            amount: 200,
            displayAmount: 200,
            paymentPurpose: "Invoice",
            paymentDate: "2026-06-10",
            memo: "",
            canCancel: true,
            lastModifiedToken: "pay-token",
            paymentTransactionStatus: "Active"
          }
        ]
      })
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    element.contractHistoryId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);
    const editButton = Array.from(
      element.shadowRoot.querySelectorAll("button.ghost-btn")
    ).find((button) => button.textContent.trim() === "編集");
    expect(editButton).toBeTruthy();
    editButton.click();
    await flush();
    const memoInput = Array.from(
      element.shadowRoot.querySelectorAll("lightning-input")
    ).find((input) => input.label === "メモ");
    memoInput.dispatchEvent(
      new CustomEvent("change", { detail: { value: "メモ更新" } })
    );
    await flush();
    Array.from(element.shadowRoot.querySelectorAll("button.solid-btn"))
      .find((button) => button.textContent.trim() === "保存")
      .click();
    await flush();
    expect(updatePaymentFromPreview).toHaveBeenCalled();
    expect(updatePaymentFromPreview.mock.calls[0][0].expectedToken).toBe(
      "token"
    );
    expect(updatePaymentFromPreview.mock.calls[0][0].expectedToken).not.toBe(
      "pay-token"
    );
  });

  it("omits journal counts from payment register success toast", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: true, hasLockedJournals: true })
    );
    previewRegisterFromPreview.mockResolvedValue({
      reverseCount: 1,
      displayText: "論理削除件数: 0\n逆仕訳件数: 1"
    });
    savePaymentFromPreview.mockResolvedValue("a02PAY000000099");
    LightningConfirm.open.mockResolvedValue(true);
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    element.contractHistoryId = "a0H000000000001AAA";
    document.body.appendChild(element);
    const dispatchSpy = jest.spyOn(element, "dispatchEvent");
    await flush();
    await openPaymentsTab(element);

    const amountInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="amount"]'
    );
    amountInput.dispatchEvent(
      new CustomEvent("change", { detail: { value: "100" } })
    );
    await flush();
    Array.from(element.shadowRoot.querySelectorAll("button.solid-btn"))
      .find((button) => button.textContent.trim() === "追加")
      .click();
    await flush();
    await flush();
    const cancelDate = await waitUntil(() =>
      element.shadowRoot.querySelector(
        'lightning-input[data-field="cancellationDate"]'
      )
    );
    cancelDate.dispatchEvent(
      new CustomEvent("change", { detail: { value: "2026-08-29" } })
    );
    await flush();
    Array.from(element.shadowRoot.querySelectorAll("button.solid-btn"))
      .find((button) => button.textContent.trim() === "追加")
      .click();
    const toast = await waitUntil(() =>
      dispatchSpy.mock.calls
        .map((args) => args[0])
        .find((evt) => evt?.detail?.title === "入出金を追加しました")
    );
    expect(toast).toBeTruthy();
    expect(String(toast.detail.message || "")).not.toContain("逆仕訳件数");
    expect(String(toast.detail.message || "")).not.toContain("論理削除件数");
    expect(savePaymentFromPreview).toHaveBeenCalled();
    expect(savePaymentFromPreview.mock.calls[0][0].businessOperationKey).toBe(
      "op-key-1"
    );
    expect(savePaymentFromPreview.mock.calls[0][0].contractHistoryId).toBe(
      "a0H000000000001AAA"
    );
  });

  it("rejects a fractional payment amount without calling Apex", async () => {
    getOpsBundle.mockResolvedValue(mockBundle());
    savePaymentFromPreview.mockResolvedValue("a02PAY000000099");
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    element.contractHistoryId = "a0H000000000001AAA";
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);
    const amountInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="amount"]'
    );
    amountInput.dispatchEvent(
      new CustomEvent("change", { detail: { value: "1.5" } })
    );
    await flush();

    const saveButton = Array.from(
      element.shadowRoot.querySelectorAll("button.solid-btn")
    ).find((button) => button.textContent.trim() === "追加");
    expect(saveButton.disabled).toBe(true);
    saveButton.click();
    await flush();
    expect(savePaymentFromPreview).not.toHaveBeenCalled();
  });

  it("does not ask to confirm deleting the source invoice when all non-zero lines are moved (Core 0.2)", async () => {
    LightningConfirm.open.mockClear();
    const preview = buildPreview();
    preview.canEdit = true;
    preview.invoices[0].invoiceTransactionStatus = "Draft";
    preview.invoices[0].locked = false;
    preview.invoices[0].lines = [
      { lineId: "a01LINE00000001", amount: 1000, productName: "A" },
      { lineId: "a01LINE00000002", amount: 0, productName: "Zero" }
    ];
    const dispatchEvent = jest.fn();
    await OrderInvoicePreviewTable.prototype.handleConfirmInvoiceSplit.call({
      invoiceSplitState: {
        invoiceId: "a00INV000000001",
        selected: { a01LINE00000001: true },
        newInvoiceDate: "2026-06-01",
        newPaymentDate: "2026-07-01",
        newBillingAccountId: "a03BA0000000001"
      },
      isSaving: false,
      hasAmountDrafts: false,
      findInvoice: () => preview.invoices[0],
      dispatchEvent,
      resolvePendingOperationKey: async () => "op-key-1"
    });

    expect(LightningConfirm.open).not.toHaveBeenCalled();
    expect(dispatchEvent).toHaveBeenCalled();
    expect(dispatchEvent.mock.calls[0][0].type).toBe("splitinvoice");
  });

  it("入出金取消はその他理由テキストが空白のみなら保存できない (Core 7.9.5 / 1.1.10)", async () => {
    getOpsBundle.mockResolvedValue(mockBundle());
    previewCancelPaymentFromPreview.mockResolvedValue({ reverseCount: 0, displayText: "" });
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    element.shadowRoot
      .querySelector("button[data-payment-id='a02PAY000000001']")
      .click();
    await flush();
    await flush();

    const reason = element.shadowRoot.querySelector(
      'lightning-combobox[data-field="cancellationReason"]'
    );
    reason.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Other" } })
    );
    await flush();

    const reasonText = element.shadowRoot.querySelector(
      'lightning-input[data-field="cancellationReasonText"]'
    );
    reasonText.dispatchEvent(
      new CustomEvent("change", { detail: { value: "   " } })
    );
    await flush();

    const saveButton = Array.from(
      element.shadowRoot.querySelectorAll("button.solid-btn")
    ).find((button) => button.textContent.trim() === "取消する");
    expect(saveButton.disabled).toBe(true);
    previewCancelPaymentFromPreview.mockClear();
    saveButton.click();
    await flush();
    expect(previewCancelPaymentFromPreview).not.toHaveBeenCalled();
  });

  it("有効な請求入出金がある請求の取消ボタンは実行できない (Core 7.9.3 / 7.7.3 / 1.1.10)", async () => {
    getOpsBundle.mockResolvedValue(mockBundle());
    previewCancelConfirmed.mockClear();
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await flush();

    const cancelButton = Array.from(
      element.shadowRoot.querySelectorAll("button.ghost-btn")
    ).find(
      (button) =>
        button.textContent.trim() === "取消" && button.dataset.invoiceId
    );
    expect(cancelButton.disabled).toBe(true);
    expect(cancelButton.title).toBe(
      "有効な請求入出金がある請求は取消できません。"
    );
    cancelButton.click();
    await flush();
    expect(
      element.shadowRoot.querySelector(
        'lightning-combobox[data-field="cancellationReason"]'
      )
    ).toBeNull();
    expect(previewCancelConfirmed).not.toHaveBeenCalled();
  });

  it("有効な手動仕訳がある請求の取消ボタンは実行できない (Core 7.9.3 / 7.7.3 / 1.1.10)", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({
        payments: [],
        manualJournals: [{ headerId: "a04MJ0000000001", transactionStatus: "Active" }]
      })
    );
    previewCancelConfirmed.mockClear();
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await flush();

    const cancelButton = Array.from(
      element.shadowRoot.querySelectorAll("button.ghost-btn")
    ).find(
      (button) =>
        button.textContent.trim() === "取消" && button.dataset.invoiceId
    );
    expect(cancelButton.disabled).toBe(true);
    expect(cancelButton.title).toBe(
      "有効な手動仕訳がある請求は取消できません。"
    );
    cancelButton.click();
    await flush();
    expect(
      element.shadowRoot.querySelector(
        'lightning-combobox[data-field="cancellationReason"]'
      )
    ).toBeNull();
    expect(previewCancelConfirmed).not.toHaveBeenCalled();
  });
});
