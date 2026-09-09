import OrderInvoicePreviewTable from "c/orderInvoicePreviewTable";

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

describe("orderInvoicePreviewTable issue/send gate (Core 11.3.1 / 11.3.2 / 7.10 / 1.1.10)", () => {
  const proto = OrderInvoicePreviewTable.prototype;

  function issueCtx(overrides) {
    return {
      canIssueDocument: true,
      companyBlockedReason: "",
      hasInvoiceDocumentTemplates: true,
      isBlankReasonText: proto.isBlankReasonText,
      ...overrides
    };
  }

  function sendCtx(overrides) {
    return {
      canSendDocument: true,
      invoiceOpsContextError: "",
      hasInvoiceDocumentTemplates: true,
      orgFromResolved: true,
      isBlankReasonText: proto.isBlankReasonText,
      hasInvalidEmailList: proto.hasInvalidEmailList,
      ...overrides
    };
  }

  const sendableInvoice = {
    invoiceDeliveryMethod: "Email",
    billingEmailTo: "to@example.com",
    billingEmailCc: "",
    billingEmailBcc: ""
  };

  it("会社情報空なら発行を止める (Core 11.3.1 / 7.10 / 1.1.10)", () => {
    expect(
      proto.invoiceIssueUnavailableReason.call(
        issueCtx({ companyBlockedReason: "会社名を設定してください。" }),
        true,
        false
      )
    ).toBe("会社名を設定してください。");
  });

  it("会社情報が揃えば発行を止めない", () => {
    expect(
      proto.invoiceIssueUnavailableReason.call(issueCtx(), true, false)
    ).toBe("");
  });

  it("請求用組織送信元空なら送付を止める (Core 11.3.2 / 7.10 / 1.1.10)", () => {
    expect(
      proto.invoiceSendUnavailableReason.call(
        sendCtx({ orgFromResolved: false }),
        sendableInvoice,
        true,
        false
      )
    ).toBe("PDFとメール送付のとき、組織の送信元を選んでください。");
  });

  it("組織送信元が解決済みなら送付を止めない", () => {
    expect(
      proto.invoiceSendUnavailableReason.call(
        sendCtx(),
        sendableInvoice,
        true,
        false
      )
    ).toBe("");
  });

  it("既定0／2以上でもカタログがあれば発行・送付をカタログなしとして止めない (Core 4.8 / 7.10 / 11.3.2)", () => {
    expect(
      proto.invoiceIssueUnavailableReason.call(issueCtx(), true, false)
    ).toBe("");
    expect(
      proto.invoiceSendUnavailableReason.call(
        sendCtx(),
        sendableInvoice,
        true,
        false
      )
    ).toBe("");
  });

  it("カタログ0件なら発行・送付を止める (Core 4.8 / 7.10 / 11.3.2)", () => {
    expect(
      proto.invoiceIssueUnavailableReason.call(
        issueCtx({ hasInvoiceDocumentTemplates: false }),
        true,
        false
      )
    ).toBe("対象がありません。");
    expect(
      proto.invoiceSendUnavailableReason.call(
        sendCtx({ hasInvoiceDocumentTemplates: false }),
        sendableInvoice,
        true,
        false
      )
    ).toBe("対象がありません。");
  });

  it("発行画面は最新発行PDFのダウンロードURLを出す (横断画面.md 操作21)", () => {
    expect(proto.issuedPdfDownloadUrl.call({}, "069000000000001AAA")).toBe(
      "/sfc/servlet.shepherd/document/download/069000000000001AAA"
    );
    expect(proto.issuedPdfDownloadUrl.call({}, "")).toBe("");
  });
});
