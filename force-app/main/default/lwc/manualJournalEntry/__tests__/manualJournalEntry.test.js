import { createElement } from "lwc";
import ManualJournalEntry from "c/manualJournalEntry";
import previewCancelManualJournal from "@salesforce/apex/ManualJournalController.previewCancel";
import previewRegisterManualJournal from "@salesforce/apex/ManualJournalController.previewRegister";
import registerManualJournal from "@salesforce/apex/ManualJournalController.register";
import LightningConfirm from "lightning/confirm";

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
  "@salesforce/apex/ManualJournalController.previewRegister",
  () => ({ default: jest.fn() }),
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

jest.mock(
  "@salesforce/apex/InvoicePreviewOpsController.issueInvoiceOperationKey",
  () => ({ default: jest.fn().mockResolvedValue("op-key-1") }),
  { virtual: true }
);

const OPERATION_DAY = "2026-08-29";

async function flush() {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

describe("manualJournalEntry", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows 有効 and 取消済 instead of saved status values", async () => {
    const element = createElement("c-manual-journal-entry", {
      is: ManualJournalEntry
    });
    element.invoiceId = "a00INV000000001";
    element.headers = [
      {
        headerId: "a05MJH000000001",
        settingName: "為替差損",
        postingDate: "2026-06-01",
        amount: 100,
        transactionStatus: "Active",
        canCancel: true,
        hasLockedJournals: false
      },
      {
        headerId: "a05MJH000000002",
        settingName: "雑収入",
        postingDate: "2026-06-02",
        amount: 50,
        transactionStatus: "Cancelled",
        canCancel: false,
        hasLockedJournals: false
      }
    ];
    document.body.appendChild(element);
    await flush();

    const text = element.shadowRoot.textContent;
    expect(text).toContain("有効");
    expect(text).toContain("取消済");
    expect(text).not.toContain("Active");
    expect(text).not.toContain("Cancelled");
  });

  it("shows setting Name as the menu label and Description as confirmable text (CHANGE-250)", async () => {
    const element = createElement("c-manual-journal-entry", {
      is: ManualJournalEntry
    });
    element.invoiceId = "a00INV000000001";
    element.operationDay = OPERATION_DAY;
    element.settings = [
      {
        settingId: "a06SET000000001",
        label: "為替差損の計上",
        description: "入金不足が為替変動による場合"
      }
    ];
    document.body.appendChild(element);
    await flush();

    const combobox = element.shadowRoot.querySelector(
      'lightning-combobox[data-field="settingId"]'
    );
    expect(combobox.options).toEqual([
      {
        label: "為替差損の計上",
        value: "a06SET000000001",
        description: "入金不足が為替変動による場合"
      }
    ]);
    expect(element.shadowRoot.textContent).not.toContain(
      "入金不足が為替変動による場合"
    );

    combobox.dispatchEvent(
      new CustomEvent("change", { detail: { value: "a06SET000000001" } })
    );
    await flush();

    expect(
      element.shadowRoot.querySelector("p.setting-description").textContent
    ).toBe("入金不足が為替変動による場合");
  });

  it("seeds cancel date to the operation day only when the header has locked journals", async () => {
    const element = createElement("c-manual-journal-entry", {
      is: ManualJournalEntry
    });
    element.invoiceId = "a00INV000000001";
    element.operationDay = OPERATION_DAY;
    element.headers = [
      {
        headerId: "a05MJH000000001",
        settingName: "為替差損",
        postingDate: "2026-06-01",
        amount: 100,
        transactionStatus: "Active",
        canCancel: true,
        hasLockedJournals: true
      }
    ];
    document.body.appendChild(element);
    await flush();

    element.shadowRoot
      .querySelector("button[data-header-id='a05MJH000000001']")
      .click();
    await flush();

    const dateInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="cancelDate"]'
    );
    expect(dateInput).not.toBeNull();
    expect(dateInput.value).toBe(OPERATION_DAY);
  });

  it("seeds posting date from the organization operation day", async () => {
    const element = createElement("c-manual-journal-entry", {
      is: ManualJournalEntry
    });
    element.invoiceId = "a00INV000000001";
    element.operationDay = OPERATION_DAY;
    document.body.appendChild(element);
    await flush();

    const dateInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="postingDate"]'
    );
    expect(dateInput.value).toBe(OPERATION_DAY);
  });

  it("omits cancel date when the header has no locked journals", async () => {
    const element = createElement("c-manual-journal-entry", {
      is: ManualJournalEntry
    });
    element.invoiceId = "a00INV000000001";
    element.headers = [
      {
        headerId: "a05MJH000000001",
        settingName: "為替差損",
        postingDate: "2026-06-01",
        amount: 100,
        transactionStatus: "Active",
        canCancel: true,
        hasLockedJournals: false
      }
    ];
    document.body.appendChild(element);
    await flush();

    element.shadowRoot
      .querySelector("button[data-header-id='a05MJH000000001']")
      .click();
    await flush();

    expect(
      element.shadowRoot.querySelector(
        'lightning-input[data-field="cancelDate"]'
      )
    ).toBeNull();
  });

  it("shows journal cancel preview counts before confirming manual journal cancel", async () => {
    previewCancelManualJournal.mockResolvedValue({
      displayText: "論理削除件数: 1\n逆仕訳件数: 0\n実際の逆仕訳日:\nなし\n将来日付: なし"
    });
    LightningConfirm.open.mockResolvedValue(true);
    const element = createElement("c-manual-journal-entry", {
      is: ManualJournalEntry
    });
    element.invoiceId = "a00INV000000001";
    element.contractHistoryId = "a0H000000000001AAA";
    element.headers = [
      {
        headerId: "a05MJH000000001",
        settingName: "為替差損",
        postingDate: "2026-06-01",
        amount: 100,
        transactionStatus: "Active",
        canCancel: true,
        hasLockedJournals: false
      }
    ];
    document.body.appendChild(element);
    await flush();

    element.shadowRoot
      .querySelector("button[data-header-id='a05MJH000000001']")
      .click();
    await flush();

    const reason = element.shadowRoot.querySelector(
      'lightning-combobox[data-field="cancelReason"]'
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

    expect(previewCancelManualJournal).toHaveBeenCalledWith({
      headerId: "a05MJH000000001",
      cancellationDate: null,
      contractHistoryId: "a0H000000000001AAA"
    });
    expect(LightningConfirm.open).toHaveBeenCalledWith(
      expect.objectContaining({
        message: expect.stringContaining("論理削除件数: 1")
      })
    );
  });

  it("disables register when amount is a positive decimal", async () => {
    const element = createElement("c-manual-journal-entry", {
      is: ManualJournalEntry
    });
    element.invoiceId = "a00INV000000001";
    element.operationDay = OPERATION_DAY;
    element.settings = [{ settingId: "a06SET000000001", label: "為替差損" }];
    document.body.appendChild(element);
    await flush();

    const setting = element.shadowRoot.querySelector(
      'lightning-combobox[data-field="settingId"]'
    );
    setting.dispatchEvent(
      new CustomEvent("change", { detail: { value: "a06SET000000001" } })
    );
    const amount = element.shadowRoot.querySelector(
      'lightning-input[data-field="amount"]'
    );
    amount.dispatchEvent(
      new CustomEvent("change", { detail: { value: "100.5" } })
    );
    await flush();

    const register = Array.from(
      element.shadowRoot.querySelectorAll("button.solid-btn")
    ).find((button) => button.textContent.trim() === "登録");
    expect(register.disabled).toBe(true);
  });

  it("seeds register cancel date only when the invoice has locked journals (CHANGE-245)", async () => {
    const element = createElement("c-manual-journal-entry", {
      is: ManualJournalEntry
    });
    element.invoiceId = "a00INV000000001";
    element.operationDay = OPERATION_DAY;
    element.hasLockedJournals = true;
    document.body.appendChild(element);
    await flush();

    const dateInput = element.shadowRoot.querySelector(
      'lightning-input[data-field="registerCancelDate"]'
    );
    expect(dateInput).not.toBeNull();
    expect(dateInput.value).toBe(OPERATION_DAY);
  });

  it("omits register cancel date when the invoice has no locked journals (CHANGE-245)", async () => {
    const element = createElement("c-manual-journal-entry", {
      is: ManualJournalEntry
    });
    element.invoiceId = "a00INV000000001";
    element.operationDay = OPERATION_DAY;
    element.hasLockedJournals = false;
    document.body.appendChild(element);
    await flush();

    expect(
      element.shadowRoot.querySelector(
        'lightning-input[data-field="registerCancelDate"]'
      )
    ).toBeNull();
  });

  it("shows journal preview counts before confirming manual journal register (CHANGE-245)", async () => {
    previewRegisterManualJournal.mockResolvedValue({
      displayText: "論理削除件数: 1\n逆仕訳件数: 0\n実際の逆仕訳日:\nなし\n将来日付: なし"
    });
    LightningConfirm.open.mockResolvedValue(true);
    registerManualJournal.mockResolvedValue("a05MJH000000099");
    const element = createElement("c-manual-journal-entry", {
      is: ManualJournalEntry
    });
    element.invoiceId = "a00INV000000001";
    element.contractHistoryId = "a0H000000000001AAA";
    element.operationDay = OPERATION_DAY;
    element.hasLockedJournals = false;
    element.settings = [{ settingId: "a06SET000000001", label: "為替差損" }];
    document.body.appendChild(element);
    await flush();

    const setting = element.shadowRoot.querySelector(
      'lightning-combobox[data-field="settingId"]'
    );
    setting.dispatchEvent(
      new CustomEvent("change", { detail: { value: "a06SET000000001" } })
    );
    const amount = element.shadowRoot.querySelector(
      'lightning-input[data-field="amount"]'
    );
    amount.dispatchEvent(
      new CustomEvent("change", { detail: { value: "100" } })
    );
    await flush();

    Array.from(element.shadowRoot.querySelectorAll("button.solid-btn"))
      .find((button) => button.textContent.trim() === "登録")
      .click();
    await flush();
    await flush();

    expect(previewRegisterManualJournal).toHaveBeenCalledWith({
      invoiceId: "a00INV000000001",
      settingId: "a06SET000000001",
      postingDate: OPERATION_DAY,
      amount: 100,
      cancellationDate: null,
      expectedToken: undefined,
      contractHistoryId: "a0H000000000001AAA"
    });
    expect(LightningConfirm.open).toHaveBeenCalledWith(
      expect.objectContaining({
        message: expect.stringContaining("論理削除件数: 1")
      })
    );
    expect(registerManualJournal).toHaveBeenCalledWith(
      expect.objectContaining({
        cancellationDate: null,
        amount: 100
      })
    );
  });

  it("does not register when the preview confirm is cancelled (CHANGE-245)", async () => {
    previewRegisterManualJournal.mockResolvedValue({
      displayText: "論理削除件数: 0"
    });
    LightningConfirm.open.mockResolvedValue(false);
    const element = createElement("c-manual-journal-entry", {
      is: ManualJournalEntry
    });
    element.invoiceId = "a00INV000000001";
    element.operationDay = OPERATION_DAY;
    element.settings = [{ settingId: "a06SET000000001", label: "為替差損" }];
    document.body.appendChild(element);
    await flush();

    const setting = element.shadowRoot.querySelector(
      'lightning-combobox[data-field="settingId"]'
    );
    setting.dispatchEvent(
      new CustomEvent("change", { detail: { value: "a06SET000000001" } })
    );
    const amount = element.shadowRoot.querySelector(
      'lightning-input[data-field="amount"]'
    );
    amount.dispatchEvent(
      new CustomEvent("change", { detail: { value: "100" } })
    );
    await flush();

    Array.from(element.shadowRoot.querySelectorAll("button.solid-btn"))
      .find((button) => button.textContent.trim() === "登録")
      .click();
    await flush();
    await flush();

    expect(registerManualJournal).not.toHaveBeenCalled();
  });

  it("passes register cancel date when the invoice has locked journals (CHANGE-245)", async () => {
    previewRegisterManualJournal.mockResolvedValue({
      displayText: "逆仕訳件数: 1"
    });
    LightningConfirm.open.mockResolvedValue(true);
    registerManualJournal.mockResolvedValue("a05MJH000000099");
    const element = createElement("c-manual-journal-entry", {
      is: ManualJournalEntry
    });
    element.invoiceId = "a00INV000000001";
    element.operationDay = OPERATION_DAY;
    element.hasLockedJournals = true;
    element.settings = [{ settingId: "a06SET000000001", label: "為替差損" }];
    document.body.appendChild(element);
    await flush();

    const setting = element.shadowRoot.querySelector(
      'lightning-combobox[data-field="settingId"]'
    );
    setting.dispatchEvent(
      new CustomEvent("change", { detail: { value: "a06SET000000001" } })
    );
    const amount = element.shadowRoot.querySelector(
      'lightning-input[data-field="amount"]'
    );
    amount.dispatchEvent(
      new CustomEvent("change", { detail: { value: "100" } })
    );
    await flush();

    Array.from(element.shadowRoot.querySelectorAll("button.solid-btn"))
      .find((button) => button.textContent.trim() === "登録")
      .click();
    await flush();
    await flush();

    expect(previewRegisterManualJournal).toHaveBeenCalledWith(
      expect.objectContaining({
        cancellationDate: OPERATION_DAY
      })
    );
    expect(registerManualJournal).toHaveBeenCalledWith(
      expect.objectContaining({
        cancellationDate: OPERATION_DAY
      })
    );
  });
});
