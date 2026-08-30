import { createElement } from "lwc";
import OrderInvoicePreviewTable from "c/orderInvoicePreviewTable";
import getOpsBundle from "@salesforce/apex/InvoicePreviewOpsController.getOpsBundle";
import savePaymentFromPreview from "@salesforce/apex/InvoicePreviewOpsController.savePaymentFromPreview";
import previewRegisterFromPreview from "@salesforce/apex/InvoicePreviewOpsController.previewRegisterFromPreview";
import previewCancelConfirmed from "@salesforce/apex/OrderCreateController.previewCancelConfirmed";
import previewCancelPaymentFromPreview from "@salesforce/apex/InvoicePreviewOpsController.previewCancelPaymentFromPreview";
import previewInvoiceLineAcceptanceEndDate from "@salesforce/apex/OrderCreateController.previewInvoiceLineAcceptanceEndDate";
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

async function openPaymentsTab(element) {
  const tab = Array.from(
    element.shadowRoot.querySelectorAll("button[data-tab='payments']")
  )[0];
  tab.click();
  await flush();
}

async function openJournalsTab(element) {
  const tab = Array.from(
    element.shadowRoot.querySelectorAll("button[data-tab='journals']")
  )[0];
  tab.click();
  await flush();
}

describe("orderInvoicePreviewTable payment form", () => {
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

    let rows = element.shadowRoot.querySelectorAll(".ops-table tbody tr");
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

    rows = element.shadowRoot.querySelectorAll(".ops-table tbody tr");
    expect(rows).toHaveLength(3);
    const statusLabels = Array.from(rows).map((row) =>
      row.querySelectorAll("td")[4].textContent.trim()
    );
    expect(statusLabels).toEqual(["有効", "取消済み", "取消"]);
  });

  it("shows journal event names and Japanese transaction statuses", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({
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
    const statuses = Array.from(
      element.shadowRoot.querySelectorAll(".ops-table tbody tr")
    ).map((row) => row.querySelectorAll("td")[6].textContent.trim());
    expect(statuses).toEqual(["有効", "取消", "論理削除", "取消済"]);
    const periods = Array.from(
      element.shadowRoot.querySelectorAll(".ops-table tbody tr")
    ).map((row) => row.querySelectorAll("td")[5].textContent.trim());
    expect(periods).toEqual(["到来済み", "到来済み", "到来済み", "到来済み"]);
    expect(element.shadowRoot.textContent).toContain("会計イベント");
    expect(element.shadowRoot.textContent).toContain("取引状態");
    expect(element.shadowRoot.textContent).toContain("ロック状態");
    expect(element.shadowRoot.textContent).toContain("計上時期");
    expect(element.shadowRoot.textContent).not.toContain("確認用");
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

    const statusFilter = element.shadowRoot.querySelector(
      'lightning-checkbox-group[name="journalStatuses"]'
    );
    statusFilter.dispatchEvent(
      new CustomEvent("change", {
        detail: {
          value: ["Active", "LogicallyDeleted", "Cancelled", "Reversal"]
        }
      })
    );
    await flush();

    const rows = Array.from(
      element.shadowRoot.querySelectorAll(".ops-table tbody tr")
    );
    expect(rows).toHaveLength(4);
    const checkboxes = rows.map((row) =>
      row.querySelector('lightning-input[type="checkbox"]')
    );
    expect(checkboxes[0]).toBeTruthy();
    expect(checkboxes[0].dataset.journalId).toBe("a03JNL000000001");
    expect(checkboxes[1]).toBeNull();
    expect(checkboxes[2]).toBeNull();
    expect(checkboxes[3]).toBeNull();
  });

  it("labels journal posting period against organization operation day", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({
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
      element.shadowRoot.querySelectorAll(".ops-table tbody tr")
    ).map((row) => row.querySelectorAll("td")[5].textContent.trim());
    expect(periods).toEqual(["将来", "到来済み"]);
  });

  it("filters journals by accounting event", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({
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

    const eventFilter = element.shadowRoot.querySelector(
      'lightning-checkbox-group[name="journalEvents"]'
    );
    eventFilter.dispatchEvent(
      new CustomEvent("change", { detail: { value: ["MANUAL_JOURNAL"] } })
    );
    await flush();

    const rows = element.shadowRoot.querySelectorAll(".ops-table tbody tr");
    expect(rows).toHaveLength(1);
    expect(rows[0].textContent).toContain("手動仕訳");
    expect(rows[0].textContent).not.toContain("請求確定");
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

  it("seeds payment register cancel date to the operation day when locked journals exist", async () => {
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

    const dateInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="cancellationDate"]'
    );
    expect(dateInput).not.toBeNull();
    expect(dateInput.value).toBe("2026-08-29");
  });

  it("omits payment register cancel date when Accounting is off even if locked journals exist", async () => {
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

  it("does not save a locked payment register when cancel date is cleared", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: true, hasLockedJournals: true })
    );
    previewRegisterFromPreview.mockResolvedValue({
      displayText: "論理削除件数: 0"
    });
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    await flush();
    await openPaymentsTab(element);

    const dateInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="cancellationDate"]'
    );
    dateInput.dispatchEvent(new CustomEvent("change", { detail: { value: "" } }));
    await flush();

    const saveButton = Array.from(
      element.shadowRoot.querySelectorAll("button.solid-btn")
    ).find((button) => button.textContent.trim() === "追加");
    expect(saveButton.disabled).toBe(true);
    saveButton.click();
    await flush();
    expect(savePaymentFromPreview).not.toHaveBeenCalled();
    expect(previewRegisterFromPreview).not.toHaveBeenCalled();
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

  it("shows journal cancel preview counts before confirming invoice cancel", async () => {
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
    expect(LightningConfirm.open).toHaveBeenCalledWith(
      expect.objectContaining({
        message: expect.stringContaining("論理削除件数: 1")
      })
    );
    expect(LightningConfirm.open.mock.calls[0][0].message).toContain(
      "逆仕訳件数: 2"
    );
    expect(LightningConfirm.open.mock.calls[0][0].message).toContain(
      "将来日付: あり"
    );
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

    expect(LightningConfirm.open.mock.calls[0][0].message).toContain(
      "顧客への取消連絡が必要です。"
    );
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

    expect(previewCancelPaymentFromPreview.mock.calls[0][0].contractHistoryId).toBe(
      "a0H000000000001AAA"
    );
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

    Array.from(element.shadowRoot.querySelectorAll("button.solid-btn"))
      .find((button) => button.textContent.trim() === "変更する")
      .click();
    await flush();
    await flush();

    expect(
      previewInvoiceLineAcceptanceEndDate.mock.calls[0][0].contractHistoryId
    ).toBe("a0H000000000001AAA");
  });

  it("shows journal count preview for unlocked Accounting ON acceptance date change", async () => {
    previewInvoiceLineAcceptanceEndDate.mockClear();
    LightningConfirm.open.mockClear();
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: true, hasLockedJournals: false })
    );
    previewInvoiceLineAcceptanceEndDate.mockResolvedValue({
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
    await flush();
    await flush();
    element.updateInvoiceUiState("a00INV000000001", {
      bundle: mockBundle({ accountingEnabled: true, hasLockedJournals: false })
    });
    await element.handleAcceptanceEndDateChange({
      currentTarget: { dataset: { lineId: "a01LINE00000001" } },
      detail: { value: "2026-08-31" }
    });
    await flush();
    await flush();

    expect(previewInvoiceLineAcceptanceEndDate).toHaveBeenCalled();
    expect(
      previewInvoiceLineAcceptanceEndDate.mock.calls[0][0].cancellationDate
    ).toBeNull();
    expect(LightningConfirm.open).toHaveBeenCalled();
    expect(LightningConfirm.open.mock.calls[0][0].message).toContain(
      "論理削除件数: 2"
    );
    const saveEvent = dispatchSpy.mock.calls
      .map((call) => call[0])
      .find((event) => event.type === "saveacceptanceenddate");
    expect(saveEvent.detail.cancellationDate).toBeNull();
    expect(saveEvent.detail.journalPreviewText).toContain("論理削除件数: 2");
  });

  it("shows journal count preview for unlocked Accounting ON payment register", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: true, hasLockedJournals: false })
    );
    previewRegisterFromPreview.mockResolvedValue({
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
    element.updateInvoiceUiState("a00INV000000001", {
      paymentDraft: {
        invoiceId: "a00INV000000001",
        amount: "100",
        purpose: "Invoice",
        paymentDate: "2026-08-29",
        allocations: [{ lineId: "a01LINE00000001", amount: 100 }]
      },
      bundle: mockBundle({ accountingEnabled: true, hasLockedJournals: false })
    });
    await element.handlePaymentSave({
      currentTarget: { dataset: { invoiceId: "a00INV000000001" } }
    });
    await flush();

    expect(previewRegisterFromPreview).toHaveBeenCalled();
    expect(LightningConfirm.open).toHaveBeenCalled();
    expect(LightningConfirm.open.mock.calls[0][0].message).toContain(
      "論理削除件数: 2"
    );
    expect(savePaymentFromPreview).toHaveBeenCalled();
    expect(savePaymentFromPreview.mock.calls[0][0].cancellationDate).toBeNull();
  });

  it("shows reverse-journal result after locked payment register", async () => {
    getOpsBundle.mockResolvedValue(
      mockBundle({ accountingEnabled: true, hasLockedJournals: true })
    );
    previewRegisterFromPreview.mockResolvedValue({
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
    element.updateInvoiceUiState("a00INV000000001", {
      paymentDraft: {
        invoiceId: "a00INV000000001",
        amount: "100",
        purpose: "Invoice",
        paymentDate: "2026-08-29",
        cancellationDate: "2026-08-29",
        allocations: [{ lineId: "a01LINE00000001", amount: 100 }]
      },
      bundle: mockBundle({ accountingEnabled: true, hasLockedJournals: true })
    });
    await element.handlePaymentSave({
      currentTarget: { dataset: { invoiceId: "a00INV000000001" } }
    });
    await flush();

    expect(savePaymentFromPreview).toHaveBeenCalled();
    expect(savePaymentFromPreview.mock.calls[0][0].businessOperationKey).toBe(
      "op-key-1"
    );
    expect(savePaymentFromPreview.mock.calls[0][0].contractHistoryId).toBe(
      "a0H000000000001AAA"
    );
    const toast = dispatchSpy.mock.calls
      .map((args) => args[0])
      .find(
        (evt) =>
          evt?.detail?.message === "論理削除件数: 0\n逆仕訳件数: 1" &&
          evt?.detail?.title === "入出金を追加しました"
      );
    expect(toast).toBeTruthy();
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
    element.updateInvoiceUiState("a00INV000000001", {
      paymentDraft: {
        invoiceId: "a00INV000000001",
        amount: "1.5",
        purpose: "Invoice",
        paymentDate: "2026-08-29",
        allocations: [{ lineId: "a01LINE00000001", amount: 1.5 }]
      }
    });
    await flush();

    expect(element.invoiceCards[0].paymentSaveDisabled).toBe(true);
    await element.handlePaymentSave({
      currentTarget: { dataset: { invoiceId: "a00INV000000001" } }
    });
    await flush();
    expect(savePaymentFromPreview).not.toHaveBeenCalled();
  });

  it("asks to delete the source invoice when all non-zero lines are moved", async () => {
    LightningConfirm.open.mockResolvedValue(false);
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    const preview = buildPreview();
    preview.canEdit = true;
    preview.invoices[0].invoiceTransactionStatus = "Draft";
    preview.invoices[0].locked = false;
    preview.invoices[0].lines = [
      { lineId: "a01LINE00000001", amount: 1000, productName: "A" },
      { lineId: "a01LINE00000002", amount: 0, productName: "Zero" }
    ];
    element.preview = preview;
    document.body.appendChild(element);
    await flush();

    element.invoiceSplitState = {
      invoiceId: "a00INV000000001",
      selected: { a01LINE00000001: true },
      newInvoiceDate: "2026-06-01",
      newPaymentDate: "2026-07-01",
      newBillingAccountId: "a03BA0000000001"
    };
    await element.handleConfirmInvoiceSplit();
    await flush();

    expect(LightningConfirm.open).toHaveBeenCalledWith(
      expect.objectContaining({
        message: expect.stringContaining("元の請求書は削除")
      })
    );
  });

  it("入出金取消はその他理由テキストが空白のみなら保存できない (Core 7.9.5 / 1.1.10)", async () => {
    getOpsBundle.mockResolvedValue(mockBundle());
    previewCancelPaymentFromPreview.mockClear();
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
