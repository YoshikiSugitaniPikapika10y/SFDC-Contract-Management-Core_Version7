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

describe("orderInvoicePreviewTable extra fields (Core 11.4.4 / 7.8 / Accounting 9.1.1)", () => {
  beforeEach(() => {
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
      journals: [],
      manualJournals: []
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("確定済みでも請求書情報ボタンを出す (Core 7.8 / 11.4.4)", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview();
    document.body.appendChild(element);
    const billing = await waitUntil(() =>
      Array.from(element.shadowRoot.querySelectorAll("button")).find(
        (button) => button.textContent.trim() === "請求書情報"
      )
    );
    expect(billing).toBeTruthy();
    const split = Array.from(element.shadowRoot.querySelectorAll("button")).find(
      (button) => button.textContent.trim() === "別の請求へ分ける"
    );
    expect(split).toBeFalsy();
  });

  it("取消済み請求は請求書情報を出さない (Core 7.8 / 11.4.4)", async () => {
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
    const billing = Array.from(element.shadowRoot.querySelectorAll("button")).find(
      (button) => button.textContent.trim() === "請求書情報"
    );
    expect(billing).toBeFalsy();
  });

  it("取消済みを含めた請求カードは灰色クラスを付ける (Core 7.7.0)", async () => {
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
    const card = element.shadowRoot.querySelector(".invoice-card");
    expect(card.classList.contains("invoice-card_cancelled")).toBe(true);
    expect(element.shadowRoot.textContent).toContain("取消済み");
  });

  it("preview先着でも起動時の請求書指定を子フィルタにする (Core 7.7.0 / 横断 2.4)", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    const preview = buildPreview();
    preview.invoices.push({
      invoiceId: "a00INV000000002",
      invoiceName: "INV-2",
      invoiceDate: "2026-06-01",
      paymentScheduledDate: "2026-07-31",
      amountTotal: 2000,
      taxTotal: 200,
      taxPercent: 10,
      taxInclusiveAmount: 2200,
      invoicePaymentNet: 0,
      invoiceTransactionStatus: "Confirmed",
      invoiceDeliveryMethod: "Email",
      locked: true,
      isCancelled: false,
      historyVersion: 1,
      lines: [
        {
          lineId: "a01LINE00000002",
          productName: "B",
          amount: 2000,
          historyVersionLabel: "V1",
          isRecurring: true,
          unitPrice: 2000,
          quantity: 1
        }
      ]
    });
    element.preview = preview;
    document.body.appendChild(element);
    await flush();
    element.initialInvoiceId = "a00INV000000002";
    await flush();
    const names = Array.from(
      element.shadowRoot.querySelectorAll(".invoice-card .invoice-index")
    ).map((node) => node.textContent.trim());
    expect(names).toEqual(["INV-2"]);
    element.initialInvoiceId = "a00INV000000001";
    await flush();
    const namesAfter = Array.from(
      element.shadowRoot.querySelectorAll(".invoice-card .invoice-index")
    ).map((node) => node.textContent.trim());
    expect(namesAfter).toEqual(["INV-1"]);
  });

  it("請求書情報は識別・送付・日付・メモに分け税率とヘッダ反映とフッタメモを出さない (Core 7.8)", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview({
      billingAccountName: "BA-1",
      billingAddressee: "宛名A",
      billingEmailTo: "to@example.com",
      memo: "既存メモ"
    });
    document.body.appendChild(element);
    const open = await waitUntil(() =>
      Array.from(element.shadowRoot.querySelectorAll("button")).find(
        (button) => button.textContent.trim() === "請求書情報"
      )
    );
    open.click();
    const panel = await waitUntil(() =>
      element.shadowRoot.querySelector(".billing-info-panel")
    );
    const headings = Array.from(
      panel.querySelectorAll(".billing-edit-heading")
    ).map((node) => node.textContent.trim());
    expect(headings).toEqual(["識別", "送付", "当該請求の日付", "メモ"]);
    expect(panel.textContent).not.toContain("税率");
    expect(panel.textContent).not.toContain("請求日ルール");
    expect(panel.textContent).not.toContain("支払条件");
    const headerApply = Array.from(
      element.shadowRoot.querySelectorAll(".header-actions button")
    ).find((button) => button.textContent.trim() === "請求アカウントの内容を反映");
    expect(headerApply).toBeFalsy();
    const panelApply = Array.from(panel.querySelectorAll("button")).find(
      (button) => button.textContent.trim() === "請求アカウントの内容を反映"
    );
    expect(panelApply).toBeFalsy();
    const footerMemo = element.shadowRoot.querySelector(
      ".invoice-footer lightning-textarea"
    );
    expect(footerMemo).toBeFalsy();
    const memoSave = Array.from(panel.querySelectorAll("button")).find(
      (button) => button.textContent.trim() === "メモを保存"
    );
    expect(memoSave).toBeTruthy();
    expect(memoSave.closest(".panel-actions")).toBeTruthy();
    const headerSave = Array.from(panel.querySelectorAll("button")).find(
      (button) => button.textContent.trim() === "保存"
    );
    expect(headerSave.closest(".panel-actions")).toBeTruthy();
    expect(headerSave.classList.contains("solid-btn")).toBe(true);
    expect(memoSave.classList.contains("ghost-btn")).toBe(true);
  });

  it("請求書情報の中身は見出しの下に置き、入出金追加は入出金とメモの見出しを出す (Core 7.8 / 11.4.4)", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview({
      invoiceTransactionStatus: "Confirmed",
      locked: false
    });
    document.body.appendChild(element);
    const open = await waitUntil(() =>
      Array.from(element.shadowRoot.querySelectorAll("button")).find(
        (button) => button.textContent.trim() === "請求書情報"
      )
    );
    open.click();
    const panel = await waitUntil(() =>
      element.shadowRoot.querySelector(".billing-info-panel")
    );
    const identity = Array.from(
      panel.querySelectorAll(".billing-edit-section")
    ).find(
      (section) =>
        section.querySelector(".billing-edit-heading")?.textContent.trim() ===
        "識別"
    );
    expect(identity.querySelector(".billing-edit-heading").nextElementSibling.className).toContain(
      "billing-edit-row"
    );
    const paymentsTab = await waitUntil(() =>
      element.shadowRoot.querySelector("button[data-tab='payments']")
    );
    paymentsTab.click();
    const form = await waitUntil(() =>
      element.shadowRoot.querySelector(".ops-form")
    );
    const headings = Array.from(
      form.querySelectorAll(".billing-edit-heading")
    ).map((node) => node.textContent.trim());
    expect(headings).toEqual(["入出金", "メモ"]);
    expect(form.textContent).not.toContain("追加項目");
  });

  it("未確定の請求書情報は送付内に反映を出す (Core 7.8)", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview({
      invoiceTransactionStatus: "Draft",
      locked: false,
      billingAccountId: "a00BA0000000001"
    });
    document.body.appendChild(element);
    const open = await waitUntil(() =>
      Array.from(element.shadowRoot.querySelectorAll("button")).find(
        (button) => button.textContent.trim() === "請求書情報"
      )
    );
    open.click();
    const panel = await waitUntil(() =>
      element.shadowRoot.querySelector(".billing-info-panel")
    );
    const panelApply = await waitUntil(() =>
      Array.from(panel.querySelectorAll("button")).find(
        (button) => button.textContent.trim() === "請求アカウントの内容を反映"
      )
    );
    expect(panelApply).toBeTruthy();
    expect(panelApply.disabled).toBe(false);
    const headerApply = Array.from(
      element.shadowRoot.querySelectorAll(".header-actions button")
    ).find((button) => button.textContent.trim() === "請求アカウントの内容を反映");
    expect(headerApply).toBeFalsy();
  });

  it("送付は1行5列、反映は送付の2行目、追加項目は1行5項目 (Core 7.8 / 11.4.4)", async () => {
    getInvoiceOpsFieldDefinitions.mockResolvedValue(
      Array.from({ length: 6 }, (_, index) => ({
        targetObject: "Invoice__c",
        apiName: `Extra${index + 1}__c`,
        label: `追加${index + 1}`,
        fieldType: "STRING"
      }))
    );
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview({
      invoiceTransactionStatus: "Draft",
      locked: false,
      billingAccountId: "a00BA0000000001"
    });
    document.body.appendChild(element);
    const open = await waitUntil(() =>
      Array.from(element.shadowRoot.querySelectorAll("button")).find(
        (button) => button.textContent.trim() === "請求書情報"
      )
    );
    open.click();
    const panel = await waitUntil(() =>
      element.shadowRoot.querySelector(".billing-info-panel")
    );
    const sendRow = panel.querySelector(".billing-edit-row_send");
    expect(
      Array.from(sendRow.querySelectorAll(".invoice-meta-k")).map((node) =>
        node.textContent.trim()
      )
    ).toEqual(["宛名", "届け方", "To", "Cc", "Bcc"]);
    expect(panel.querySelector(".billing-edit-row_mail")).toBeFalsy();
    const apply = await waitUntil(() =>
      Array.from(panel.querySelectorAll("button")).find(
        (button) => button.textContent.trim() === "請求アカウントの内容を反映"
      )
    );
    expect(apply.closest(".billing-edit-row_send")).toBeFalsy();
    expect(apply.closest(".billing-edit-apply").previousElementSibling).toBe(
      sendRow
    );
    const extraRow = await waitUntil(() =>
      panel.querySelector(".billing-edit-row_extra")
    );
    expect(extraRow.querySelectorAll(".ops-extra-field")).toHaveLength(6);
    expect(panel.querySelectorAll(".billing-edit-row_extra")).toHaveLength(1);
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
    const journalsTab = await waitUntil(
      () =>
        element.shadowRoot.querySelectorAll("button[data-tab='journals']")[0]
    );
    journalsTab.click();
    await flush();
    const headerText = Array.from(
      element.shadowRoot.querySelectorAll(".ops-table thead th")
    )
      .map((th) => th.textContent.trim())
      .join(" ");
    expect(headerText).not.toContain("確認用");
    expect(headerText).toContain("選択 計上日 借方 貸方 金額 イベント");
    expect(element.shadowRoot.textContent).not.toContain("明細税抜 1,100円");
  });

  it("保存中は請求書情報を止め当該カードに処理中を出す (Core 7.8.2)", async () => {
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview({
      invoiceTransactionStatus: "Draft",
      locked: false
    });
    document.body.appendChild(element);
    const billing = await waitUntil(() =>
      Array.from(element.shadowRoot.querySelectorAll("button")).find(
        (button) => button.textContent.trim() === "請求書情報"
      )
    );
    expect(billing.disabled).toBe(false);
    element.isSaving = true;
    await flush();
    expect(billing.disabled).toBe(true);
    expect(element.shadowRoot.textContent).toContain("処理中");
    expect(element.shadowRoot.querySelector("lightning-spinner")).toBeNull();
  });

  it("発行処理中は当該ボードの請求書情報を止める (Core 7.10)", async () => {
    const proto = OrderInvoicePreviewTable.prototype;
    const waiting = Object.getOwnPropertyDescriptor(
      proto,
      "isDocumentOpsWaiting"
    ).get;
    let release;
    const hang = new Promise((resolve) => {
      release = resolve;
    });
    const ctx = {
      invoiceOpsProcessingId: null,
      invoiceOpsProcessingMode: null,
      invoiceSendState: { invoiceId: "a00INV000000001" },
      invoiceIssueState: { invoiceId: "a00INV000000001" },
      dispatchEvent: jest.fn(),
      reduceInvoiceOpsError: () => ""
    };
    const running = proto.runInvoiceOperation.call(
      ctx,
      "a00INV000000001",
      "issue",
      () => hang
    );
    expect(ctx.invoiceOpsProcessingId).toBe("a00INV000000001");
    expect(ctx.invoiceOpsProcessingMode).toBe("issue");
    expect(waiting.call(ctx)).toBe(true);
    release();
    await running;
    expect(ctx.invoiceOpsProcessingId).toBe(null);
    expect(waiting.call(ctx)).toBe(false);
  });

  it("未確定の入金タブは案内一文だけ (Core 8.9)", async () => {
    getOpsBundle.mockResolvedValue({
      accountingEnabled: true,
      paymentAllowed: false,
      paymentBlockedReason: "請求を確定してから入金できます。",
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
    const element = createElement("c-order-invoice-preview-table", {
      is: OrderInvoicePreviewTable
    });
    element.preview = buildPreview({
      invoiceTransactionStatus: "Draft",
      locked: false
    });
    document.body.appendChild(element);
    const paymentsTab = await waitUntil(() =>
      Array.from(element.shadowRoot.querySelectorAll("button")).find(
        (button) => button.textContent.trim() === "入金"
      )
    );
    paymentsTab.click();
    const guide = await waitUntil(() =>
      Array.from(element.shadowRoot.querySelectorAll("p")).find((p) =>
        p.textContent.includes("請求を確定してから入金できます。")
      )
    );
    expect(guide).toBeTruthy();
    const paymentPanel = element.shadowRoot.querySelector(".ops-panel");
    expect(paymentPanel.textContent).not.toContain("入金はありません。");
    expect(
      Array.from(paymentPanel.querySelectorAll("lightning-input")).some(
        (input) => input.label === "取消済みを含める"
      )
    ).toBe(false);
  });
});
