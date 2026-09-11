import ContractCrossEstimateTile from "c/contractCrossEstimateTile";
import getEstimateIssueContext from "@salesforce/apex/ContractCrossController.getEstimateIssueContext";
import previewEstimateIssueFileName from "@salesforce/apex/ContractCrossController.previewEstimateIssueFileName";
import issueEstimate from "@salesforce/apex/ContractCrossController.issueEstimate";
import { openContentDocumentFilePreview } from "c/orderWizardNavigation";

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

const proto = ContractCrossEstimateTile.prototype;
const INITIAL_ATTACHMENT_KEY = "cmc.estimateSend.initialContentDocumentId";

function bind(overrides = {}) {
  const ctx = {
    tile: {
      id: "a01000000000001AAA",
      historyName: "見積A",
      isEstimate: true,
      amount: 1000,
      taxInclusiveAmount: 1100,
      estimateDate: "2026-04-01",
      validDate: "2026-04-30",
      sendContactName: "担当",
      createdDate: "2026-04-01T00:00:00.000Z",
      createdByName: "作成者",
      lastModifiedByName: "更新者",
      autoRenew: true,
      lines: [
        {
          id: "1",
          typeLabel: "追加",
          productName: "商品",
          unitPrice: 1000,
          unit: "式",
          quantity: 1,
          startDate: "2026-04-01",
          endDate: "2027-03-31",
          cycleCount: 12,
          invoiceSetting: "一括",
          revenueBasis: "検収",
          amount: 1000
        }
      ]
    },
    accountingEnabled: false,
    canIssue: true,
    canSend: true,
    canOrder: true,
    showIssue: false,
    issueBusy: false,
    issueError: "",
    issueSucceeded: false,
    completionNote: "",
    templateKey: "std",
    templateOptions: [],
    issueFileName: "",
    showSendThisFile: false,
    issuedContentDocumentId: "",
    latestIssuedContentDocumentId: "",
    companyBlockedReason: "",
    dispatchEvent: jest.fn(),
    ...overrides
  };
  Object.getOwnPropertyNames(proto).forEach((name) => {
    if (name === "constructor") {
      return;
    }
    const desc = Object.getOwnPropertyDescriptor(proto, name);
    if (!desc || (desc.get && desc.set)) {
      return;
    }
    if (Object.prototype.hasOwnProperty.call(ctx, name)) {
      return;
    }
    if (desc.get && !desc.set) {
      Object.defineProperty(ctx, name, { get: desc.get, configurable: true });
    } else if (typeof desc.value === "function") {
      ctx[name] = desc.value;
    }
  });
  return ctx;
}

describe("contractCrossEstimateTile uncovered (横断画面.md 第5節 / Core 4.8 / 4.10)", () => {
  beforeEach(() => {
    getEstimateIssueContext.mockReset();
    previewEstimateIssueFileName.mockReset();
    issueEstimate.mockReset();
    openContentDocumentFilePreview.mockClear();
    sessionStorage.clear();
  });

  it("period is start〜end and empty dates stay blank (横断画面.md 第5節)", () => {
    const ctx = bind();
    expect(ctx.lines[0].periodLabel).toBe("2026-04-01〜2027-03-31");
    expect(ctx.hasLines).toBe(true);
    expect(ctx.lineCount).toBe(1);
    const empty = bind({
      tile: { id: "a", isEstimate: true, lines: [{ id: "1" }] }
    });
    expect(empty.lines[0].periodLabel).toBe("");
  });

  it("amount labels use ja-JP and skip non-numeric (横断画面.md 第5節)", () => {
    const ctx = bind();
    expect(ctx.amountLabel).toBe((1000).toLocaleString("ja-JP"));
    expect(ctx.taxInclusiveLabel).toBe((1100).toLocaleString("ja-JP"));
    const blank = bind({
      tile: { amount: "", taxInclusiveAmount: "x", estimateDate: "", validDate: null }
    });
    expect(blank.amountLabel).toBe("");
    expect(blank.taxInclusiveLabel).toBe("");
    expect(blank.estimateDateLabel).toBe("");
    expect(blank.validDateLabel).toBe("");
  });

  it("sentAt empty is 未送付; Date values format (横断画面.md 第5節)", () => {
    const ctx = bind();
    expect(ctx.sentLabel).toBe("未送付");
    expect(ctx.historyName).toBe("見積A");
    expect(ctx.sendContactName).toBe("担当");
    expect(ctx.createdByName).toBe("作成者");
    expect(ctx.lastModifiedByName).toBe("更新者");
    expect(ctx.showAutoRenew).toBe(true);
    expect(ctx.createdDateLabel).toBeTruthy();
    const sent = bind({
      tile: { sentAt: "2026-09-01T00:00:00.000Z" }
    });
    expect(sent.sentLabel).toContain("2026");
  });

  it("issue/send buttons only on Estimate with permission (横断画面.md 第5節)", () => {
    const ctx = bind();
    expect(ctx.showIssueButton).toBe(true);
    expect(ctx.showSendButton).toBe(true);
    expect(ctx.showOrderButton).toBe(true);
    const denied = bind({ canIssue: false, canSend: false, canOrder: false });
    expect(denied.showIssueButton).toBe(false);
    expect(denied.showSendButton).toBe(false);
    expect(denied.showOrderButton).toBe(false);
  });

  it("openIssue without history is a no-op", async () => {
    const ctx = bind({ tile: {} });
    await ctx.openIssue();
    expect(getEstimateIssueContext).not.toHaveBeenCalled();
  });

  it("openIssue company block copies reason (Core 4.8 / 1.1.10)", async () => {
    getEstimateIssueContext.mockResolvedValue({
      documentTemplateOptions: [{ label: "標準", value: "std" }],
      defaultDocumentTemplateKey: "std",
      fileName: "a.pdf",
      companyBlockedReason: "会社名を設定してください。",
      latestIssuedContentDocumentId: ""
    });
    const ctx = bind();
    ctx.handleIssueClick();
    await Promise.resolve();
    await Promise.resolve();
    expect(ctx.issueError).toBe("会社名を設定してください。");
    expect(ctx.templateOptions).toEqual([{ label: "標準", value: "std" }]);
  });

  it("openIssue failure uses 見積書を発行できませんでした。", async () => {
    getEstimateIssueContext.mockRejectedValue({});
    const ctx = bind();
    await ctx.openIssue();
    expect(ctx.issueError).toBe("見積書を発行できませんでした。");
  });

  it("template change previews file name (Core 4.8)", async () => {
    previewEstimateIssueFileName.mockResolvedValue("preview.pdf");
    const ctx = bind();
    await ctx.handleTemplateChange({ detail: { value: "std" } });
    expect(ctx.issueFileName).toBe("preview.pdf");
    previewEstimateIssueFileName.mockRejectedValue({
      body: { message: "帳票がありません" }
    });
    await ctx.handleTemplateChange({ detail: { value: "std" } });
    expect(ctx.issueError).toBe("帳票がありません");
    await ctx.handleTemplateChange({ detail: { value: "" } });
  });

  it("issue success shows 見積書を発行しました。 and このファイルを送る (Core 4.8 / 4.10)", async () => {
    issueEstimate.mockResolvedValue({
      contentDocumentId: "069AAA",
      showSendThisFile: true
    });
    const ctx = bind();
    await ctx.handleIssuePdf();
    expect(ctx.completionNote).toBe("見積書を発行しました。");
    expect(ctx.showSendThisFile).toBe(true);
    expect(ctx.dispatchEvent).toHaveBeenCalled();
    ctx.handleIssuePdfPreview();
    expect(openContentDocumentFilePreview).toHaveBeenCalledWith(ctx, "069AAA");
  });

  it("issuePdfDisabled skips Apex", async () => {
    const ctx = bind({ templateKey: "" });
    await ctx.handleIssuePdf();
    expect(issueEstimate).not.toHaveBeenCalled();
  });

  it("issue Apex failure keeps overlay (Core 4.8)", async () => {
    issueEstimate.mockRejectedValue({ message: "発行失敗" });
    const ctx = bind();
    await ctx.handleIssuePdf();
    expect(ctx.issueError).toBe("発行失敗");
    expect(ctx.issueSucceeded).toBe(false);
  });

  it("このファイルを送る stores initial attachment (Core 4.10)", () => {
    const ctx = bind({ issuedContentDocumentId: "069AAA" });
    ctx.handleSendThisFile();
    expect(sessionStorage.getItem(INITIAL_ATTACHMENT_KEY)).toBe("069AAA");
    expect(ctx.showIssue).toBe(false);
    expect(ctx.dispatchEvent).toHaveBeenCalled();
  });

  it("send and order events carry historyId (横断画面.md 第5節)", () => {
    const ctx = bind();
    ctx.handleSendClick();
    ctx.handleOrderClick();
    expect(ctx.dispatchEvent.mock.calls[0][0].detail.historyId).toBe(
      "a01000000000001AAA"
    );
    expect(ctx.dispatchEvent.mock.calls[1][0].detail.historyId).toBe(
      "a01000000000001AAA"
    );
    ctx.handleCloseIssue();
    expect(ctx.showIssue).toBe(false);
  });

  it("historyRecordUrl empty without id (横断画面.md 第1節)", () => {
    const ctx = bind({ tile: {} });
    expect(ctx.historyRecordUrl).toBe("");
    expect(ctx.hasLines).toBe(false);
  });
});
