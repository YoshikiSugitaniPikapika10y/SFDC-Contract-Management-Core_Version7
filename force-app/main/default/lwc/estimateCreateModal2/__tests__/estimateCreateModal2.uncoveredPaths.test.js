import { createElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import { getFieldValue, getRecordNotifyChange } from "lightning/uiRecordApi";
import EstimateCreateModal2 from "c/estimateCreateModal2";
import { buildCreateHistoryName, buildCreateServiceName } from "c/estimateWizardState";

jest.mock("@salesforce/apex", () => ({ refreshApex: jest.fn() }), {
  virtual: true
});
jest.mock(
  "@salesforce/apex/EstimateCreateController.getBillingAccountsByAccount",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EstimateCreateController.getActiveContractServicesByAccount",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
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
  "lightning/uiObjectInfoApi",
  () => ({ getObjectInfo: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/navigation",
  () => {
    const Navigate = Symbol.for("NavigationMixin.Navigate");
    return {
      NavigationMixin: Object.assign(
        (Base) =>
          class extends Base {
            [Navigate]() {}
          },
        { Navigate }
      )
    };
  },
  { virtual: true }
);

const proto = EstimateCreateModal2.prototype;

function bind(overrides = {}) {
  const ctx = {
    selectedType: "New",
    orderedCustomFieldsOnly: false,
    editMode: false,
    loadingContractHistory: false,
    loadingOpportunityAccount: false,
    loadingContractServices: false,
    opportunityAccountId: "001000000000001AAA",
    opportunityName: "商談A",
    relatedBillingAccounts: [],
    activeContractServices: [],
    billingAccountsLoadError: "",
    contractServicesLoadError: "",
    allowOtherAccountBilling: false,
    linkedBillingAccountName: "",
    servicePickerOpen: false,
    recordId: "006000000000001AAA",
    _wizardData: {
      selectedType: "New",
      contractServiceName: "",
      contractHistoryName: "",
      contractServiceId: "",
      contractHistoryId: "",
      billingAccountId: "",
      taxPercent: 10,
      estimateSendContactId: ""
    },
    _billingAccountResolved: false,
    _billingAccountObjectInfo: null,
    _wiredActiveContractServices: { data: [] },
    _wiredRelatedBillingAccounts: { data: [] },
    _isConnected: true,
    dispatchEvent: jest.fn(),
    ...overrides
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
  return ctx;
}

describe("estimateCreateModal2 uncovered paths (Core 0.1 / 3.2 / 4.3 / 4.3.3)", () => {
  beforeEach(() => {
    refreshApex.mockReset().mockResolvedValue(undefined);
    getFieldValue.mockReset();
    getRecordNotifyChange.mockReset();
  });

  it("shows 対象がありません。 when related billing candidates are empty (Core 3.2)", () => {
    const ctx = bind({
      relatedBillingAccounts: [],
      opportunityAccountId: "001000000000001AAA"
    });
    expect(ctx.relatedBillingEmptyMessage).toBe(
      "対象がありません。他の取引先から選ぶ場合は下のチェックをオンにしてください。"
    );
    expect(ctx.showRelatedBillingEmptyMessage).toBe(true);
  });

  it("blocks billing pick without opportunity account (Core 3.2 / 1.1.10)", () => {
    const ctx = bind({ opportunityAccountId: "" });
    expect(ctx.relatedBillingEmptyMessage).toBe(
      "商談に取引先がないため、請求アカウントを選べません。"
    );
    expect(ctx.activeContractServiceEmptyMessage).toBe(
      "商談に取引先がないため、契約サービスを選べません。"
    );
    expect(ctx.isBillingAccountComboboxDisabled).toBe(true);
    expect(ctx.isSendContactPickerDisabled).toBe(true);
    expect(ctx.sendContactFilter.criteria[0].value).toBe("000000000000000AAA");
  });

  it("filters send contact by opportunity account (Core 4.3.3)", () => {
    const ctx = bind({ opportunityAccountId: "001AAA" });
    expect(ctx.sendContactFilter).toEqual({
      criteria: [
        { fieldPath: "AccountId", operator: "eq", value: "001AAA" }
      ]
    });
  });

  it("surfaces billing and service load errors without empty-candidate copy", () => {
    const billing = bind({
      billingAccountsLoadError: "請求アカウントの読み込みに失敗しました。"
    });
    expect(ctxEmpty(billing.relatedBillingEmptyMessage)).toBe("");
    expect(billing.showBillingAccountsLoadError).toBe(true);

    const services = bind({
      contractServicesLoadError: "契約サービスの読み込みに失敗しました。",
      loadingOpportunityAccount: false,
      loadingContractServices: false,
      loadingContractHistory: false
    });
    expect(services.activeContractServiceEmptyMessage).toBe("");
    expect(services.showContractServicesLoadError).toBe(true);
  });

  it("New uses create titles, Version 1, and editable identity (Core 0.1 / 4.3.3)", () => {
    const ctx = bind({ selectedType: "New" });
    expect(ctx.cardTitle).toBe("新規契約の作成");
    expect(ctx.cardClass).toBe("est-card");
    expect(ctx.displayNewHistoryVersion).toBe("1");
    expect(ctx.isServiceIdentityReadonly).toBe(false);
    expect(ctx.showOperationTypes).toBe(false);
    expect(ctx.showContinuationAfterService).toBe(false);
    expect(ctx.showEstimateSendContact).toBe(true);
  });

  it("continuation shows 既存契約の選択 and Term operations Change/Renew/Cancel", () => {
    const termService = {
      id: "a00SVC",
      name: "継続サービス",
      version: 2,
      lifecycle: "Term",
      lifecycleLabel: "継続契約",
      termStart: "2026-04-01",
      termEnd: "2027-03-31",
      billingAccountName: "BA1",
      taxPercent: 10,
      currentProductNames: "商品A"
    };
    const ctx = bind({
      selectedType: "Change",
      _wizardData: {
        selectedType: "Change",
        contractServiceId: "a00SVC",
        billingAccountId: "a00BA"
      },
      activeContractServices: [termService]
    });
    expect(ctx.cardTitle).toBe("既存契約の選択");
    expect(ctx.isServiceIdentityReadonly).toBe(true);
    expect(ctx.operationTypeValues).toEqual(["Change", "Renew", "Cancel"]);
    expect(ctx.showOperationTypes).toBe(true);
    const labels = ctx.typeOptions.map((opt) => opt.label);
    expect(labels).toEqual(["追加変更", "更新", "解約"]);
    const changeHelp = ctx.typeOptions[0].helpLines
      .map((line) => line.segments.map((seg) => seg.text).join(""))
      .join(" / ");
    expect(changeHelp).toContain("2026/04/01～2027/03/31の期間内に課金変更を行います");
    expect(changeHelp).toContain("2027/04/01から契約延長も可能です");
    expect(ctx.typeOptions[1].helpLines[0].segments.map((s) => s.text).join("")).toBe(
      "2027/04/01から契約を延長します"
    );
    expect(ctx.typeOptions[2].helpLines[0].segments.map((s) => s.text).join("")).toBe(
      "2027/03/31の期間満了をもって解約します"
    );
  });

  it("Spot continuation offers Change only and 一回課金を追加します", () => {
    const spot = {
      id: "a00SPOT",
      name: "都度",
      version: 1,
      lifecycle: "Spot",
      lifecycleLabel: "都度契約",
      taxPercent: ""
    };
    const ctx = bind({
      selectedType: "Change",
      _wizardData: { selectedType: "Change", contractServiceId: "a00SPOT" },
      activeContractServices: [spot]
    });
    expect(ctx.operationTypeValues).toEqual(["Change"]);
    expect(ctx.opsGridClass).toBe("est-ops-grid est-ops-grid_single");
    expect(
      ctx.typeOptions[0].helpLines[0].segments.map((s) => s.text).join("")
    ).toBe("一回課金を追加します");
    expect(ctx.selectedServiceCard.taxLabel).toBe("税率: 未設定");
    expect(ctx.selectedServiceCard.currentProductsLabel).toBe("");
  });

  it("picker option shows VersionN and 税率: 未設定 (Core 0.1)", () => {
    const option = proto.buildServicePickerOption.call(
      {},
      {
        id: "svc1",
        name: "Service",
        version: 3,
        lifecycle: "Term",
        currentProductNames: "P1",
        billingAccountName: "請求先"
      },
      "svc1"
    );
    expect(option.versionLabel).toBe("Version3");
    expect(option.taxLabel).toBe("税率: 未設定");
    expect(option.billingLabel).toBe("請求: BA1".replace("BA1", "請求先"));
    expect(option.currentProductsLabel).toBe("現商品: P1");
  });

  it("applies default names only when blank (Core 4.3.3)", () => {
    const ctx = bind({
      selectedType: "New",
      opportunityName: "商談A",
      _wizardData: {
        selectedType: "New",
        contractServiceName: "",
        contractHistoryName: "",
        billingAccountId: ""
      }
    });
    ctx.maybeApplyDefaultNames();
    const detail = ctx.dispatchEvent.mock.calls[0][0].detail;
    expect(detail.contractServiceName).toBe(buildCreateServiceName("商談A"));
    expect(detail.contractHistoryName).toBe(buildCreateHistoryName("商談A"));
  });

  it("does not apply default names on Ordered custom-field edit", () => {
    const ctx = bind({
      orderedCustomFieldsOnly: true,
      opportunityName: "商談A",
      _wizardData: {
        selectedType: "Change",
        contractServiceName: "",
        contractHistoryName: ""
      }
    });
    ctx.maybeApplyDefaultNames();
    expect(ctx.dispatchEvent).not.toHaveBeenCalled();
  });

  it("auto-selects the only related billing account on New", () => {
    const ctx = bind({
      selectedType: "New",
      relatedBillingAccounts: [{ id: "a00ONLY", name: "唯一" }],
      _wizardData: { selectedType: "New", billingAccountId: "" }
    });
    ctx.maybeAutoSelectBillingAccount();
    expect(ctx.dispatchEvent.mock.calls[0][0].detail.billingAccountId).toBe(
      "a00ONLY"
    );
  });

  it("does not auto-select billing on continuation", () => {
    const ctx = bind({
      selectedType: "Change",
      relatedBillingAccounts: [{ id: "a00ONLY", name: "唯一" }]
    });
    ctx.maybeAutoSelectBillingAccount();
    expect(ctx.dispatchEvent).not.toHaveBeenCalled();
  });

  it("wires billing load failure to 請求アカウントの読み込みに失敗しました。", () => {
    const ctx = bind();
    ctx.wiredRelatedBillingAccounts({ error: { message: "x" } });
    expect(ctx.billingAccountsLoadError).toBe(
      "請求アカウントの読み込みに失敗しました。"
    );
    expect(ctx.relatedBillingAccounts).toEqual([]);
  });

  it("wires contract service load failure to 契約サービスの読み込みに失敗しました。", () => {
    const ctx = bind({ opportunityAccountId: "001AAA" });
    ctx.wiredActiveContractServices({ error: { message: "x" } });
    expect(ctx.contractServicesLoadError).toBe(
      "契約サービスの読み込みに失敗しました。"
    );
    expect(ctx.loadingContractServices).toBe(false);
  });

  it("maps active contract services and auto-selects the only candidate", () => {
    const ctx = bind({
      selectedType: "Change",
      _wizardData: { selectedType: "Change", contractServiceId: "" },
      opportunityAccountId: "001AAA"
    });
    ctx.wiredActiveContractServices({
      data: [
        {
          id: "a00ONE",
          name: "唯一サービス",
          lifecycle: "Term",
          lifecycleLabel: "継続契約",
          termStart: "2026-04-01",
          termEnd: "2027-03-31",
          billingAccountId: "a00BA",
          billingAccountName: "BA",
          taxPercent: 8,
          version: 1
        }
      ]
    });
    const select = ctx.dispatchEvent.mock.calls.find(
      (call) => call[0].type === "serviceselect"
    );
    expect(select[0].detail).toEqual({
      contractServiceId: "a00ONE",
      contractServiceName: "唯一サービス",
      serviceLifecycle: "Term"
    });
  });

  it("clears other-account billing when opportunity account is missing", () => {
    const ctx = bind({ allowOtherAccountBilling: true, opportunityAccountId: "001" });
    getFieldValue.mockReturnValue("");
    ctx.wiredOpportunity({ data: { fields: {} } });
    expect(ctx.allowOtherAccountBilling).toBe(false);
    expect(ctx.loadingOpportunityAccount).toBe(false);
  });

  it("emits empty tax as null on blank input (Core 4.3.4)", () => {
    const ctx = bind();
    ctx.handleTaxPercentChange({ target: { value: "" } });
    expect(ctx.dispatchEvent.mock.calls[0][0].detail.taxPercent).toBeNull();
  });

  it("locks service picker while history is loading", () => {
    const ctx = bind({
      selectedType: "Change",
      loadingContractHistory: true,
      opportunityAccountId: "001AAA"
    });
    expect(ctx.isContractServiceComboboxDisabled).toBe(true);
    ctx.handleServicePickerToggle();
    expect(ctx.servicePickerOpen).toBe(false);
  });

  it("does not change operation type while editing Ordered custom fields", () => {
    const ctx = bind({
      orderedCustomFieldsOnly: true,
      selectedType: "Change"
    });
    ctx.handleTypeSelect({ currentTarget: { dataset: { type: "Renew" } } });
    expect(ctx.dispatchEvent).not.toHaveBeenCalled();
  });

  it("emits typechange for Term Renew (Core 4.3)", () => {
    const ctx = bind({ selectedType: "Change", editMode: false });
    ctx.handleTypeSelect({ currentTarget: { dataset: { type: "Renew" } } });
    expect(ctx.dispatchEvent.mock.calls[0][0].type).toBe("typechange");
    expect(ctx.dispatchEvent.mock.calls[0][0].detail.selectedType).toBe("Renew");
  });

  it("shows billing display name from related accounts, else linked name", () => {
    const named = bind({
      relatedBillingAccounts: [{ id: "a00BA", name: "関連名" }],
      _wizardData: { billingAccountId: "a00BA" }
    });
    expect(named.billingAccountDisplayValue).toBe("関連名");
    const linked = bind({
      relatedBillingAccounts: [],
      linkedBillingAccountName: "紐付け名",
      _wizardData: { billingAccountId: "a00BA" }
    });
    expect(linked.billingAccountDisplayValue).toBe("紐付け名");
    const empty = bind({ _wizardData: { billingAccountId: "" } });
    expect(empty.billingAccountDisplayValue).toBe("—");
  });

  it("hides formal edit without 19 and billing id (Core 4.3.3)", () => {
    const ctx = bind({
      _billingAccountObjectInfo: { updateable: false },
      _wizardData: { billingAccountId: "a00BA" }
    });
    expect(ctx.showBillingAccountFormalEdit).toBe(false);
    expect(
      ctx.handleOpenBillingAccountFormalEdit.call({
        ...ctx,
        [NavigationMixin.Navigate]: jest.fn()
      })
    ).toBe(false);
  });

  it("retries clear load errors via refreshApex", () => {
    const ctx = bind({
      billingAccountsLoadError: "請求アカウントの読み込みに失敗しました。",
      contractServicesLoadError: "契約サービスの読み込みに失敗しました。"
    });
    ctx.handleBillingAccountsRetry();
    expect(ctx.billingAccountsLoadError).toBe("");
    ctx.handleContractServicesRetry();
    expect(ctx.contractServicesLoadError).toBe("");
    expect(refreshApex).toHaveBeenCalled();
  });

  it("refreshCandidateWires notifies LDS ids and sets continuation loading", () => {
    const ctx = bind({
      selectedType: "Change",
      opportunityAccountId: "001AAA",
      recordId: "006AAA",
      _wizardData: {
        selectedType: "Change",
        contractServiceId: "a00SVC",
        billingAccountId: "a00BA"
      }
    });
    return ctx.refreshCandidateWires().then(() => {
      expect(ctx.loadingContractServices).toBe(true);
      expect(getRecordNotifyChange).toHaveBeenCalled();
    });
  });

  it("clears other-account billing when the checked account is not related", () => {
    const ctx = bind({
      opportunityAccountId: "001AAA",
      allowOtherAccountBilling: true,
      relatedBillingAccounts: [{ id: "a00REL", name: "関連" }],
      _wizardData: { billingAccountId: "a00OTHER" }
    });
    ctx.handleAllowOtherAccountBillingChange({ target: { checked: false } });
    expect(ctx.allowOtherAccountBilling).toBe(false);
    expect(ctx.dispatchEvent.mock.calls[0][0].detail.billingAccountId).toBe("");
  });

  it("renders 新規契約の作成 on New (Core 4.3.3)", async () => {
    const el = createElement("c-estimate-create-modal2", {
      is: EstimateCreateModal2
    });
    el.selectedType = "New";
    el.recordId = "006000000000001AAA";
    el.wizardData = {
      selectedType: "New",
      taxPercent: 10,
      contractServiceName: "",
      contractHistoryName: ""
    };
    document.body.appendChild(el);
    await Promise.resolve();
    const title = el.shadowRoot.querySelector(".est-card-title");
    expect(title.textContent).toBe("新規契約の作成");
    document.body.removeChild(el);
  });

  it("renders 既存契約の選択 on Change (Core 4.3)", async () => {
    const el = createElement("c-estimate-create-modal2", {
      is: EstimateCreateModal2
    });
    el.selectedType = "Change";
    el.recordId = "006000000000001AAA";
    el.wizardData = {
      selectedType: "Change",
      contractServiceId: "a00SVC",
      taxPercent: 10
    };
    document.body.appendChild(el);
    await Promise.resolve();
    const title = el.shadowRoot.querySelector(".est-card-title");
    expect(title.textContent).toBe("既存契約の選択");
    document.body.removeChild(el);
  });

  it("emits name, billing, tax, send-contact, and service picker changes (Core 4.3.3)", () => {
    const ctx = bind({
      selectedType: "New",
      opportunityAccountId: "001AAA",
      loadingOpportunityAccount: false,
      loadingContractServices: false,
      loadingContractHistory: false,
      relatedBillingAccounts: [{ id: "a00REL", name: "関連" }],
      activeContractServices: [
        {
          id: "a00SVC",
          name: "サービス",
          lifecycle: "Term",
          billingAccountId: "a00BA",
          billingAccountName: "BA",
          taxPercent: 10
        }
      ],
      _wizardData: {
        selectedType: "New",
        billingAccountId: "a00REL",
        contractServiceName: "x",
        contractHistoryName: "y"
      }
    });
    ctx.handleServiceNameChange({ target: { value: "契約サービス名" } });
    expect(ctx.dispatchEvent.mock.calls[0][0].detail.contractServiceName).toBe(
      "契約サービス名"
    );
    ctx.handleHistoryNameChange({ target: { value: "契約履歴名" } });
    ctx.handleBillingAccountComboboxChange({ target: { value: "a00REL" } });
    ctx.handleBillingAccountChange({ detail: { recordId: "a00REL" } });
    ctx.handleEstimateSendContactChange({ detail: { recordId: "003AAA" } });
    ctx.handleTaxPercentChange({ target: { value: "10" } });
    ctx.handleReselectBillingAccount();
    expect(
      ctx.dispatchEvent.mock.calls.some(
        (call) => call[0].detail && call[0].detail.billingAccountId === ""
      )
    ).toBe(true);
    ctx.handleServicePickerToggle();
    expect(ctx.servicePickerOpen).toBe(true);
    ctx.handleServicePickerSelect({
      currentTarget: { dataset: { id: "a00SVC" } }
    });
    expect(
      ctx.dispatchEvent.mock.calls.some((call) => call[0].type === "serviceselect")
    ).toBe(true);
    ctx.wiredRelatedBillingAccounts({
      data: [{ id: "a00REL", name: "関連" }]
    });
    expect(ctx.relatedBillingAccounts).toEqual([
      { id: "a00REL", name: "関連" }
    ]);
    getFieldValue.mockReturnValue("紐付け請求");
    ctx.wiredBillingAccountName({ data: { fields: {} } });
    expect(ctx.linkedBillingAccountName).toBe("紐付け請求");
  });
});

function ctxEmpty(value) {
  return value;
}
