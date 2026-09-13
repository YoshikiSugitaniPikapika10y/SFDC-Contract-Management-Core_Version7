import EstimateSendRecordAction from "c/estimateSendRecordAction";
import getBoardContext from "@salesforce/apex/EstimateSendBoardController.getBoardContext";
import getRecordActionEstimate from "@salesforce/apex/EstimateSendBoardController.getRecordActionEstimate";
import previewEstimate from "@salesforce/apex/EstimateSendBoardController.previewEstimateFromRecordPage";
import sendEstimate from "@salesforce/apex/EstimateSendBoardController.sendEstimateFromRecordPage";
import getBoardContextCross from "@salesforce/apex/ContractCrossController.getEstimateSendBoardContext";
import getRecordActionEstimateCross from "@salesforce/apex/ContractCrossController.getEstimateSendRecord";
import previewEstimateCross from "@salesforce/apex/ContractCrossController.previewEstimateFromRecordPage";
import LightningConfirm from "lightning/confirm";
import { openContentDocumentFilePreview } from "c/orderWizardNavigation";

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
  "lightning/platformShowToastEvent",
  () => ({ ShowToastEvent: class ShowToastEvent {} }),
  { virtual: true }
);
jest.mock(
  "c/orderWizardNavigation",
  () => ({
    NavigationMixin: (Base) => class extends Base {},
    openContentDocumentFilePreview: jest.fn()
  }),
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
  "@salesforce/apex/ContractCrossController.getEstimateSendBoardContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.getEstimateSendRecord",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.previewEstimateFromRecordPage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractCrossController.sendEstimateFromRecordPage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_05_Can_SendEstimate",
  () => ({ default: true }),
  { virtual: true }
);

const proto = EstimateSendRecordAction.prototype;
const INITIAL_ATTACHMENT_KEY = "cmc.estimateSend.initialContentDocumentId";
const REMERGE_NEW =
  "帳票またはメールを変えると、差し込みとファイル名をやり直します。加筆は捨てます。";
const REMERGE_EXISTING =
  "メールを変えると差し込みをやり直します。既存添付は作り直しません。加筆は捨てます。";

function previewPayload(overrides = {}) {
  return {
    fromLabel: "me@example.com",
    fromChoice: "Self",
    operatorEmail: "me@example.com",
    toAddresses: "to@example.com",
    ccAddresses: "",
    bccAddresses: "",
    subject: "件名",
    body: "本文",
    attachmentOptions: [
      { label: "既存", value: "069AAA", fileName: "keep.pdf" },
      { label: "新しく発行する", value: "NEW", fileName: "new.pdf" }
    ],
    attachmentId: "069AAA",
    newIssueFileName: "new.pdf",
    fileName: "keep.pdf",
    documentTemplateKey: "std",
    emailTemplateApiName: "mail",
    ...overrides
  };
}

function bind(overrides = {}) {
  const ctx = {
    _recordId: "a01000000000001AAA",
    estimate: { sendable: true, lastModifiedToken: "tok", historyName: "見積A" },
    documentTemplateKey: "std",
    emailTemplateApiName: "mail",
    documentTemplateOptions: [{ label: "標準", value: "std" }],
    emailTemplateOptions: [{ label: "メール", value: "mail" }],
    fromLabel: "me@example.com",
    fromChoice: "Self",
    operatorEmail: "me@example.com",
    orgFromLabel: "org@example.com",
    orgFromResolved: false,
    toAddresses: "to@example.com",
    ccAddresses: "",
    bccAddresses: "",
    subject: "件名",
    body: "本文",
    fileName: "keep.pdf",
    newIssueFileName: "new.pdf",
    attachmentId: "069AAA",
    attachmentOptions: [
      { label: "既存", value: "069AAA", fileName: "keep.pdf" },
      { label: "新しく発行する", value: "NEW", fileName: "new.pdf" }
    ],
    preferredAttachmentId: "",
    errorMessage: "",
    isLoading: false,
    isSending: false,
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

describe("estimateSendRecordAction uncovered (Core 7.10 / 4.8)", () => {
  beforeEach(() => {
    getBoardContext.mockReset().mockResolvedValue({
      documentTemplateOptions: [{ label: "標準", value: "std" }],
      emailTemplateOptions: [{ label: "メール", value: "mail" }],
      defaultDocumentTemplateKey: "std",
      defaultEmailTemplateApiName: "mail",
      defaultFromChoice: "Self",
      operatorEmail: "me@example.com",
      orgFromLabel: "org@example.com"
    });
    getRecordActionEstimate.mockReset().mockResolvedValue({
      sendable: true,
      lastModifiedToken: "tok",
      historyName: "見積A"
    });
    previewEstimate.mockReset().mockResolvedValue(previewPayload());
    sendEstimate.mockReset().mockResolvedValue({});
    getBoardContextCross.mockReset().mockResolvedValue({
      documentTemplateOptions: [{ label: "標準", value: "std" }],
      emailTemplateOptions: [{ label: "メール", value: "mail" }],
      defaultDocumentTemplateKey: "std",
      defaultEmailTemplateApiName: "mail",
      defaultFromChoice: "Self",
      operatorEmail: "me@example.com",
      orgFromLabel: "org@example.com"
    });
    getRecordActionEstimateCross.mockReset().mockResolvedValue({
      sendable: true,
      lastModifiedToken: "tok",
      historyName: "見積A"
    });
    previewEstimateCross.mockReset().mockResolvedValue(previewPayload());
    LightningConfirm.open.mockReset().mockResolvedValue(true);
    openContentDocumentFilePreview.mockClear();
    sessionStorage.clear();
  });

  it("load fills From 自分 and keeps existing file name on re-preview (Core 7.10)", async () => {
    const ctx = bind({ estimate: undefined, attachmentId: "069AAA", fileName: "keep.pdf" });
    await ctx.load();
    expect(ctx.fromChoice).toBe("Self");
    expect(ctx.fileName).toBe("keep.pdf");
    expect(ctx.toAddresses).toBe("to@example.com");
  });

  it("empty recordId load is a no-op", async () => {
    const ctx = bind({ _recordId: "" });
    await ctx.load();
    expect(getBoardContext).not.toHaveBeenCalled();
  });

  it("cross overlay load uses ContractCrossController (共通基盤 10.4)", async () => {
    const ctx = bind({
      estimate: undefined,
      fromCrossWork: true,
      attachmentId: "069AAA",
      fileName: "keep.pdf"
    });
    await ctx.load();
    expect(getBoardContextCross).toHaveBeenCalled();
    expect(getRecordActionEstimateCross).toHaveBeenCalled();
    expect(getBoardContext).not.toHaveBeenCalled();
    expect(getRecordActionEstimate).not.toHaveBeenCalled();
  });

  it("load error shows Apex message", async () => {
    getBoardContext.mockRejectedValue({ body: { message: "照会失敗" } });
    const ctx = bind({ estimate: undefined });
    await ctx.load();
    expect(ctx.errorMessage).toBe("照会失敗");
    expect(ctx.estimate).toBe(null);
  });

  it("confirm remerge for NEW attachment uses 差し込みとファイル名 (Core 7.10)", async () => {
    const ctx = bind({ attachmentId: "NEW" });
    const ok = await ctx.confirmRemerge();
    expect(ok).toBe(true);
    expect(LightningConfirm.open).toHaveBeenCalledWith(
      expect.objectContaining({ message: REMERGE_NEW, label: "テンプレートを変更" })
    );
    const existing = bind({ attachmentId: "069AAA" });
    await existing.confirmRemerge();
    expect(LightningConfirm.open).toHaveBeenLastCalledWith(
      expect.objectContaining({ message: REMERGE_EXISTING })
    );
  });

  it("document template change rolls back when confirm is no (Core 7.10)", async () => {
    LightningConfirm.open.mockResolvedValue(false);
    const target = { value: "other" };
    const ctx = bind();
    await ctx.handleDocumentTemplateChange({ detail: { value: "other" }, target });
    expect(target.value).toBe("std");
    expect(ctx.documentTemplateKey).toBe("std");
  });

  it("email template change applies after confirm (Core 7.10)", async () => {
    previewEstimate.mockResolvedValue(
      previewPayload({ emailTemplateApiName: "mail2" })
    );
    const ctx = bind();
    await ctx.handleEmailTemplateChange({
      detail: { value: "mail2" },
      target: {}
    });
    expect(ctx.emailTemplateApiName).toBe("mail2");
    expect(previewEstimate).toHaveBeenCalled();
  });

  it("From 自分 uses operator email without remerge (Core 4.8)", async () => {
    const ctx = bind({ fromChoice: "Org", orgFromResolved: true });
    await ctx.handleFromChoiceChange({ detail: { value: "Self" } });
    expect(ctx.fromChoice).toBe("Self");
    expect(ctx.orgFromResolved).toBe(false);
    expect(ctx.fromLabel).toBe("me@example.com");
  });

  it("From 組織 resolves label (Core 4.8 / 11.3.2)", async () => {
    previewEstimate.mockResolvedValue({ fromLabel: "org@example.com" });
    const ctx = bind();
    await ctx.handleFromChoiceChange({ detail: { value: "Org" } });
    expect(ctx.orgFromResolved).toBe(true);
    expect(ctx.isOrgFromUnresolved).toBe(false);
    previewEstimate.mockRejectedValue({ message: "組織From不明" });
    await ctx.handleFromChoiceChange({ detail: { value: "Org" } });
    expect(ctx.orgFromResolved).toBe(false);
    expect(ctx.errorMessage).toBe("組織From不明");
  });

  it("attachment NEW uses newIssueFileName (Core 7.10)", () => {
    const ctx = bind();
    ctx.handleAttachmentChange({ detail: { value: "NEW" } });
    expect(ctx.attachmentId).toBe("NEW");
    expect(ctx.fileName).toBe("new.pdf");
    expect(ctx.showDocumentTemplatePicker).toBe(true);
    ctx.handleAttachmentChange({ detail: { value: "069AAA" } });
    expect(ctx.fileName).toBe("keep.pdf");
    expect(ctx.showExistingFilePreview).toBe(true);
    ctx.handleExistingFilePreview();
    expect(openContentDocumentFilePreview).toHaveBeenCalledWith(ctx, "069AAA");
  });

  it("preferred attachment comes from session key (Core 4.10)", () => {
    sessionStorage.setItem(INITIAL_ATTACHMENT_KEY, "069PREF");
    const ctx = bind();
    expect(ctx.consumePreferredAttachmentId()).toBe("069PREF");
    expect(sessionStorage.getItem(INITIAL_ATTACHMENT_KEY)).toBe(null);
  });

  it("draft change ignores To and writes Cc (Core 4.8)", () => {
    const ctx = bind();
    ctx.handleDraftChange({ target: { name: "ccAddresses", value: "cc@example.com" } });
    expect(ctx.ccAddresses).toBe("cc@example.com");
  });

  it("cancel closes when not sending (Core 7.10)", () => {
    const ctx = bind();
    ctx.handleCancel();
    expect(ctx.dispatchEvent).toHaveBeenCalled();
  });

  it("横断の見積書タイルでは CloseActionScreen しない (横断画面.md 第2.1節)", () => {
    const ctx = bind({ fromCrossWork: true });
    ctx.closePanel();
    const names = ctx.dispatchEvent.mock.calls.map(
      (call) => call[0].type || call[0].constructor.name
    );
    expect(names).toContain("panelclose");
    expect(names).not.toContain("CloseActionScreenEvent");
  });

  it("send failure reloads then keeps failure message (Core 7.10)", async () => {
    sendEstimate.mockRejectedValue({
      body: { message: "見積を送付できませんでした。" }
    });
    const ctx = bind();
    await ctx.handleSend();
    expect(getBoardContext).toHaveBeenCalled();
    expect(ctx.errorMessage).toBe("見積を送付できませんでした。");
    expect(ctx.isSending).toBe(false);
  });

  it("sendDisabled skips Apex (Core 7.10)", async () => {
    const ctx = bind({ toAddresses: "" });
    await ctx.handleSend();
    expect(sendEstimate).not.toHaveBeenCalled();
  });

  it("unavailable and retry (Core 7.10 / 4.8)", () => {
    const ctx = bind({
      estimate: { sendable: false, sendableReason: "受注済みです。" }
    });
    expect(ctx.unavailableMessage).toBe("受注済みです。");
    expect(ctx.hasUnavailableMessage).toBe(true);
    const retry = bind({ errorMessage: "timeout" });
    expect(retry.showLoadRetry).toBe(true);
    retry.load = jest.fn();
    retry.handleLoadRetry();
    expect(retry.load).toHaveBeenCalled();
  });

  it("isSelfFromUnresolved when operator email is blank (Core 4.8)", () => {
    const ctx = bind({ fromChoice: "Self", operatorEmail: "" });
    expect(ctx.isSelfFromUnresolved).toBe(true);
  });

  it("email template change rolls back when confirm is no (Core 7.10)", async () => {
    LightningConfirm.open.mockResolvedValue(false);
    const target = { value: "mail2" };
    const ctx = bind();
    await ctx.handleEmailTemplateChange({
      detail: { value: "mail2" },
      target
    });
    expect(target.value).toBe("mail");
    expect(ctx.emailTemplateApiName).toBe("mail");
  });

  it("Cc empty segments and over-255 are invalid (Core 7.10)", () => {
    const ctx = bind();
    expect(ctx.hasInvalidEmailList("a@example.com, , b@example.com")).toBe(
      false
    );
    expect(ctx.hasInvalidEmailList("a".repeat(256))).toBe(true);
  });
});
