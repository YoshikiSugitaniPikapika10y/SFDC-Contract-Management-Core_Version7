import ContractCrossEstimateTile from "c/contractCrossEstimateTile";
import getEstimateIssueContext from "@salesforce/apex/ContractCrossController.getEstimateIssueContext";

jest.mock("lightning/platformShowToastEvent", () => ({ ShowToastEvent: class {} }), {
  virtual: true
});
jest.mock(
  "c/orderWizardNavigation",
  () => ({
    NavigationMixin: (Base) => class extends Base {},
    openContentDocumentFilePreview: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.getEstimateIssueContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.previewEstimateIssueFileName",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.issueEstimate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

describe("contractCrossEstimateTile issue gate (Core 4.8 / 1.1.10)", () => {
  const proto = ContractCrossEstimateTile.prototype;
  const issuePdfDisabled = Object.getOwnPropertyDescriptor(
    proto,
    "issuePdfDisabled"
  ).get;

  function ctx(overrides) {
    return {
      issueBusy: false,
      templateKey: "std",
      companyBlockedReason: "",
      isBlankText: proto.isBlankText,
      ...overrides
    };
  }

  it("帳票未選択なら発行するを押せない", () => {
    expect(issuePdfDisabled.call(ctx({ templateKey: "" }))).toBe(true);
    expect(issuePdfDisabled.call(ctx({ templateKey: "   " }))).toBe(true);
  });

  it("会社情報空なら発行するを押せない", () => {
    expect(
      issuePdfDisabled.call(
        ctx({ companyBlockedReason: "会社名を設定してください。" })
      )
    ).toBe(true);
  });

  it("帳票があれば発行するを押せる", () => {
    expect(issuePdfDisabled.call(ctx({ templateKey: "std" }))).toBe(false);
  });

  it("発行を開いても実行前のプレビュー対象は空 (Core 4.8)", async () => {
    getEstimateIssueContext.mockResolvedValue({
      documentTemplateOptions: [],
      defaultDocumentTemplateKey: "std",
      fileName: "a.pdf",
      companyBlockedReason: "",
      latestIssuedContentDocumentId: "069000000000001AAA"
    });
    const tile = {
      tile: { id: "a" },
      isBlankText: proto.isBlankText,
      issueSucceeded: false,
      issuedContentDocumentId: ""
    };
    await proto.openIssue.call(tile);
    expect(tile.latestIssuedContentDocumentId).toBe("069000000000001AAA");
    expect(tile.issueSucceeded).toBe(false);
    const showIssuePdfPreview = Object.getOwnPropertyDescriptor(
      proto,
      "showIssuePdfPreview"
    ).get;
    expect(showIssuePdfPreview.call(tile)).toBe(false);
  });

  it("最新発行が無ければ発行開きのプレビュー対象は空 (Core 4.8)", async () => {
    getEstimateIssueContext.mockResolvedValue({
      documentTemplateOptions: [],
      defaultDocumentTemplateKey: "std",
      fileName: "a.pdf",
      companyBlockedReason: "",
      latestIssuedContentDocumentId: ""
    });
    const tile = {
      tile: { id: "a" },
      isBlankText: proto.isBlankText
    };
    await proto.openIssue.call(tile);
    expect(tile.latestIssuedContentDocumentId).toBe("");
  });

  it("発行成功後だけダウンロードURLを出す (Core 4.8)", () => {
    const latestPdfDownloadUrl = Object.getOwnPropertyDescriptor(
      proto,
      "latestPdfDownloadUrl"
    ).get;
    expect(
      latestPdfDownloadUrl.call({
        issuedContentDocumentId: "",
        latestIssuedContentDocumentId: "069000000000001AAA"
      })
    ).toBe("");
    expect(
      latestPdfDownloadUrl.call({
        issuedContentDocumentId: "069000000000002AAA",
        latestIssuedContentDocumentId: "069000000000001AAA"
      })
    ).toBe("/sfc/servlet.shepherd/document/download/069000000000002AAA");
  });

  it("印付き最新があるとき「最新のPDFを見る」を出す (横断画面.md 第5節)", () => {
    const showViewPdfAction = Object.getOwnPropertyDescriptor(
      proto,
      "showViewPdfAction"
    ).get;
    const viewPdfDocumentId = Object.getOwnPropertyDescriptor(
      proto,
      "viewPdfDocumentId"
    ).get;
    const withFile = {
      isEstimate: true,
      issuedContentDocumentId: "",
      latestIssuedContentDocumentId: "",
      tile: { latestIssuedContentDocumentId: "069000000000001AAA" },
      isBlankText: proto.isBlankText
    };
    Object.defineProperty(withFile, "viewPdfDocumentId", {
      get: viewPdfDocumentId
    });
    expect(showViewPdfAction.call(withFile)).toBe(true);
    const withoutFile = {
      isEstimate: true,
      issuedContentDocumentId: "",
      latestIssuedContentDocumentId: "",
      tile: { latestIssuedContentDocumentId: "" },
      isBlankText: proto.isBlankText
    };
    Object.defineProperty(withoutFile, "viewPdfDocumentId", {
      get: viewPdfDocumentId
    });
    expect(showViewPdfAction.call(withoutFile)).toBe(false);
  });
});
