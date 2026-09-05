import EstimateSendRecordAction from "c/estimateSendRecordAction";

jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
  { virtual: true }
);
jest.mock(
  "lightning/refresh",
  () => ({ RefreshEvent: class RefreshEvent {} }),
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

jest.mock(
  "@salesforce/apex/EstimateSendBoardController.getBoardContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateSendBoardController.getRecordActionEstimate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateSendBoardController.previewEstimateFromRecordPage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateSendBoardController.sendEstimateFromRecordPage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_05_Can_SendEstimate",
  () => ({ default: true }),
  { virtual: true }
);

describe("estimateSendRecordAction send gate (Core 7.10 / 1.1.10)", () => {
  const proto = EstimateSendRecordAction.prototype;
  const sendDisabled = Object.getOwnPropertyDescriptor(
    proto,
    "sendDisabled"
  ).get;

  function ctx(overrides) {
    return {
      isLoading: false,
      isSending: false,
      estimate: { sendable: true },
      documentTemplateKey: "tpl",
      emailTemplateApiName: "email",
      toAddresses: "to@example.com",
      attachmentId: "a01",
      fileName: "estimate.pdf",
      ccAddresses: "",
      bccAddresses: "",
      hasInvalidEmailList: proto.hasInvalidEmailList,
      isBlankText: proto.isBlankText,
      ...overrides
    };
  }

  it("Ccの不正アドレスなら送れない", () => {
    expect(sendDisabled.call(ctx({ ccAddresses: "not-an-email" }))).toBe(true);
  });

  it("Bccの不正アドレスなら送れない", () => {
    expect(sendDisabled.call(ctx({ bccAddresses: "also-invalid" }))).toBe(
      true
    );
  });

  it("Cc／Bccが空なら止めない", () => {
    expect(sendDisabled.call(ctx())).toBe(false);
  });

  it("正しいCcは送れる", () => {
    expect(
      sendDisabled.call(ctx({ ccAddresses: "a@example.com, b@example.com" }))
    ).toBe(false);
  });

  it("添付名空白のみなら送れない (Core 7.10 / 1.1.10)", () => {
    expect(sendDisabled.call(ctx({ fileName: "   " }))).toBe(true);
    expect(sendDisabled.call(ctx({ fileName: "estimate.pdf" }))).toBe(false);
  });

  it("From=組織かつ未解決なら送れない (Core 4.8 / 11.3.2 / 1.1.10)", () => {
    expect(
      sendDisabled.call(ctx({ fromChoice: "Org", orgFromResolved: false }))
    ).toBe(true);
  });

  it("From=組織かつ解決済みなら送れる (Core 4.8 / 11.3.2)", () => {
    expect(
      sendDisabled.call(ctx({ fromChoice: "Org", orgFromResolved: true }))
    ).toBe(false);
  });

  it("From=自分かつ操作者メール空なら送れない (Core 4.8 / 7.10 / 11.3.2)", () => {
    expect(
      sendDisabled.call(
        ctx({ fromChoice: "Self", operatorEmail: "", isBlankText: proto.isBlankText })
      )
    ).toBe(true);
    expect(
      sendDisabled.call(
        ctx({
          fromChoice: "Self",
          operatorEmail: "   ",
          isBlankText: proto.isBlankText
        })
      )
    ).toBe(true);
  });

  it("From=自分かつ操作者メールがあれば送れる (Core 4.8 / 7.10 / 11.3.2)", () => {
    expect(
      sendDisabled.call(
        ctx({
          fromChoice: "Self",
          operatorEmail: "me@example.com",
          isBlankText: proto.isBlankText
        })
      )
    ).toBe(false);
  });

  it("Toが空なら送れない。この画面ではToを直さない (Core 4.8)", () => {
    expect(sendDisabled.call(ctx({ toAddresses: "" }))).toBe(true);
    const draft = { toAddresses: "to@example.com" };
    proto.handleDraftChange.call(draft, {
      target: { name: "toAddresses", value: "hacked@example.com" }
    });
    expect(draft.toAddresses).toBe("to@example.com");
  });

  it("未送付は送付する、送付済みは再送する (Core 4.8)", () => {
    const sendButtonLabel = Object.getOwnPropertyDescriptor(
      proto,
      "sendButtonLabel"
    ).get;
    const isResend = Object.getOwnPropertyDescriptor(proto, "isResend").get;
    expect(isResend.call({ estimate: {} })).toBe(false);
    expect(sendButtonLabel.call({ isResend: false })).toBe("送付する");
    expect(
      isResend.call({ estimate: { estimateSentAt: "2026-09-01T00:00:00.000Z" } })
    ).toBe(true);
    expect(sendButtonLabel.call({ isResend: true })).toBe("再送する");
  });

  it("失敗のあと送り直す注記と送れない理由を本文どおり出す (Core 7.10 / 4.8)", () => {
    const sendFailureRetryNote = Object.getOwnPropertyDescriptor(
      proto,
      "sendFailureRetryNote"
    ).get;
    const unavailableMessage = Object.getOwnPropertyDescriptor(
      proto,
      "unavailableMessage"
    ).get;
    const fromChoiceOptions = Object.getOwnPropertyDescriptor(
      proto,
      "fromChoiceOptions"
    ).get;
    expect(sendFailureRetryNote.call({})).toBe(
      "失敗のあと送り直すと、先のメールが届いていることがある"
    );
    expect(unavailableMessage.call({ estimate: { sendable: false } })).toBe(
      "この見積は送付できません。"
    );
    expect(fromChoiceOptions.call({})).toEqual([
      { label: "自分", value: "Self" },
      { label: "組織", value: "Org" }
    ]);
  });
});
