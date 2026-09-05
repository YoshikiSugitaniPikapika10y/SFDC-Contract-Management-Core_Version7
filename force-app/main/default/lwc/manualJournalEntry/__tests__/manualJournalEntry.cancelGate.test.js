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

  it("lists the five Accounting 2.4 cancel reasons", () => {
    const options = Object.getOwnPropertyDescriptor(
      proto,
      "cancelReasonOptions"
    ).get.call({});
    expect(options).toEqual([
      { label: "金額・日付などの誤り", value: "AmountOrDateError" },
      { label: "登録先の誤り", value: "WrongDestination" },
      { label: "重複登録", value: "Duplicate" },
      { label: "元取引の変更・取消", value: "SourceChanged" },
      { label: "その他", value: "Other" }
    ]);
  });

  it("does not require extra text unless the reason is その他 (Accounting 2.4)", () => {
    const textRequired = Object.getOwnPropertyDescriptor(
      proto,
      "cancelReasonTextRequired"
    ).get;
    expect(textRequired.call({ cancelReason: "Duplicate" })).toBe(false);
    expect(textRequired.call({ cancelReason: "Other" })).toBe(true);
    expect(
      cancelConfirmDisabled.call({
        busy: false,
        cancelReason: "Duplicate",
        cancelReasonText: "",
        cancelRequiresDate: false,
        isBlankReasonText: proto.isBlankReasonText
      })
    ).toBe(false);
  });
});
