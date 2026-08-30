import ManualJournalEntry from "c/manualJournalEntry";
import previewCancelManualJournal from "@salesforce/apex/ManualJournalController.previewCancel";

jest.mock(
  "@salesforce/apex/ManualJournalController.previewCancel",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ManualJournalController.cancel",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ManualJournalController.register",
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
  () => ({ default: { open: jest.fn() }, open: jest.fn() }),
  { virtual: true }
);

describe("manualJournalEntry cancel gate (Accounting 2.4 / 10.4 / Core 1.1.10)", () => {
  const proto = ManualJournalEntry.prototype;
  const cancelConfirmDisabled = Object.getOwnPropertyDescriptor(
    proto,
    "cancelConfirmDisabled"
  ).get;

  afterEach(() => {
    jest.clearAllMocks();
  });

  it("その他の理由テキスト空白のみは取消を進めない", async () => {
    const dispatchEvent = jest.fn();
    await proto.handleCancel.call({
      cancelHeaderId: "a05MJH000000001",
      cancelReason: "Other",
      cancelReasonText: "   ",
      busy: false,
      isBlankReasonText: proto.isBlankReasonText,
      dispatchEvent
    });
    expect(previewCancelManualJournal).not.toHaveBeenCalled();
    expect(dispatchEvent).toHaveBeenCalled();
    expect(dispatchEvent.mock.calls[0][0].detail.message).toBe(
      "取消理由がその他のときは内容を入力してください。"
    );
  });

  it("その他の理由テキスト空白のみは取消ボタンを非活性にする", () => {
    expect(
      cancelConfirmDisabled.call({
        busy: false,
        cancelReason: "Other",
        cancelReasonText: "   ",
        cancelRequiresDate: false,
        isBlankReasonText: proto.isBlankReasonText
      })
    ).toBe(true);
  });
});
