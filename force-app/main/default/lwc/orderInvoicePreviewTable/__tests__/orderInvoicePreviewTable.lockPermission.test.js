import { createElement } from "lwc";
import OrderInvoicePreviewTable from "c/orderInvoicePreviewTable";
import getBoardContext from "@salesforce/apex/InvoiceSendBoardController.getBoardContext";
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
        historyVersion: 1,
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
        ],
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

function lockButton(element) {
  return Array.from(element.shadowRoot.querySelectorAll("button")).find(
    (button) => /件をLock$/.test(button.textContent.trim())
  );
}

function unlockButton(element) {
  return Array.from(element.shadowRoot.querySelectorAll("button")).find(
    (button) => /件をUnlock$/.test(button.textContent.trim())
  );
}

function lockCheckbox(element) {
  return element.shadowRoot.querySelector(
    'td.split-select-col lightning-input[data-journal-id="a03JNL000000001"]'
  );
}

function lockEmptyButton(element) {
  return element.shadowRoot.querySelector("button.journal-lock-empty");
}

function lockKeyButton(element) {
  return element.shadowRoot.querySelector("button.journal-lock-key");
}

async function openJournalsTab(element) {
  const tab = await waitUntil(
    () => element.shadowRoot.querySelector("button[data-tab='journals']")
  );
  tab.click();
  await flush();
}

function mount(preview) {
  const element = createElement("c-order-invoice-preview-table", {
    is: OrderInvoicePreviewTable
  });
  element.preview = preview;
  document.body.appendChild(element);
  return element;
}

describe("orderInvoicePreviewTable journal lock permissions (Accounting 第9.5節 / 共通基盤 第10.4節 / Core 第7.7.3節)", () => {
  beforeEach(() => {
    getBoardContext.mockResolvedValue({
      featureEnabled: false,
      canSend: true,
      accountingEnabled: true,
      documentTemplateOptions: [],
      emailTemplateOptions: []
    });
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
          memo: ""
        }
      ],
      manualJournals: []
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows Lock and Unlock when each dedicated permission is present", async () => {
    const element = mount(buildPreview());
    await flush();
    await openJournalsTab(element);
    expect(lockButton(element)).toBeFalsy();
    expect(unlockButton(element)).toBeFalsy();
    expect(lockCheckbox(element)).toBeTruthy();
    expect(lockEmptyButton(element)).toBeFalsy();
    expect(lockKeyButton(element)).toBeFalsy();
  });

  it("shows N件をLock on the bar after selecting an unlocked journal (Core 7.7.3)", async () => {
    const element = mount(buildPreview());
    await flush();
    await openJournalsTab(element);
    const box = lockCheckbox(element);
    box.checked = true;
    box.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(lockButton(element)?.textContent.trim()).toBe("1件をLock");
    expect(unlockButton(element)).toBeFalsy();
  });

  it("hides Lock and Unlock on cancelled invoices even with both permissions", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.initialInvoiceId = "a00INV000000001";
    element.preview = buildPreview({
      invoiceTransactionStatus: "Cancelled",
      isCancelled: true
    });
    document.body.appendChild(element);
    await flush();
    await openJournalsTab(element);
    expect(lockButton(element)).toBeFalsy();
    expect(unlockButton(element)).toBeFalsy();
    expect(lockCheckbox(element)).toBeFalsy();
    expect(lockEmptyButton(element)).toBeFalsy();
    expect(lockKeyButton(element)).toBeFalsy();
  });

  it("filters journal rows by posting month and event in the header (Core 7.7.3)", async () => {
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
          eventName: "請求本体",
          amount: 1100,
          postingDate: "2026-06-01",
          transactionStatus: "Active",
          isLocked: false,
          memo: "",
          invoiceLineId: "a01LINE00000001",
          productName: "本体商品"
        },
        {
          journalId: "a03JNL000000002",
          eventKey: "PAYMENT_INVOICE_CURRENT",
          eventName: "入金",
          amount: 1100,
          postingDate: "2026-07-15",
          transactionStatus: "Active",
          isLocked: false,
          memo: "",
          invoiceLineId: "a01LINE00000002",
          productName: "入金商品"
        }
      ],
      manualJournals: []
    });
    const element = mount(buildPreview());
    await flush();
    await openJournalsTab(element);
    const headers = Array.from(
      element.shadowRoot.querySelectorAll("table.ops-table_journals thead th")
    ).map((th) => th.textContent.replace(/\s+/g, " ").trim());
    expect(headers.slice(0, 3)).toEqual(["選択", "Lock", "状態"]);
    expect(headers[3]).toContain("計上日");
    expect(headers[4]).toContain("イベント");
    const rowText = () =>
      Array.from(
        element.shadowRoot.querySelectorAll(
          "table.ops-table_journals tbody tr.journal-row"
        )
      )
        .map((row) => row.textContent)
        .join(" ");
    expect(rowText()).toContain("請求本体");
    expect(rowText()).toContain("入金");
    const monthTrigger = element.shadowRoot.querySelector(
      "button[data-filter='postingMonth']"
    );
    monthTrigger.click();
    await flush();
    const june = element.shadowRoot.querySelector(
      "lightning-input[data-filter='postingMonth'][data-value='2026-06']"
    );
    june.checked = true;
    june.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(rowText()).toContain("請求本体");
    expect(rowText()).not.toContain("入金");
    june.checked = false;
    june.dispatchEvent(new CustomEvent("change"));
    await flush();
    const lineTrigger = element.shadowRoot.querySelector(
      "button[data-filter='lineKey']"
    );
    lineTrigger.click();
    await flush();
    const line = element.shadowRoot.querySelector(
      "lightning-input[data-filter='lineKey'][data-value='a01LINE00000001']"
    );
    line.checked = true;
    line.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(rowText()).toContain("請求本体");
    expect(rowText()).not.toContain("入金");
  });

  it("filters journals by manual setting name and multiple months (Accounting 5.2)", async () => {
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
          eventName: "請求本体",
          amount: 1100,
          postingDate: "2026-06-01",
          transactionStatus: "Active",
          isLocked: false,
          memo: "",
          invoiceLineId: "a01LINE00000001",
          productName: "本体商品"
        },
        {
          journalId: "a03JNL000000004",
          eventKey: "MANUAL_JOURNAL",
          eventName: "為替差損の計上",
          amount: 100,
          postingDate: "2026-07-15",
          transactionStatus: "Active",
          isLocked: false,
          memo: ""
        }
      ],
      manualJournals: []
    });
    const element = mount(buildPreview());
    await flush();
    await openJournalsTab(element);
    const rowText = () =>
      Array.from(
        element.shadowRoot.querySelectorAll(
          "table.ops-table_journals tbody tr.journal-row"
        )
      )
        .map((row) => row.textContent)
        .join(" ");
    const eventTrigger = element.shadowRoot.querySelector(
      "button[data-filter='eventName']"
    );
    expect(eventTrigger.textContent).not.toContain("<span>");
    expect(eventTrigger.textContent.trim()).toBe("すべて");
    expect(
      eventTrigger
        .closest("th")
        .querySelector(".journal-filter-label").textContent
    ).toBe("イベント");
    expect(
      element.shadowRoot.querySelector(".journal-scroll_has-lock-bar")
    ).toBeNull();
    eventTrigger.click();
    await flush();
    expect(
      element.shadowRoot.querySelector(
        "lightning-input[data-filter='eventName'][data-value='MANUAL_JOURNAL']"
      )
    ).toBeNull();
    const manual = element.shadowRoot.querySelector(
      "lightning-input[data-filter='eventName'][data-value='為替差損の計上']"
    );
    manual.checked = true;
    manual.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(
      element.shadowRoot.querySelector(".journal-multi-filter-menu")
    ).not.toBeNull();
    expect(rowText()).toContain("為替差損の計上");
    expect(rowText()).not.toContain("請求本体");
    document.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }));
    await flush();
    expect(
      element.shadowRoot.querySelector(".journal-multi-filter-menu")
    ).toBeNull();
    eventTrigger.click();
    await flush();
    const stillOpen = element.shadowRoot.querySelector(
      "lightning-input[data-filter='eventName'][data-value='為替差損の計上']"
    );
    stillOpen.checked = false;
    stillOpen.dispatchEvent(new CustomEvent("change"));
    await flush();
    const monthTrigger = element.shadowRoot.querySelector(
      "button[data-filter='postingMonth']"
    );
    monthTrigger.click();
    await flush();
    const june = element.shadowRoot.querySelector(
      "lightning-input[data-filter='postingMonth'][data-value='2026-06']"
    );
    const july = element.shadowRoot.querySelector(
      "lightning-input[data-filter='postingMonth'][data-value='2026-07']"
    );
    june.checked = true;
    june.dispatchEvent(new CustomEvent("change"));
    july.checked = true;
    july.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(rowText()).toContain("請求本体");
    expect(rowText()).toContain("為替差損の計上");
  });

  it("hides Lock and Unlock when Accounting is OFF", async () => {
    getBoardContext.mockResolvedValue({
      featureEnabled: false,
      canSend: true,
      accountingEnabled: false,
      documentTemplateOptions: [],
      emailTemplateOptions: []
    });
    getOpsBundle.mockResolvedValue({
      accountingEnabled: false,
      paymentAllowed: true,
      taxInclusiveAmount: 1100,
      invoicePaymentNet: 0,
      paymentNetTotal: 0,
      invoiceDate: "2026-06-01",
      invoiceToken: "token",
      hasLockedJournals: false,
      payments: [],
      paymentLines: [],
      journals: [],
      manualJournals: []
    });
    const element = mount(buildPreview());
    await flush();
    await flush();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(
      element.shadowRoot.querySelector("button[data-tab='journals']")
    ).toBeNull();
    expect(lockButton(element)).toBeFalsy();
    expect(unlockButton(element)).toBeFalsy();
  });
});
