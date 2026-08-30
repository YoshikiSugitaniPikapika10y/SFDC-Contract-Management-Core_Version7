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
});
