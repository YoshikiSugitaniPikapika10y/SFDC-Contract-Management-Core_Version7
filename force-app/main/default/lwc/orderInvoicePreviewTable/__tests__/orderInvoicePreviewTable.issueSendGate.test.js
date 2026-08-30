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
      defaultInvoiceDocumentTemplateKey: "StandardInvoice",
      isBlankReasonText: proto.isBlankReasonText,
      ...overrides
    };
  }

  function sendCtx(overrides) {
    return {
      canSendDocument: true,
      invoiceOpsContextError: "",
      defaultInvoiceDocumentTemplateKey: "StandardInvoice",
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

  it("発行画面は最新発行PDFのプレビューとダウンロードURLを出す (横断画面.md 操作21)", () => {
    expect(
      proto.issuedPdfPreviewUrl.call(
        {},
        "069000000000001AAA"
      )
    ).toBe("/lightning/r/ContentDocument/069000000000001AAA/view");
    expect(proto.issuedPdfDownloadUrl.call({}, "069000000000001AAA")).toBe(
      "/sfc/servlet.shepherd/document/download/069000000000001AAA"
    );
    expect(proto.issuedPdfPreviewUrl.call({}, "")).toBe("");
    expect(proto.issuedPdfDownloadUrl.call({}, "")).toBe("");
  });
});
