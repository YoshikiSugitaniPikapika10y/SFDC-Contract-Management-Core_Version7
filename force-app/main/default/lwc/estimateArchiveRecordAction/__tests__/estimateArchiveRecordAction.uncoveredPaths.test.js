import EstimateArchiveRecordAction from "c/estimateArchiveRecordAction";
import archiveEstimate from "@salesforce/apex/EstimateArchiveController.archiveEstimate";
import getArchiveContext from "@salesforce/apex/EstimateArchiveController.getArchiveContext";
import issueEstimateOperationKey from "@salesforce/apex/EstimateCreateController.issueEstimateOperationKey";
import { getRecordNotifyChange } from "lightning/uiRecordApi";
import { resolveSaveErrorAlert } from "c/estimateValidationAlertUtils";
import { CloseActionScreenEvent } from "lightning/actions";
import { RefreshEvent } from "lightning/refresh";

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
  "lightning/uiRecordApi",
  () => ({ getRecordNotifyChange: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateArchiveController.archiveEstimate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateArchiveController.getArchiveContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.issueEstimateOperationKey",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_03_Can_Estimate",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "c/quickActionPanelResize",
  () => ({ resizeQuickActionPanel: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/estimateValidationAlertUtils",
  () => ({ resolveSaveErrorAlert: jest.fn() }),
  { virtual: true }
);

const VERSION_CONFLICT_MESSAGE =
  "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。";
const NON_ESTIMATE_ARCHIVE_MESSAGE =
  "見積状態の契約履歴のみ不採用にできます。";

const proto = EstimateArchiveRecordAction.prototype;

function bind(overrides = {}) {
  const ctx = {
    _recordId: "a01000000000001AAA",
    recordId: "a01000000000001AAA",
    _contextRequestSeq: 0,
    isWorking: false,
    errorMessage: "",
    historyStatus: "Estimate",
    _lastModifiedToken: "tok",
    _pendingOperationKey: "",
    dispatchEvent: jest.fn(),
    ...overrides
  };
  if (ctx.recordId === undefined) {
    ctx.recordId = ctx._recordId;
  }
  Object.getOwnPropertyNames(proto).forEach((name) => {
    if (name === "constructor") {
      return;
    }
    const desc = Object.getOwnPropertyDescriptor(proto, name);
    // @api get/set は VM 必須のため bind では付けない
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

describe("estimateArchiveRecordAction uncovered (Core 5.5 / 4.3.12 / 0.1)", () => {
  beforeEach(() => {
    getArchiveContext.mockReset().mockResolvedValue({
      historyStatus: "Estimate",
      lastModifiedToken: "tok-1"
    });
    archiveEstimate.mockReset().mockResolvedValue({});
    issueEstimateOperationKey.mockReset().mockResolvedValue("op-key-1");
    resolveSaveErrorAlert.mockReset().mockReturnValue({
      messages: [{ text: "保存失敗" }]
    });
    getRecordNotifyChange.mockClear();
  });

  it("subtitle is 不採用 not 破棄 (Core 0.1 / 5.5)", () => {
    const ctx = bind();
    expect(ctx.confirmSubtitle).toBe("見積を不採用にして編集不可にします");
    expect(ctx.confirmSubtitle).not.toMatch(/破棄/);
  });

  it("empty recordId loadContext is a no-op", async () => {
    const ctx = bind({ _recordId: "", recordId: "" });
    await ctx.loadContext();
    expect(getArchiveContext).not.toHaveBeenCalled();
  });

  it("Estimate context clears gate error (Core 5.5 / 1.1.10)", async () => {
    const ctx = bind({ errorMessage: "old", historyStatus: "" });
    await ctx.loadContext();
    expect(ctx.historyStatus).toBe("Estimate");
    expect(ctx._lastModifiedToken).toBe("tok-1");
    expect(ctx.errorMessage).toBe("");
    expect(ctx.isArchiveDisabled).toBe(false);
  });

  it("Ordered context blocks Archive with 不採用 message (Core 5.5)", async () => {
    getArchiveContext.mockResolvedValue({
      historyStatus: "Ordered",
      lastModifiedToken: "tok-o"
    });
    const ctx = bind({ historyStatus: "" });
    await ctx.loadContext();
    expect(ctx.errorMessage).toBe(NON_ESTIMATE_ARCHIVE_MESSAGE);
    expect(ctx.isEstimate).toBe(false);
    expect(ctx.isArchiveDisabled).toBe(true);
  });

  it("stale success response is discarded (Core 4.3.11)", async () => {
    let resolveContext;
    getArchiveContext.mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveContext = resolve;
        })
    );
    const ctx = bind({ historyStatus: "" });
    const first = ctx.loadContext();
    ctx._contextRequestSeq += 1;
    resolveContext({
      historyStatus: "Ordered",
      lastModifiedToken: "stale"
    });
    await first;
    expect(ctx.historyStatus).toBe("");
    expect(ctx.errorMessage).toBe("");
  });

  it("loadContext error shows Apex message (Core 4.3.11)", async () => {
    getArchiveContext.mockRejectedValue(new Error("x"));
    resolveSaveErrorAlert.mockReturnValue({
      messages: [{ text: "照会失敗" }]
    });
    const ctx = bind();
    await ctx.loadContext();
    expect(ctx.errorMessage).toBe("照会失敗");
  });

  it("stale error response is discarded", async () => {
    let rejectContext;
    getArchiveContext.mockImplementation(
      () =>
        new Promise((_, reject) => {
          rejectContext = reject;
        })
    );
    const ctx = bind({ errorMessage: "" });
    const first = ctx.loadContext();
    ctx._recordId = "other";
    rejectContext(new Error("x"));
    await first;
    expect(ctx.errorMessage).toBe("");
  });

  it("handleReloadContext clears error then reloads", async () => {
    const ctx = bind({ errorMessage: "old" });
    await ctx.handleReloadContext();
    expect(getArchiveContext).toHaveBeenCalled();
    expect(ctx.errorMessage).toBe("");
  });

  it("hasPermission / isBusy getters", () => {
    const ctx = bind({ isWorking: true });
    expect(ctx.hasPermission).toBe(true);
    expect(ctx.isBusy).toBe(true);
  });

  it("キャンセル closes without refresh (Core 5.5)", () => {
    const ctx = bind();
    ctx.handleCancel();
    expect(getRecordNotifyChange).not.toHaveBeenCalled();
    expect(ctx.dispatchEvent).toHaveBeenCalledWith(
      expect.any(CloseActionScreenEvent)
    );
  });

  it("アーカイブ成功は操作キー付きで不採用し画面を更新する (Core 5.5 / 4.3.12)", async () => {
    archiveEstimate.mockResolvedValue({ businessOperationKey: "echo-key" });
    const ctx = bind({
      historyStatus: "Estimate",
      _lastModifiedToken: "tok",
      _pendingOperationKey: ""
    });
    await ctx.handleArchive();
    expect(issueEstimateOperationKey).toHaveBeenCalled();
    expect(archiveEstimate).toHaveBeenCalledWith({
      contractHistoryId: "a01000000000001AAA",
      expectedLastModifiedToken: "tok",
      businessOperationKey: "op-key-1"
    });
    expect(ctx._pendingOperationKey).toBe("");
    expect(ctx.isWorking).toBe(false);
    expect(getRecordNotifyChange).toHaveBeenCalledWith([
      { recordId: "a01000000000001AAA" }
    ]);
    expect(ctx.dispatchEvent).toHaveBeenCalledWith(expect.any(RefreshEvent));
    expect(ctx.dispatchEvent).toHaveBeenCalledWith(
      expect.any(CloseActionScreenEvent)
    );
  });

  it("reuses pending operation key without re-issue (Core 4.3.12)", async () => {
    const ctx = bind({
      historyStatus: "Estimate",
      _pendingOperationKey: "keep-key"
    });
    await ctx.handleArchive();
    expect(issueEstimateOperationKey).not.toHaveBeenCalled();
    expect(archiveEstimate).toHaveBeenCalledWith(
      expect.objectContaining({ businessOperationKey: "keep-key" })
    );
  });

  it("版比較失敗はキーを捨てて文脈を読み直す (Core 4.3.12)", async () => {
    archiveEstimate.mockRejectedValue(new Error("conflict"));
    resolveSaveErrorAlert.mockReturnValue({
      messages: [{ text: VERSION_CONFLICT_MESSAGE }]
    });
    getArchiveContext.mockResolvedValue({
      historyStatus: "Estimate",
      lastModifiedToken: "tok-new"
    });
    const ctx = bind({
      historyStatus: "Estimate",
      _pendingOperationKey: "old-key",
      _lastModifiedToken: "tok-old"
    });
    await ctx.handleArchive();
    expect(resolveSaveErrorAlert).toHaveBeenCalled();
    expect(ctx._pendingOperationKey).toBe("");
    expect(ctx._lastModifiedToken).toBe("tok-new");
    expect(getArchiveContext).toHaveBeenCalled();
    expect(ctx.isWorking).toBe(false);
  });

  it("non-version archive error keeps message without close", async () => {
    archiveEstimate.mockRejectedValue(new Error("denied"));
    resolveSaveErrorAlert.mockReturnValue({
      messages: [{ text: "権限なし" }, { text: "詳細" }]
    });
    const ctx = bind({ historyStatus: "Estimate" });
    await ctx.handleArchive();
    expect(ctx.errorMessage).toBe("権限なし\n詳細");
    expect(getRecordNotifyChange).not.toHaveBeenCalled();
  });

  it("disabled Archive does nothing", async () => {
    const ctx = bind({ historyStatus: "Ordered" });
    await ctx.handleArchive();
    expect(archiveEstimate).not.toHaveBeenCalled();
  });
});
