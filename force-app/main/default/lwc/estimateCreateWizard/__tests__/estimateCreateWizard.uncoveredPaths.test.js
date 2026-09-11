import { createElement } from "lwc";
import { refreshApex } from "@salesforce/apex";
import getLatestContractHistory from "@salesforce/apex/EstimateCreateController.getLatestContractHistory";
import getDocumentDefaults from "@salesforce/apex/EstimateCreateController.getDocumentDefaults";
import getEstimateCopyPreset from "@salesforce/apex/EstimateCreateController.getEstimateCopyPreset";
import getEstimateEditPreset from "@salesforce/apex/EstimateCreateController.getEstimateEditPreset";
import saveEstimate from "@salesforce/apex/EstimateCreateController.saveEstimate";
import issueEstimateOperationKey from "@salesforce/apex/EstimateCreateController.issueEstimateOperationKey";
import getOrderHistoryFieldDefinitions from "@salesforce/apex/OrderWizardFieldService.getDefinitions";
import EstimateCreateWizard from "c/estimateCreateWizard";
import {
  createInitialWizardState,
  reduceWizardState,
  WIZARD_ACTIONS
} from "c/estimateWizardState";
import {
  BILLING_TYPE_ONE_TIME,
  BILLING_TYPE_RECURRING,
  INVOICE_SETTING_PREPAID_START,
  REVENUE_BASIS_OVER_TIME
} from "c/estimateLineItemUtils";

jest.mock("@salesforce/apex", () => ({ refreshApex: jest.fn() }), {
  virtual: true
});
jest.mock(
  "lightning/uiRecordApi",
  () => ({
    getRecord: jest.fn(),
    getFieldValue: jest.fn(),
    getRecordNotifyChange: jest.fn()
  }),
  { virtual: true }
);
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
  "lightning/navigation",
  () => ({
    NavigationMixin: (Base) => class extends Base {},
    CurrentPageReference: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.saveEstimate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.issueEstimateOperationKey",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getDocumentDefaults",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getEstimateCopyPreset",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getEstimateEditPreset",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getLatestContractHistory",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractWizardFieldService.getContractServiceFieldDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractWizardFieldService.getContractHistoryFieldDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractWizardFieldService.getContractProductFieldDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ContractWizardFieldService.getOpportunityDefaultContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OrderWizardFieldService.getDefinitions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const proto = EstimateCreateWizard.prototype;

function bind(overrides = {}) {
  let wizardState = createInitialWizardState();
  if (overrides.wizardState) {
    wizardState = overrides.wizardState;
  }
  const ctx = {
    recordId: "006000000000001AAA",
    opportunityRecordId: "006000000000001AAA",
    modalMode: false,
    isTabView: true,
    copyFromHistoryId: "",
    editHistoryId: "",
    _confirmState: null,
    _saveInFlight: false,
    _saveSucceededThisSession: false,
    _pendingOperationKey: "",
    _contentSessionSeq: 0,
    _wiredServiceFieldDefinitions: null,
    _wiredHistoryFieldDefinitions: null,
    _wiredProductFieldDefinitions: null,
    _wiredOpportunityDefaultContext: null,
    wizardFieldConfigError: "",
    documentDefaultsError: "",
    validationAlert: null,
    serviceFieldDefinitions: [],
    historyFieldDefinitions: [],
    orderHistoryFieldDefinitions: [],
    productFieldDefinitions: [],
    opportunityDefaultContext: {},
    opportunityIdForContext: "006000000000001AAA",
    contractPanelSessionItems: ["p-0"],
    wizardState,
    template: { querySelector: jest.fn(() => null) },
    dispatchEvent: jest.fn(),
    ...overrides,
    wizardState
  };
  Object.getOwnPropertyNames(proto).forEach((name) => {
    if (name === "constructor" || Object.prototype.hasOwnProperty.call(ctx, name)) {
      return;
    }
    const desc = Object.getOwnPropertyDescriptor(proto, name);
    if (desc.get) {
      Object.defineProperty(ctx, name, {
        get: desc.get,
        set: desc.set,
        configurable: true
      });
    } else if (typeof desc.value === "function") {
      ctx[name] = desc.value;
    }
  });
  ctx.dispatch = function dispatch(action) {
    this.wizardState = reduceWizardState(this.wizardState, action);
  };
  return ctx;
}

function withData(ctx, fields) {
  ctx.dispatch({ type: WIZARD_ACTIONS.MERGE_STEP2, fields });
  return ctx;
}

function alertText(ctx) {
  return (ctx.validationAlert.messages || []).map((row) => row.text).join("");
}

const oneTimeNew = {
  productId: "01tAAA",
  quantity: 1,
  unitPrice: 1000,
  billingType: BILLING_TYPE_ONE_TIME,
  invoiceType: INVOICE_SETTING_PREPAID_START,
  revenueRecognitionBasis: REVENUE_BASIS_OVER_TIME,
  startDate: "2026-04-01",
  endDate: "2026-04-30",
  recordType: "New",
  typeLabel: "New",
  amount: 1000
};

describe("estimateCreateWizard uncovered paths (Core 0.1 / 4.3 / 4.3.3 / 4.3.4 / 4.6)", () => {
  beforeEach(() => {
    refreshApex.mockReset().mockResolvedValue(undefined);
  });

  it("shows 見積作成 vs 見積編集 and type labels (Core 0.1)", () => {
    const create = bind();
    withData(create, { selectedType: "New", entryMode: "new" });
    expect(create.headerTitle).toBe("見積作成");
    expect(create.typeLabel).toBe("新規");
    expect(create.step3SyncBannerMessage).toBe("読み込み中");
    expect(create.stepItems.map((s) => s.label)).toEqual(["基本情報", "詳細情報"]);

    const edit = bind({ editHistoryId: "a01EDIT" });
    withData(edit, { selectedType: "Change" });
    expect(edit.headerTitle).toBe("見積編集");
    expect(edit.typeLabel).toBe("追加変更");
    expect(edit.showContractIdentifyPanel).toBe(true);
  });

  it("validateTaxPercent rejects empty, negative, over 100, and fraction percent (Core 4.3.4 / 4.6)", () => {
    const ctx = bind();
    expect(ctx.validateTaxPercent("")).toBe(
      "消費税率を入力してください。空欄は0%になりません。"
    );
    expect(ctx.validateTaxPercent(-1)).toBe(
      "消費税率が不正です（負の値は指定できません）。"
    );
    expect(ctx.validateTaxPercent(0.5)).toBe(
      "消費税率は0〜100のパーセント値で入力してください。"
    );
    expect(ctx.validateTaxPercent(101)).toBe(
      "消費税率が不正です（100を超える値は指定できません）。"
    );
    expect(ctx.validateTaxPercent("x")).toBe("消費税率が不正です。");
    expect(ctx.validateTaxPercent(10)).toBeNull();
  });

  it("validateStep1 New rejects missing identity and billing (Core 4.3.3 / 3.2)", () => {
    const ctx = bind();
    expect(ctx.validateStep1()).toBe("操作を選択してください。");
    withData(ctx, {
      selectedType: "New",
      accountName: "取引先",
      contractServiceName: "",
      contractHistoryName: "履歴",
      billingAccountId: "a00BA",
      taxPercent: 10
    });
    expect(ctx.validateStep1()).toBe("契約サービス名を入力してください。");
    withData(ctx, {
      contractServiceName: "サービス",
      contractHistoryName: "",
      billingAccountId: "a00BA",
      taxPercent: 10,
      accountName: "取引先"
    });
    expect(ctx.validateStep1()).toBe("契約履歴名を入力してください。");
    withData(ctx, {
      contractServiceName: "サービス",
      contractHistoryName: "履歴",
      billingAccountId: "",
      taxPercent: 10,
      accountName: "取引先"
    });
    expect(ctx.validateStep1()).toBe("請求アカウントを選択してください。");
  });

  it("validateStep1 continuation rejects missing service, history, lifecycle (Core 4.3)", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "Change",
      contractServiceId: "",
      taxPercent: 10,
      billingAccountId: "a00BA"
    });
    expect(ctx.validateStep1()).toBe("契約サービスを選択してください。");
    withData(ctx, {
      contractServiceId: "a00SVC",
      contractServiceName: "サービス",
      contractHistoryId: "",
      billingAccountId: "a00BA",
      taxPercent: 10
    });
    expect(ctx.validateStep1()).toBe(
      "選択した契約サービスに、受注済み（新規／追加変更／更新）の契約履歴がありません。"
    );
    withData(ctx, {
      contractServiceId: "a00SVC",
      contractServiceName: "サービス",
      contractHistoryId: "a01HIS",
      contractHistoryName: "履歴",
      serviceLifecycle: "",
      billingAccountId: "a00BA",
      taxPercent: 10
    });
    expect(ctx.validateStep1()).toBe(
      "ライフサイクルが未設定です。先にバックフィルしてください。"
    );
  });

  it("Spot cannot Renew or Cancel (Core 4.3 / 5.1)", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "Renew",
      contractServiceId: "a00SVC",
      contractServiceName: "サービス",
      contractHistoryId: "a01HIS",
      contractHistoryName: "履歴",
      serviceLifecycle: "Spot",
      billingAccountId: "a00BA",
      taxPercent: 10,
      renewEligible: true
    });
    expect(ctx.validateStep1()).toBe(
      "都度契約では更新／解約は使えません。一回課金だけの追加変更を使ってください。"
    );
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.maybeShowIneligibleOperationAlert();
    expect(alertText(ctx)).toBe(
      "都度契約では更新／解約は使えません。一回課金だけの追加変更を使ってください。"
    );
  });

  it("renewEligible false uses 新規で作成してください (Core 4.3)", () => {
    const ctx = bind();
    expect(ctx.renewEligibleFalseMessage("Change")).toBe(
      "前回の版の期間終了日と一致する継続課金商品がありません。追加変更できません。新規で作成してください。"
    );
    withData(ctx, {
      selectedType: "Change",
      contractServiceId: "a00SVC",
      contractServiceName: "サービス",
      contractHistoryId: "a01HIS",
      contractHistoryName: "履歴",
      serviceLifecycle: "Term",
      billingAccountId: "a00BA",
      taxPercent: 10,
      renewEligible: false
    });
    expect(ctx.validateStep1()).toBe(ctx.renewEligibleFalseMessage("Change"));
  });

  it("validateStep2 New recurring requires period start (Core 4.3.5)", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "New",
      taxPercent: 10,
      contractHistoryName: "履歴",
      contractStartDate: "",
      selectedProducts: [
        {
          ...oneTimeNew,
          billingType: BILLING_TYPE_RECURRING,
          startDate: "2026-04-01",
          endDate: "2027-03-31",
          amount: 12000
        }
      ]
    });
    expect(ctx.validateStep2()).toBe(
      "継続課金の期間開始日を入力してください。"
    );
  });

  it("validateStep2 New one-time only skips contract period", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "New",
      taxPercent: 10,
      contractHistoryName: "履歴",
      selectedProducts: [oneTimeNew]
    });
    expect(ctx.validateStep2()).toBeNull();
  });

  it("validateStep2 Cancel requires matching cancel dates", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "Cancel",
      taxPercent: 10,
      contractHistoryName: "履歴",
      renewEligible: true,
      contractStartDate: "2027-04-01",
      contractEndDate: "2027-04-02",
      contractEffectiveDate: "2027-04-01",
      previousTermEndDate: "2027-03-31",
      selectedProducts: []
    });
    expect(ctx.validateStep2()).toBe(
      "解約日の開始日と終了日が一致しません。"
    );
    withData(ctx, {
      selectedType: "Cancel",
      taxPercent: 10,
      contractHistoryName: "履歴",
      renewEligible: true,
      contractStartDate: "",
      contractEndDate: "",
      contractEffectiveDate: "2027-04-01",
      previousTermEndDate: "2027-03-31",
      selectedProducts: []
    });
    expect(ctx.validateStep2()).toBe(
      "継続課金の期間開始日を入力してください。"
    );
  });

  it("handleNext without opportunity id is 商談IDが指定されていません。", () => {
    const ctx = bind({
      recordId: "",
      opportunityRecordId: "",
      copyFromHistoryId: "",
      editHistoryId: ""
    });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleNext();
    expect(alertText(ctx)).toBe("商談IDが指定されていません。");
  });

  it("handleNext while confirm is open asks to answer first", () => {
    const ctx = bind({ _confirmState: { kind: "close" } });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = () => {};
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleNext();
    expect(alertText(ctx)).toBe(
      "確認ダイアログに回答してから進んでください。"
    );
  });

  it("handleSaveClick without opportunity id is 商談IDが指定されていません。", () => {
    const ctx = bind({
      recordId: "",
      opportunityRecordId: "",
      copyFromHistoryId: "",
      editHistoryId: ""
    });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleSaveClick();
    expect(alertText(ctx)).toBe("商談IDが指定されていません。");
  });

  it("handleSaveClick while confirm is open asks to answer before save", () => {
    const ctx = bind({ _confirmState: { kind: "remarks", requestId: "r1" } });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = () => {};
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleSaveClick();
    expect(alertText(ctx)).toBe(
      "確認ダイアログに回答してから保存してください。"
    );
  });

  it("handleSaveClick while Step3 loading asks to wait", () => {
    const ctx = bind();
    ctx.dispatch({ type: WIZARD_ACTIONS.SET_STEP3_LOADING, loading: true });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleSaveClick();
    expect(alertText(ctx)).toBe(
      "商品明細を更新中です。完了してから保存してください。"
    );
  });

  it("flush block message prefers amount modal, else 商品明細を更新中", () => {
    const ctx = bind();
    ctx.template.querySelector = () => ({ hasOpenAmountModal: true });
    expect(ctx.getStep3FlushBlockMessage("保存")).toContain(
      "金額の入力を適用（またはキャンセル）してから保存してください"
    );
    ctx.template.querySelector = () => null;
    expect(ctx.getStep3FlushBlockMessage("保存")).toBe(
      "商品明細を更新中です。完了してから保存してください。"
    );
  });

  it("handleClose without save confirms discard", () => {
    const ctx = bind({ _saveSucceededThisSession: false });
    ctx.openConfirm = proto.openConfirm;
    ctx.showConfirmationAlert = proto.showConfirmationAlert;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleClose();
    expect(ctx._confirmState).toEqual({ kind: "close" });
    expect(alertText(ctx)).toBe(
      "入力内容は保存されていません。破棄してよろしいですか？"
    );
  });

  it("handleSave rejects types other than New/Change/Renew/Cancel", async () => {
    const ctx = bind();
    withData(ctx, { selectedType: "Add" });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    await ctx.handleSave();
    expect(alertText(ctx)).toBe(
      "新規、追加変更、更新、解約のみ保存できます。"
    );
  });

  it("resolveApexErrorMessage prefers body.message then fallback", () => {
    const ctx = bind();
    expect(ctx.resolveApexErrorMessage({ body: { message: "CMD T不正" } })).toBe(
      "CMD T不正"
    );
    expect(ctx.resolveApexErrorMessage({})).toBe(
      "見積ウィザードのカスタム項目設定が不正です。カスタムメタデータを確認してください。"
    );
  });

  it("Ordered custom-field edit hides mixed order fields unless Ordered", () => {
    const ctx = bind({ editHistoryId: "a01EDIT" });
    withData(ctx, { historyStatus: "Estimate", selectedType: "Change" });
    ctx.orderHistoryFieldDefinitions = [{ apiName: "OrderOnly__c" }];
    expect(ctx.displayedOrderFieldDefinitions).toEqual([]);
    withData(ctx, { historyStatus: "Ordered" });
    expect(ctx.displayedOrderFieldDefinitions).toEqual([
      { apiName: "OrderOnly__c" }
    ]);
  });

  it("setCurrentPageReference reads tab and copy/edit ids", () => {
    const ctx = bind({
      copyFromHistoryId: "",
      editHistoryId: "",
      opportunityRecordId: ""
    });
    ctx.setCurrentPageReference({
      type: "standard__navItemPage",
      attributes: { apiName: "Estimate_Create" },
      state: {
        c__recordId: "006TAB",
        c__copyFromHistoryId: "a01COPY"
      }
    });
    expect(ctx.opportunityRecordId).toBe("006TAB");
    expect(ctx.copyFromHistoryId).toBe("a01COPY");
    expect(ctx.isTabView).toBe(true);
  });

  it("resolveApplicationDateForSave reads ApplicationDate__c or null", () => {
    const ctx = bind();
    withData(ctx, { contractHistoryCustomFields: {} });
    expect(ctx.resolveApplicationDateForSave()).toBeNull();
    withData(ctx, {
      contractHistoryCustomFields: { ApplicationDate__c: "2026-04-01" }
    });
    expect(ctx.resolveApplicationDateForSave()).toBe("2026-04-01");
  });

  it("missing record error shows when no opportunity and not copy/edit", () => {
    const ctx = bind({
      recordId: "",
      opportunityRecordId: "",
      copyFromHistoryId: "",
      editHistoryId: ""
    });
    expect(ctx.showMissingRecordError).toBe(true);
    const loading = bind({
      recordId: "",
      opportunityRecordId: "",
      copyFromHistoryId: "a01COPY"
    });
    loading.wizardState = reduceWizardState(loading.wizardState, {
      type: WIZARD_ACTIONS.PRESET_LOAD_START,
      key: "a01COPY"
    });
    expect(loading.showMissingRecordError).toBe(false);
  });

  it("handleNext from valid New Step1 opens 詳細情報", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "New",
      accountName: "取引先",
      contractServiceName: "サービス",
      contractHistoryName: "履歴",
      billingAccountId: "a00BA",
      taxPercent: 10
    });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleNext();
    expect(ctx.currentStep).toBe(2);
    ctx.handlePrev();
    expect(ctx.currentStep).toBe(1);
  });

  it("handleStep2Change merges billing and tax (Core 4.3.3)", () => {
    const ctx = bind();
    ctx.handleStep2Change({
      detail: { billingAccountId: "a00BA", taxPercent: 8 }
    });
    expect(ctx.wizardData.billingAccountId).toBe("a00BA");
    expect(ctx.wizardData.taxPercent).toBe(8);
  });

  it("handleContractServiceSelect loads latest ordered history (Core 4.3)", async () => {
    getLatestContractHistory.mockResolvedValue({
      historyId: "a01HIS",
      historyName: "履歴1",
      version: 1,
      nextVersion: 2,
      renewEligible: true,
      serviceLifecycle: "Term"
    });
    const ctx = bind();
    withData(ctx, { selectedType: "Change" });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    await ctx.handleContractServiceSelect({
      detail: {
        contractServiceId: "a00SVC",
        contractServiceName: "継続",
        serviceLifecycle: "Term"
      }
    });
    expect(ctx.wizardData.contractServiceId).toBe("a00SVC");
    expect(ctx.wizardData.contractHistoryId).toBe("a01HIS");
  });

  it("handleContractServiceSelect failure is 契約履歴の取得に失敗しました。", async () => {
    getLatestContractHistory.mockRejectedValue(new Error("x"));
    const ctx = bind();
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    await ctx.handleContractServiceSelect({
      detail: {
        contractServiceId: "a00SVC",
        contractServiceName: "継続",
        serviceLifecycle: "Term"
      }
    });
    expect(alertText(ctx)).toBe("契約履歴の取得に失敗しました。");
  });

  it("wired field definition error uses Apex body message", () => {
    const ctx = bind();
    ctx.wiredServiceFieldDefinitions({
      error: { body: { message: "サービスCMD不正" } }
    });
    expect(ctx.wizardFieldConfigError).toBe("サービスCMD不正");
  });

  it("loadDocumentDefaults failure keeps wizard usable with retry copy", async () => {
    getDocumentDefaults.mockRejectedValue({ body: { message: "既定失敗" } });
    const ctx = bind({ _contentSessionSeq: 1, _documentDefaultsRequestSeq: 0 });
    ctx.loadDocumentDefaults();
    await Promise.resolve();
    await Promise.resolve();
    expect(ctx.wizardState.async.loadingDocumentDefaults).toBe(false);
  });

  it("handleConfirmRequest while another confirm is open asks to answer first", () => {
    const ctx = bind({ _confirmState: { kind: "close" } });
    ctx.resolveModal3Confirm = jest.fn();
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = () => {};
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleConfirmRequest({
      detail: { requestId: "r2", message: "備考確認" }
    });
    expect(alertText(ctx)).toBe("先に表示中の確認に回答してください。");
  });

  it("mounts 見積作成 with 読み込み中 then 基本情報 (Core 0.1)", async () => {
    getDocumentDefaults.mockResolvedValue({
      estimateSendMode: "PdfAndEmail",
      estimateValidMonths: 1
    });
    const el = createElement("c-estimate-create-wizard", {
      is: EstimateCreateWizard
    });
    el.recordId = "006000000000001AAA";
    el.modalMode = true;
    document.body.appendChild(el);
    await Promise.resolve();
    await Promise.resolve();
    const title = el.shadowRoot.querySelector(".est-header-title, h1, .est-title");
    const text = el.shadowRoot.textContent;
    expect(text).toMatch(/見積作成|読み込み中|基本情報/);
    document.body.removeChild(el);
  });
});

describe("estimateCreateWizard uncovered paths remaining (Core 0.2 / 4.3 / 4.3.7 / 4.10)", () => {
  beforeEach(() => {
    refreshApex.mockReset().mockResolvedValue(undefined);
    getDocumentDefaults.mockReset().mockResolvedValue({});
    getEstimateCopyPreset.mockReset();
    getEstimateEditPreset.mockReset();
    saveEstimate.mockReset();
    issueEstimateOperationKey.mockReset().mockResolvedValue("op-1");
    getOrderHistoryFieldDefinitions.mockReset().mockResolvedValue([]);
  });

  it("type labels cover 更新 and 解約 (Core 0.1)", () => {
    const renew = bind();
    withData(renew, { selectedType: "Renew" });
    expect(renew.typeLabel).toBe("更新");
    const cancel = bind();
    withData(cancel, { selectedType: "Cancel" });
    expect(cancel.typeLabel).toBe("解約");
  });

  it("pageClass locks input while copy preset loads", () => {
    const ctx = bind({ modalMode: true });
    ctx.wizardState = reduceWizardState(ctx.wizardState, {
      type: WIZARD_ACTIONS.PRESET_LOAD_START,
      key: "copy"
    });
    expect(ctx.pageClass).toContain("est-page_modal");
    expect(ctx.pageClass).toContain("est-page_preset-loading");
    expect(ctx.isStep3).toBe(false);
    expect(typeof ctx.canSaveEstimate).toBe("boolean");
  });

  it("validation alert variant and actions follow the alert payload", () => {
    const ctx = bind();
    ctx.validationAlert = {
      variant: "warning",
      showActions: true,
      messages: [{ key: "1", text: "x" }]
    };
    expect(ctx.validationAlertVariant).toBe("warning");
    expect(ctx.validationAlertShowActions).toBe(true);
    expect(ctx.isPrevDisabled).toBe(false);
    ctx._confirmState = { kind: "close" };
    expect(ctx.isPrevDisabled).toBe(true);
  });

  it("flushStep3ToParent is blocked when amount modal is open", () => {
    const ctx = bind();
    ctx.template.querySelector = () => ({
      flushToParent: () => false,
      hasOpenAmountModal: true
    });
    expect(ctx.flushStep3ToParent()).toBe(false);
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleSaveClick();
    expect(alertText(ctx)).toContain(
      "金額の入力を適用（またはキャンセル）してから保存してください"
    );
  });

  it("handleSaveClick while already saving does not open another save", () => {
    const ctx = bind({ _saveInFlight: true });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.handleSaveClick();
    expect(ctx.validationAlert).toBe(null);
  });

  it("handleSaveClick with missing history name on detail is 契約履歴名 (Core 4.3.3)", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "New",
      taxPercent: 10,
      contractHistoryName: "",
      selectedProducts: [oneTimeNew]
    });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleSaveClick();
    expect(alertText(ctx)).toBe("契約履歴名を入力してください。");
  });

  it("confirm proceed on close discards unsaved input (Core 0.2)", () => {
    const ctx = bind({
      modalMode: true,
      _confirmState: { kind: "close" }
    });
    ctx.clearValidationAlert = proto.clearValidationAlert;
    ctx.performClose = proto.performClose;
    ctx.handleConfirmationProceed();
    expect(ctx._confirmState).toBe(null);
    expect(ctx.dispatchEvent).toHaveBeenCalled();
  });

  it("confirm proceed and cancel resolve remarks to Step3", () => {
    const proceed = bind({
      _confirmState: { kind: "remarks", requestId: "r1" }
    });
    const modal = { resolveConfirmRequest: jest.fn() };
    proceed.template.querySelector = () => modal;
    proceed.clearValidationAlert = proto.clearValidationAlert;
    proceed.handleConfirmationProceed();
    expect(modal.resolveConfirmRequest).toHaveBeenCalledWith("r1", true);

    const cancel = bind({
      _confirmState: { kind: "remarks", requestId: "r2" }
    });
    cancel.template.querySelector = () => modal;
    cancel.clearValidationAlert = proto.clearValidationAlert;
    cancel.handleConfirmationCancel();
    expect(modal.resolveConfirmRequest).toHaveBeenCalledWith("r2", false);
  });

  it("openConfirm refuses a second confirm", () => {
    const ctx = bind({ _confirmState: { kind: "close" } });
    expect(ctx.openConfirm({ kind: "remarks", requestId: "x" }, "m")).toBe(
      false
    );
  });

  it("Spot Renew is 都度契約では更新／解約は使えません (Core 4.3)", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "Renew",
      serviceLifecycle: "Spot",
      contractServiceId: "a00SVC",
      contractServiceName: "都度",
      contractHistoryId: "a01HIS",
      contractHistoryName: "履歴",
      billingAccountId: "a00BA",
      taxPercent: 10
    });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.maybeShowIneligibleOperationAlert();
    expect(alertText(ctx)).toBe(
      "都度契約では更新／解約は使えません。一回課金だけの追加変更を使ってください。"
    );
    expect(ctx.validateStep1()).toBe(
      "都度契約では更新／解約は使えません。一回課金だけの追加変更を使ってください。"
    );
  });

  it("Change without matching term end cannot continue (Core 4.3)", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "Change",
      serviceLifecycle: "Term",
      renewEligible: false,
      contractServiceId: "a00SVC",
      contractServiceName: "継続",
      contractHistoryId: "a01HIS",
      contractHistoryName: "履歴",
      billingAccountId: "a00BA",
      taxPercent: 10
    });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.maybeShowIneligibleOperationAlert();
    expect(alertText(ctx)).toBe(
      "前回の版の期間終了日と一致する継続課金商品がありません。追加変更できません。新規で作成してください。"
    );
    expect(ctx.validateStep1()).toBe(
      "前回の版の期間終了日と一致する継続課金商品がありません。追加変更できません。新規で作成してください。"
    );
  });

  it("handleStep1TypeChange remounts the contract panel (Core 4.3.7)", () => {
    const ctx = bind();
    withData(ctx, { selectedType: "New", contractServiceId: "" });
    ctx._contentSessionSeq = 1;
    ctx.contractPanelSessionItems = ["p-1"];
    ctx.handleStep1TypeChange({ detail: { selectedType: "Change" } });
    expect(ctx.wizardData.selectedType).toBe("Change");
    expect(ctx.contractPanelSessionItems[0]).not.toBe("p-1");
  });

  it("handleStep1EntryChange remounts when not editing", () => {
    const ctx = bind();
    ctx._contentSessionSeq = 3;
    ctx.handleStep1EntryChange({ detail: { entryMode: "continuation" } });
    expect(ctx.wizardData.entryMode).toBe("continuation");
    expect(ctx.contractPanelSessionItems[0]).toBe("p-4");
  });

  it("copy preset failure is 見積コピーの読み込みに失敗しました (Core 4.3)", async () => {
    getEstimateCopyPreset.mockRejectedValue({});
    const ctx = bind({
      copyFromHistoryId: "a01COPY",
      _contentSessionSeq: 1
    });
    await ctx.loadPreset("a01COPY", false);
    expect(ctx.copyLoadError).toBe("見積コピーの読み込みに失敗しました。");
  });

  it("edit preset failure uses Apex body then 見積編集内容の読み込みに失敗しました", async () => {
    getEstimateEditPreset.mockRejectedValue({
      body: { message: "版が更新されています" }
    });
    const ctx = bind({
      editHistoryId: "a01EDIT",
      _contentSessionSeq: 1
    });
    await ctx.loadPreset("a01EDIT", true);
    expect(ctx.copyLoadError).toBe("版が更新されています");
  });

  it("copy preset success applies opportunity and Ordered order fields (Core 4.10 / 11.4.3)", async () => {
    getEstimateCopyPreset.mockResolvedValue({
      opportunityId: "006PRESET",
      historyStatus: "Estimate",
      selectedType: "New"
    });
    const ctx = bind({
      copyFromHistoryId: "a01COPY",
      _contentSessionSeq: 1,
      _documentDefaults: { estimateDate: "2026-04-01" }
    });
    ctx.syncOpportunityIdForContext = proto.syncOpportunityIdForContext;
    await ctx.loadPreset("a01COPY", false);
    expect(ctx.opportunityRecordId).toBe("006PRESET");
    getOrderHistoryFieldDefinitions.mockResolvedValue([
      { apiName: "OrderDate__c" }
    ]);
    await ctx.loadOrderHistoryFieldDefinitions({
      historyStatus: "Ordered",
      selectedType: "Change"
    });
    expect(ctx.orderHistoryFieldDefinitions).toEqual([
      { apiName: "OrderDate__c" }
    ]);
  });

  it("handlePresetRetry reloads the edit source", async () => {
    getEstimateEditPreset.mockRejectedValue(new Error("x"));
    const ctx = bind({
      editHistoryId: "a01EDIT",
      _contentSessionSeq: 2
    });
    ctx.handlePresetRetry();
    await Promise.resolve();
    await Promise.resolve();
    expect(getEstimateEditPreset).toHaveBeenCalled();
  });

  it("handleStep3Change merges products on 詳細情報", () => {
    const ctx = bind();
    ctx.setCurrentStep(2);
    ctx.handleStep3Change({
      detail: { selectedProducts: [oneTimeNew] }
    });
    expect(ctx.wizardData.selectedProducts).toEqual([oneTimeNew]);
  });

  it("handleStepClick back while amount modal is open asks to 戻る after apply", () => {
    const ctx = bind();
    ctx.setCurrentStep(2);
    ctx.template.querySelector = () => ({
      flushToParent: () => false,
      hasOpenAmountModal: true
    });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleStepClick({
      currentTarget: { dataset: { step: "1" } }
    });
    expect(alertText(ctx)).toContain("から戻るしてください");
    expect(ctx.currentStep).toBe(2);
  });

  it("handleStepClick forward without type is 操作を選択してください", () => {
    const ctx = bind();
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleStepClick({
      currentTarget: { dataset: { step: "2" } }
    });
    expect(alertText(ctx)).toBe("操作を選択してください。");
  });

  it("validateStep1 New without account is 商談に取引先が設定されていません (Core 3.2)", () => {
    const ctx = bind();
    withData(ctx, { selectedType: "New", accountName: "" });
    expect(ctx.validateStep1()).toBe(
      "商談に取引先が設定されていません。"
    );
  });

  it("validateStep1 Change without service name is 契約サービス名", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "Change",
      contractServiceId: "a00SVC",
      contractServiceName: "  ",
      contractHistoryId: "a01HIS"
    });
    expect(ctx.validateStep1()).toBe("契約サービス名を入力してください。");
  });

  it("validateStep1 Change without history name is 契約履歴名", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "Change",
      contractServiceId: "a00SVC",
      contractServiceName: "サービス",
      contractHistoryId: "a01HIS",
      contractHistoryName: "",
      serviceLifecycle: "Term",
      billingAccountId: "a00BA"
    });
    expect(ctx.validateStep1()).toBe("契約履歴名を入力してください。");
  });

  it("validateStep2 New recurring without start date is 継続課金の期間開始日", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "New",
      taxPercent: 10,
      contractHistoryName: "履歴",
      selectedProducts: [
        { ...oneTimeNew, billingType: BILLING_TYPE_RECURRING }
      ]
    });
    expect(ctx.validateStep2()).toBe(
      "継続課金の期間開始日を入力してください。"
    );
  });

  it("validateStep2 New without effective date is 継続課金の切替日", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "New",
      taxPercent: 10,
      contractHistoryName: "履歴",
      contractStartDate: "2026-04-01",
      selectedProducts: [
        { ...oneTimeNew, billingType: BILLING_TYPE_RECURRING }
      ]
    });
    expect(ctx.validateStep2()).toBe(
      "継続課金の切替日を入力してください。"
    );
  });

  it("validateStep2 Cancel without end date is 解約日が取得できません", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "Cancel",
      taxPercent: 10,
      contractHistoryName: "履歴",
      contractStartDate: "2026-04-01",
      contractEffectiveDate: "2026-04-01",
      renewEligible: true
    });
    expect(ctx.validateStep2()).toBe("解約日が取得できません。");
  });

  it("validateStep2 Cancel mismatched start/end is 解約日の開始日と終了日が一致しません", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "Cancel",
      taxPercent: 10,
      contractHistoryName: "履歴",
      contractStartDate: "2026-04-01",
      contractEndDate: "2026-04-30",
      contractEffectiveDate: "2026-04-01",
      renewEligible: true
    });
    expect(ctx.validateStep2()).toBe(
      "解約日の開始日と終了日が一致しません。"
    );
  });

  it("handleSave with field-config error shows that message", async () => {
    const ctx = bind({ wizardFieldConfigError: "カスタムメタデータが不正です。" });
    withData(ctx, { selectedType: "New" });
    ctx.scrollValidationAlertIntoView = () => {};
    await ctx.handleSave();
    expect(alertText(ctx)).toBe("カスタムメタデータが不正です。");
  });

  it("handleSave success in modal notifies estimatesaved (Core 4.3)", async () => {
    saveEstimate.mockResolvedValue({
      contractHistoryId: "a01NEW",
      lastModifiedToken: "tok",
      businessOperationKey: "op-1"
    });
    const ctx = bind({ modalMode: true });
    withData(ctx, { selectedType: "New", contractServiceName: "サービス" });
    ctx.scrollValidationAlertIntoView = () => {};
    await ctx.handleSave();
    expect(ctx._saveSucceededThisSession).toBe(true);
    expect(ctx.dispatchEvent).toHaveBeenCalled();
    const ev = ctx.dispatchEvent.mock.calls.find(
      (c) => c[0] && c[0].type === "estimatesaved"
    );
    expect(ev[0].detail.contractHistoryId).toBe("a01NEW");
  });

  it("handleSave Apex failure keeps the save error text", async () => {
    saveEstimate.mockRejectedValue({ body: { message: "版が更新されています" } });
    const ctx = bind();
    withData(ctx, { selectedType: "New" });
    ctx.scrollValidationAlertIntoView = () => {};
    await ctx.handleSave();
    expect(alertText(ctx)).toContain("版が更新されています");
  });

  it("handleClose after successful save closes without discard confirm", () => {
    const ctx = bind({
      modalMode: true,
      _saveSucceededThisSession: true
    });
    ctx.handleClose();
    expect(ctx._confirmState).toBe(null);
    expect(ctx.dispatchEvent).toHaveBeenCalled();
  });

  it("handleClose while saving is ignored", () => {
    const ctx = bind();
    ctx.dispatch({ type: WIZARD_ACTIONS.SAVE_START });
    ctx.handleClose();
    expect(ctx._confirmState).toBe(null);
  });

  it("initializeFromUrl reads tab record and copy id (Core 4.3)", () => {
    const href = window.location.href;
    const ctx = bind({
      copyFromHistoryId: "",
      editHistoryId: "",
      opportunityRecordId: ""
    });
    window.history.replaceState(
      {},
      "",
      "/lightning/n/Estimate_Create?c__recordId=006URL&c__copyFromHistoryId=a01COPY"
    );
    ctx.initializeFromUrl();
    expect(ctx.isTabView).toBe(true);
    expect(ctx.opportunityRecordId).toBe("006URL");
    expect(ctx.copyFromHistoryId).toBe("a01COPY");
    window.history.replaceState({}, "", href);
  });

  it("wired history/product/opportunity errors keep CMDT message", () => {
    const ctx = bind();
    ctx.wiredHistoryFieldDefinitions({
      error: { body: { message: "履歴CMD不正" } }
    });
    expect(ctx.wizardFieldConfigError).toBe("履歴CMD不正");
    ctx.wiredProductFieldDefinitions({
      error: { body: { message: "商品CMD不正" } }
    });
    expect(ctx.wizardFieldConfigError).toBe("商品CMD不正");
    ctx.wiredOpportunityDefaultContext({
      error: { body: { message: "商談コンテキスト不正" } }
    });
    expect(ctx.wizardFieldConfigError).toBe("商談コンテキスト不正");
  });

  it("handleFieldConfigRetry and document-defaults retry clear the banner", () => {
    const ctx = bind({
      wizardFieldConfigError: "x",
      documentDefaultsError: "y"
    });
    ctx.handleFieldConfigRetry();
    expect(ctx.wizardFieldConfigError).toBe("");
    ctx._wiredServiceFieldDefinitions = { data: [] };
    ctx.handleDocumentDefaultsRetry();
    expect(ctx.documentDefaultsError).toBe("");
    ctx.handleFieldConfigRetry();
    expect(refreshApex).toHaveBeenCalled();
  });

  it("handleOpportunityLoaded stores account and contact", () => {
    const ctx = bind();
    ctx.handleOpportunityLoaded({
      detail: {
        opportunityName: "商談A",
        accountName: "取引先A",
        opportunityContactId: "003AAA"
      }
    });
    expect(ctx.wizardData.accountName).toBe("取引先A");
    expect(ctx.wizardData.opportunityContactId).toBe("003AAA");
  });

  it("handleStep3Loading sets loading and Next stays blocked", () => {
    const ctx = bind();
    ctx.handleStep3Loading({ detail: { loading: true } });
    expect(ctx.loadingStep3).toBe(true);
    expect(ctx.isNextDisabled).toBe(true);
  });

  it("ensurePresetLoaded loads copy when copy id is set", async () => {
    getEstimateCopyPreset.mockResolvedValue({ selectedType: "New" });
    const ctx = bind({
      copyFromHistoryId: "a01COPY",
      editHistoryId: "",
      _contentSessionSeq: 1
    });
    ctx.ensurePresetLoaded();
    await Promise.resolve();
    await Promise.resolve();
    expect(getEstimateCopyPreset).toHaveBeenCalled();
  });

  it("New without start/end after dates filled is 継続課金の期間終了日", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "New",
      taxPercent: 10,
      contractHistoryName: "履歴",
      contractStartDate: "2026-04-01",
      contractEffectiveDate: "2026-04-01",
      contractEndDate: "",
      selectedProducts: [
        { ...oneTimeNew, billingType: BILLING_TYPE_RECURRING }
      ]
    });
    expect(ctx.validateStep2()).toBe(
      "継続課金の期間終了日を入力してください。"
    );
  });

  it("validateStep2 start after end is 期間開始日は期間終了日以前", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "New",
      taxPercent: 10,
      contractHistoryName: "履歴",
      contractStartDate: "2026-05-01",
      contractEndDate: "2026-04-30",
      contractEffectiveDate: "2026-05-01",
      selectedProducts: [
        { ...oneTimeNew, billingType: BILLING_TYPE_RECURRING }
      ]
    });
    expect(ctx.validateStep2()).toBe(
      "継続課金の期間開始日は継続課金の期間終了日以前の日付を入力してください。"
    );
  });

  it("validateStep2 New without products is 商品明細を1行以上入力してください (Core 4.3.5)", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "New",
      taxPercent: 10,
      contractHistoryName: "履歴",
      selectedProducts: []
    });
    expect(ctx.validateStep2()).toBe(
      "商品明細を1行以上入力してください。"
    );
  });

  it("handleNext while 契約履歴 loading asks to wait", () => {
    const ctx = bind();
    ctx.wizardState = {
      ...ctx.wizardState,
      async: { ...ctx.wizardState.async, loadingContractHistory: true }
    };
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleNext();
    expect(alertText(ctx)).toBe(
      "契約履歴を読み込み中です。完了してから次へ進んでください。"
    );
  });

  it("handleNext while document defaults loading asks to wait", () => {
    const ctx = bind();
    ctx.wizardState = {
      ...ctx.wizardState,
      async: { ...ctx.wizardState.async, loadingDocumentDefaults: true }
    };
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleNext();
    expect(alertText(ctx)).toBe(
      "見積書の初期値を読み込み中です。完了してから次へ進んでください。"
    );
  });

  it("handlePrev from 詳細情報 while amount modal is open asks to 戻る", () => {
    const ctx = bind();
    ctx.setCurrentStep(2);
    ctx.template.querySelector = () => ({
      flushToParent: () => false,
      hasOpenAmountModal: true
    });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handlePrev();
    expect(alertText(ctx)).toContain("から戻るしてください");
    expect(ctx.currentStep).toBe(2);
  });

  it("handleStepClick forward from valid New opens 詳細情報", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "New",
      accountName: "取引先",
      contractServiceName: "サービス",
      contractHistoryName: "履歴",
      billingAccountId: "a00BA",
      taxPercent: 10
    });
    ctx.showValidationAlert = proto.showValidationAlert;
    ctx.dismissOpenConfirm = proto.dismissOpenConfirm;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleStepClick({ currentTarget: { dataset: { step: "2" } } });
    expect(ctx.currentStep).toBe(2);
    expect(ctx.step3PanelClass).toContain("est-step-panel");
    expect(ctx.isStep3PanelAriaHidden).toBe(false);
  });

  it("validateStep2 Change without period start is 継続課金の期間開始日", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "Change",
      serviceLifecycle: "Term",
      taxPercent: 10,
      contractHistoryName: "履歴",
      renewEligible: true,
      selectedProducts: [
        { ...oneTimeNew, billingType: BILLING_TYPE_RECURRING }
      ]
    });
    expect(ctx.validateStep2()).toBe(
      "継続課金の期間開始日を入力してください。"
    );
  });

  it("validateStep2 Renew without period start is 継続課金の期間開始日", () => {
    const ctx = bind();
    withData(ctx, {
      selectedType: "Renew",
      taxPercent: 10,
      contractHistoryName: "履歴",
      renewEligible: true,
      selectedProducts: [
        { ...oneTimeNew, billingType: BILLING_TYPE_RECURRING }
      ]
    });
    expect(ctx.validateStep2()).toBe(
      "継続課金の期間開始日を入力してください。"
    );
  });

  it("Ordered edit validateStep2 only checks custom fields (Core 4.3.1)", () => {
    const ctx = bind({ editHistoryId: "a01EDIT" });
    withData(ctx, {
      selectedType: "Change",
      historyStatus: "Ordered",
      contractServiceCustomFields: {},
      contractHistoryCustomFields: {},
      selectedProducts: []
    });
    expect(ctx.isOrderedCustomFieldsOnlyEdit).toBe(true);
    expect(ctx.validateStep2()).toBeNull();
  });

  it("handleClose replaces remarks confirm with discard (Core 0.2)", () => {
    const ctx = bind({
      _confirmState: { kind: "remarks", requestId: "r9" }
    });
    ctx.template.querySelector = () => ({
      resolveConfirmRequest: jest.fn()
    });
    ctx.showConfirmationAlert = proto.showConfirmationAlert;
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleClose();
    expect(ctx._confirmState).toEqual({ kind: "close" });
    expect(alertText(ctx)).toBe(
      "入力内容は保存されていません。破棄してよろしいですか？"
    );
  });

  it("renderedCallback loads edit preset", async () => {
    getEstimateEditPreset.mockResolvedValue({
      selectedType: "Change",
      historyStatus: "Estimate"
    });
    const ctx = bind({
      editHistoryId: "a01EDIT",
      _contentSessionSeq: 1
    });
    ctx.renderedCallback();
    await Promise.resolve();
    await Promise.resolve();
    expect(getEstimateEditPreset).toHaveBeenCalled();
  });

  it("ensurePresetLoaded for edit uses 見積編集内容の読み込みに失敗しました on empty error", async () => {
    getEstimateEditPreset.mockRejectedValue({});
    const ctx = bind({
      editHistoryId: "a01EDIT",
      _contentSessionSeq: 1
    });
    await ctx.loadPreset("a01EDIT", true);
    expect(ctx.copyLoadError).toBe(
      "見積編集内容の読み込みに失敗しました。"
    );
  });

  it("stepItems lock forward until Step1 is valid", () => {
    const ctx = bind();
    const items = ctx.stepItems;
    expect(items[0].label).toBe("基本情報");
    expect(items[1].label).toBe("詳細情報");
    expect(items[1].itemClass).toContain("est-step_locked");
  });

  it("handleSaveClick proceeds to save when New one-time is valid", async () => {
    saveEstimate.mockResolvedValue({ contractHistoryId: "a01NEW" });
    const ctx = bind({ modalMode: true });
    withData(ctx, {
      selectedType: "New",
      taxPercent: 10,
      contractHistoryName: "履歴",
      selectedProducts: [oneTimeNew]
    });
    ctx.scrollValidationAlertIntoView = () => {};
    ctx.handleSaveClick();
    await Promise.resolve();
    await Promise.resolve();
    expect(saveEstimate).toHaveBeenCalled();
  });
});
