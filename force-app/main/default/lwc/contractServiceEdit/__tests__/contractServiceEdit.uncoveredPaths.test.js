import ContractServiceEdit from "c/contractServiceEdit";
import getContext from "@salesforce/apex/ContractServiceEditController.getContext";
import save from "@salesforce/apex/ContractServiceEditController.save";
import issueContractServiceOperationKey from "@salesforce/apex/ContractServiceEditController.issueContractServiceOperationKey";
import getContractServiceFieldDefinitions from "@salesforce/apex/ContractWizardFieldService.getContractServiceFieldDefinitions";
import {
  buildCustomFieldInputs,
  validateCustomFieldMaps
} from "c/estimateWizardCustomFields";
import { CloseActionScreenEvent } from "lightning/actions";

jest.mock(
  "lightning/actions",
  () => ({ CloseActionScreenEvent: class CloseActionScreenEvent {} }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractServiceEditController.getContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractServiceEditController.save",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractServiceEditController.issueContractServiceOperationKey",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractWizardFieldService.getContractServiceFieldDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Loop_08_Can_EditService",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "c/estimateWizardCustomFields",
  () => ({
    buildCustomFieldInputs: jest.fn(() => []),
    validateCustomFieldMaps: jest.fn(() => null)
  }),
  { virtual: true }
);

const VERSION_CONFLICT_MESSAGE =
  "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。";

const proto = ContractServiceEdit.prototype;

function bind(overrides = {}) {
  const ctx = {
    _recordId: "a0C000000000001AAA",
    recordId: "a0C000000000001AAA",
    name: "サービスA",
    billingAccountId: "a0B000000000001AAA",
    accountId: "001000000000001AAA",
    relatedBillingAccounts: [{ id: "a0B000000000001AAA" }],
    allowOtherAccountBilling: false,
    taxPercent: 10,
    customerMemo: "",
    originalTaxPercent: 10,
    customFields: {},
    fieldDefinitions: [],
    loading: false,
    saving: false,
    lastModifiedToken: "tok",
    _pendingOperationKey: "",
    surfaceError: "",
    canRetryLoad: false,
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

describe("contractServiceEdit uncovered (Core 3.4.1 / 4.3.12 / 4.6)", () => {
  beforeEach(() => {
    getContext.mockReset().mockResolvedValue({
      name: "サービスA",
      accountId: "001000000000001AAA",
      relatedBillingAccounts: [{ id: "a0B000000000001AAA" }],
      billingAccountId: "a0B000000000001AAA",
      taxPercent: 10,
      customerMemo: "memo",
      customFields: { X__c: "1" },
      lastModifiedToken: "tok-1"
    });
    getContractServiceFieldDefinitions.mockReset().mockResolvedValue([
      { apiName: "X__c", label: "追加" }
    ]);
    save.mockReset().mockResolvedValue({});
    issueContractServiceOperationKey.mockReset().mockResolvedValue("op-1");
    buildCustomFieldInputs.mockReset().mockReturnValue([
      { apiName: "X__c", key: "X__c" }
    ]);
    validateCustomFieldMaps.mockReset().mockReturnValue(null);
  });

  it("canEditService / custom fields getters (Core 3.4.1)", () => {
    const ctx = bind();
    expect(ctx.canEditService).toBe(true);
    expect(ctx.hasCustomFields).toBe(true);
    expect(buildCustomFieldInputs).toHaveBeenCalled();
  });

  it("billingAccountFilter restricts to own account when OFF (Core 3.4.1 / 4.3.3)", () => {
    expect(bind().billingAccountFilter).toEqual({
      criteria: [
        {
          fieldPath: "Account__c",
          operator: "eq",
          value: "001000000000001AAA"
        }
      ]
    });
    expect(
      bind({ allowOtherAccountBilling: true }).billingAccountFilter
    ).toBeUndefined();
    expect(bind({ accountId: "" }).billingAccountFilter).toBeUndefined();
  });

  it("empty serviceId keeps loading without Apex (Core 3.4.1)", () => {
    const ctx = bind({ _recordId: "", recordId: "" });
    ctx.loadContext();
    expect(getContext).not.toHaveBeenCalled();
    expect(ctx.loading).toBe(true);
  });

  it("loadContext fills DTO and flags outside billing (Core 3.4.1)", async () => {
    getContext.mockResolvedValue({
      name: "新",
      accountId: "001A",
      relatedBillingAccounts: [{ id: "a0B1" }],
      billingAccountId: "a0BOUT",
      taxPercent: 8,
      customerMemo: "c",
      customFields: {},
      lastModifiedToken: "t2"
    });
    const ctx = bind({ relatedBillingAccounts: [] });
    ctx.loadContext();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(ctx.name).toBe("新");
    expect(ctx.allowOtherAccountBilling).toBe(true);
    expect(ctx.lastModifiedToken).toBe("t2");
    expect(ctx.loading).toBe(false);
    expect(ctx.surfaceError).toBe("");
  });

  it("loadContext error sets retryable surface (Core 3.4.1)", async () => {
    getContext.mockRejectedValue({ body: { message: "照会失敗" } });
    const ctx = bind();
    ctx.loadContext();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(ctx.surfaceError).toBe("照会失敗");
    expect(ctx.canRetryLoad).toBe(true);
    expect(ctx.loading).toBe(false);
  });

  it("isBillingOutsideRelated", () => {
    const ctx = bind({
      relatedBillingAccounts: [{ id: "a0B1" }]
    });
    expect(ctx.isBillingOutsideRelated("")).toBe(false);
    expect(ctx.isBillingOutsideRelated("a0B1")).toBe(false);
    expect(ctx.isBillingOutsideRelated("a0B2")).toBe(true);
  });

  it("field handlers ignore while saving", () => {
    const ctx = bind({ saving: true, name: "旧" });
    ctx.handleNameChange({ target: { value: "新" } });
    expect(ctx.name).toBe("旧");
    ctx.handleBillingAccountChange({ detail: { recordId: "x" } });
    expect(ctx.billingAccountId).toBe("a0B000000000001AAA");
    ctx.handleTaxChange({ target: { value: "8" } });
    expect(ctx.taxPercent).toBe(10);
    ctx.handleMemoChange({ target: { value: "m" } });
    expect(ctx.customerMemo).toBe("");
    ctx.handleCustomFieldChange({ detail: { fieldApi: "X__c", value: "2" } });
    expect(ctx.customFields).toEqual({});
    ctx.handleAllowOtherAccountBillingChange({ target: { checked: true } });
    expect(ctx.allowOtherAccountBilling).toBe(false);
    ctx.handleCancel();
    expect(ctx.dispatchEvent).not.toHaveBeenCalled();
  });

  it("handlers update when not saving; OFF clears outside billing (Core 3.4.1)", () => {
    const ctx = bind({
      billingAccountId: "a0BOUT",
      relatedBillingAccounts: [{ id: "a0B1" }],
      allowOtherAccountBilling: true
    });
    ctx.handleNameChange({ target: { value: "改名" } });
    expect(ctx.name).toBe("改名");
    ctx.handleBillingAccountChange({ detail: { recordId: "a0B1" } });
    expect(ctx.billingAccountId).toBe("a0B1");
    ctx.handleBillingAccountChange({});
    expect(ctx.billingAccountId).toBe("");
    ctx.billingAccountId = "a0BOUT";
    ctx.handleAllowOtherAccountBillingChange({ target: { checked: false } });
    expect(ctx.allowOtherAccountBilling).toBe(false);
    expect(ctx.billingAccountId).toBe("");
    ctx.handleTaxChange({ target: { value: "" } });
    expect(ctx.taxPercent).toBe(null);
    ctx.handleTaxChange({ target: { value: "8" } });
    expect(ctx.taxPercent).toBe(8);
    ctx.handleMemoChange({ target: { value: "備考" } });
    expect(ctx.customerMemo).toBe("備考");
    ctx.handleCustomFieldChange({ detail: {} });
    ctx.handleCustomFieldChange({ detail: { fieldApi: "X__c", value: "v" } });
    expect(ctx.customFields.X__c).toBe("v");
  });

  it("cancel closes action (Core 3.4.1)", () => {
    const ctx = bind();
    ctx.handleCancel();
    expect(ctx.dispatchEvent).toHaveBeenCalledWith(
      expect.any(CloseActionScreenEvent)
    );
  });

  it("taxChanged detects null and numeric diffs (Core 4.6)", () => {
    expect(bind({ originalTaxPercent: null, taxPercent: 10 }).taxChanged()).toBe(
      true
    );
    expect(bind({ originalTaxPercent: null, taxPercent: null }).taxChanged()).toBe(
      false
    );
    expect(bind({ originalTaxPercent: 10, taxPercent: null }).taxChanged()).toBe(
      true
    );
    expect(bind({ originalTaxPercent: 10, taxPercent: 10 }).taxChanged()).toBe(
      false
    );
  });

  it("validateDisplayTaxPercent edges (Core 4.6 / 1.1.10)", () => {
    const ctx = bind();
    expect(ctx.validateDisplayTaxPercent(null)).toBe(null);
    expect(ctx.validateDisplayTaxPercent("x")).toBe("消費税率が不正です。");
    expect(ctx.validateDisplayTaxPercent(-1)).toBe(
      "消費税率が不正です（負の値は指定できません）。"
    );
    expect(ctx.validateDisplayTaxPercent(0.5)).toBe(
      "消費税率は0〜100のパーセント値で入力してください。"
    );
    expect(ctx.validateDisplayTaxPercent(101)).toBe(
      "消費税率が不正です（100を超える値は指定できません）。"
    );
    expect(ctx.validateDisplayTaxPercent(10)).toBe(null);
    expect(ctx.validateDisplayTaxPercent(0)).toBe(null);
  });

  it("handleSave gates empty name / billing / tax (Core 3.4.1)", async () => {
    const noName = bind({ name: "  " });
    await noName.handleSave();
    expect(noName.surfaceError).toBe("名前を入力してください。");
    const noBill = bind({ billingAccountId: "" });
    await noBill.handleSave();
    expect(noBill.surfaceError).toBe("請求アカウントを入力してください。");
    const noTax = bind({ taxPercent: null });
    await noTax.handleSave();
    expect(noTax.surfaceError).toBe("税率を入力してください。");
    expect(save).not.toHaveBeenCalled();
  });

  it("handleSave success issues key and closes (Core 4.3.12)", async () => {
    save.mockResolvedValue({ businessOperationKey: "echo" });
    const ctx = bind({ _pendingOperationKey: "" });
    await ctx.handleSave();
    expect(issueContractServiceOperationKey).toHaveBeenCalled();
    expect(save).toHaveBeenCalledWith(
      expect.objectContaining({
        recordId: "a0C000000000001AAA",
        businessOperationKey: "op-1"
      })
    );
    expect(ctx._pendingOperationKey).toBe("");
    expect(ctx.dispatchEvent).toHaveBeenCalledWith(
      expect.any(CloseActionScreenEvent)
    );
    expect(ctx.saving).toBe(false);
  });

  it("reuses pending key; version conflict reloads (Core 4.3.12)", async () => {
    const reuse = bind({ _pendingOperationKey: "keep" });
    await reuse.handleSave();
    expect(issueContractServiceOperationKey).not.toHaveBeenCalled();
    expect(save).toHaveBeenCalledWith(
      expect.objectContaining({ businessOperationKey: "keep" })
    );

    save.mockRejectedValue({ body: { message: VERSION_CONFLICT_MESSAGE } });
    const conflict = bind({ _pendingOperationKey: "old" });
    const loadSpy = jest.spyOn(conflict, "loadContext").mockImplementation(() => {});
    await conflict.handleSave();
    expect(conflict.surfaceError).toBe(VERSION_CONFLICT_MESSAGE);
    expect(conflict._pendingOperationKey).toBe("");
    expect(loadSpy).toHaveBeenCalled();
  });

  it("handleReloadContext clears error and reloads", () => {
    const ctx = bind({ surfaceError: "e", canRetryLoad: true });
    const spy = jest.spyOn(ctx, "loadContext").mockImplementation(() => {});
    ctx.handleReloadContext();
    expect(ctx.surfaceError).toBe("");
    expect(ctx.canRetryLoad).toBe(false);
    expect(spy).toHaveBeenCalled();
  });

  it("messageOf fallbacks", () => {
    const ctx = bind();
    expect(ctx.messageOf({ body: { message: "b" } })).toBe("b");
    expect(ctx.messageOf({ message: "m" })).toBe("m");
    expect(ctx.messageOf({})).toBe("処理に失敗しました。");
  });

  it("saving handleSave is a no-op", async () => {
    await bind({ saving: true }).handleSave();
    expect(save).not.toHaveBeenCalled();
  });
});
