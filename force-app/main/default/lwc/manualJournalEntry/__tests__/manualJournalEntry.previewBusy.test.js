import ManualJournalEntry from "c/manualJournalEntry";
import previewRegisterManualJournal from "@salesforce/apex/ManualJournalController.previewRegister";
import previewCancelManualJournal from "@salesforce/apex/ManualJournalController.previewCancel";
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
  "@salesforce/apex/InvoicePreviewOpsController.issueInvoiceOperationKey",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/confirm",
  () => ({ default: { open: jest.fn() } }),
  { virtual: true }
);
jest.mock(
  "lightning/platformShowToastEvent",
  () => ({ ShowToastEvent: class ShowToastEvent {} }),
  { virtual: true }
);

describe("manualJournalEntry preview busy (Accounting 10.3 / 8.8)", () => {
  const proto = ManualJournalEntry.prototype;

  afterEach(() => {
    previewRegisterManualJournal.mockReset();
    previewCancelManualJournal.mockReset();
    LightningConfirm.open.mockReset();
  });

  it("件数プレビュー中の二度目の登録は動かない", async () => {
    let resolvePreview;
    previewRegisterManualJournal.mockReturnValue(
      new Promise((resolve) => {
        resolvePreview = resolve;
      })
    );
    const ctx = {
      busy: false,
      registerDisabled: false,
      amount: 100,
      registerRequiresDate: false,
      invoiceId: "a00",
      settingId: "a06",
      postingDate: "2026-09-01",
      expectedToken: "t",
      contractHistoryId: "a0H",
      dispatchEvent: jest.fn()
    };
    const first = proto.handleRegister.call(ctx);
    expect(ctx.busy).toBe(true);
    await proto.handleRegister.call(ctx);
    expect(previewRegisterManualJournal).toHaveBeenCalledTimes(1);
    resolvePreview({ displayText: "論理削除件数: 0" });
    LightningConfirm.open.mockResolvedValue(false);
    await first;
    expect(ctx.busy).toBe(false);
  });

  it("件数プレビュー中の二度目の取消は動かない", async () => {
    let resolvePreview;
    previewCancelManualJournal.mockReturnValue(
      new Promise((resolve) => {
        resolvePreview = resolve;
      })
    );
    const ctx = {
      busy: false,
      cancelHeaderId: "a05",
      cancelReason: "Duplicate",
      cancelReasonText: "",
      cancelRequiresDate: false,
      isBlankReasonText: proto.isBlankReasonText,
      dispatchEvent: jest.fn()
    };
    const first = proto.handleCancel.call(ctx);
    expect(ctx.busy).toBe(true);
    await proto.handleCancel.call(ctx);
    expect(previewCancelManualJournal).toHaveBeenCalledTimes(1);
    resolvePreview({ displayText: "逆仕訳件数: 0" });
    LightningConfirm.open.mockResolvedValue(false);
    await first;
    expect(ctx.busy).toBe(false);
  });
});
