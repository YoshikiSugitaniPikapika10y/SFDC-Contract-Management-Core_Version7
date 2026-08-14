import { LightningElement, api, track, wire } from "lwc";
import {
  getRecord,
  getFieldValue,
  getRecordNotifyChange
} from "lightning/uiRecordApi";
import { refreshApex } from "@salesforce/apex";
import OPP_NAME_FIELD from "@salesforce/schema/Opportunity.Name";
import OPP_ACCOUNT_ID_FIELD from "@salesforce/schema/Opportunity.AccountId";
import CS_BILLING_ACCOUNT_FIELD from "@salesforce/schema/ContractService__c.BiilingAcccount__c";
import BA_NAME_FIELD from "@salesforce/schema/BillingAccount__c.Name";
import getBillingAccountsByAccount from "@salesforce/apex/EstimateCreateController.getBillingAccountsByAccount";
import getActiveContractServicesByAccount from "@salesforce/apex/EstimateCreateController.getActiveContractServicesByAccount";
import { formatHistoryVersion } from "c/estimateWizardState";
import { addDaysToIsoDate } from "c/estimateLineItemUtils";

const CS_BILLING_ACCOUNT_NAME_FIELD =
  "ContractService__c.BiilingAcccount__r.Name";

const TYPE_META = {
  Change: {
    label: "Change",
    iconName: "utility:edit"
  },
  Renew: {
    label: "Renew",
    iconName: "utility:refresh"
  },
  Cancel: {
    label: "Cancel",
    iconName: "utility:close"
  },
  Add: {
    label: "Add",
    iconName: "utility:add"
  }
};

/**
 * 基本情報内: 契約の特定（名前／選択／請求アカウント／契約履歴名）と操作選択。
 * 入口（新規/続き）は modal1。操作はサービス選択後にここ。
 */
export default class EstimateCreateModal2 extends LightningElement {
  @api recordId;
  @api editMode = false;
  @api orderedCustomFieldsOnly = false;
  @api selectedType = "";
  @api loadingContractHistory = false;

  _wizardData;
  _isConnected = false;
  /** 請求アカウントを自動選択済み、またはユーザーが明示的に選んだ。 */
  _billingAccountResolved = false;
  _wiredActiveContractServices;
  _wiredRelatedBillingAccounts;

  @track opportunityAccountId = "";
  @track relatedBillingAccounts = [];
  @track activeContractServices = [];
  @track billingAccountsLoadError = "";
  @track contractServicesLoadError = "";
  @track allowOtherAccountBilling = false;
  @track linkedBillingAccountName = "";
  /** 商談の取引先 ID 取得が完了するまで true。 */
  @track loadingOpportunityAccount = true;
  /** 契約サービス候補の wire 応答待ち。 */
  @track loadingContractServices = false;
  /** 契約サービスカスタムピッカーの開閉。 */
  @track servicePickerOpen = false;
  /** LDS で取得した商談名（デフォルト名用）。 */
  @track opportunityName = "";

  @api
  get wizardData() {
    return this._wizardData;
  }

  set wizardData(value) {
    this._wizardData = value;
    if (this._isConnected) {
      this.maybeApplyDefaultNames();
    }
  }

  billingAccountMatchingInfo = {
    primaryField: {
      fieldPath: "Name"
    }
  };

  connectedCallback() {
    this._isConnected = true;
    this.maybeApplyDefaultNames();
    // マウント直後は wire 結果が未設定のことがあるため、次ティックで必ず再取得する
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    Promise.resolve().then(() => {
      this.refreshCandidateWires();
    });
  }

  get resolvedOpportunityName() {
    return (
      (this.opportunityName || "").trim() ||
      (this._wizardData?.opportunityName || "").trim()
    );
  }

  /**
   * 契約サービス／請求先候補をサーバ最新で取り直す（wire キャッシュ破棄）。
   */
  @api
  refreshCandidateWires() {
    if (!this.isNewType && this.opportunityAccountId) {
      this.loadingContractServices = true;
    }
    const jobs = [];
    if (this._wiredActiveContractServices) {
      jobs.push(refreshApex(this._wiredActiveContractServices));
    }
    if (this._wiredRelatedBillingAccounts) {
      jobs.push(refreshApex(this._wiredRelatedBillingAccounts));
    }
    const notifyIds = [];
    if (this.recordId) {
      notifyIds.push({ recordId: this.recordId });
    }
    if (this.contractServiceId) {
      notifyIds.push({ recordId: this.contractServiceId });
    }
    if (this.billingAccountId) {
      notifyIds.push({ recordId: this.billingAccountId });
    }
    if (notifyIds.length > 0) {
      getRecordNotifyChange(notifyIds);
    }
    return Promise.all(jobs);
  }

  get contractServiceName() {
    return this._wizardData?.contractServiceName || "";
  }

  get contractHistoryName() {
    return this._wizardData?.contractHistoryName || "";
  }

  get contractServiceId() {
    return this._wizardData?.contractServiceId || "";
  }

  get contractHistoryId() {
    return this._wizardData?.contractHistoryId || "";
  }

  get autoHistoryName() {
    return this._wizardData?.autoHistoryName || "";
  }

  get baseHistoryVersion() {
    return this._wizardData?.baseHistoryVersion ?? null;
  }

  get billingAccountId() {
    return this._wizardData?.billingAccountId || "";
  }

  get effectiveWizardType() {
    return this.selectedType || this._wizardData?.selectedType || "";
  }

  get isNewType() {
    return this.effectiveWizardType === "New";
  }

  get cardTitle() {
    return this.isNewType ? "新規契約の作成" : "既存契約の選択";
  }

  get cardClass() {
    return this.isNewType ? "est-card" : "est-card est-card_continuation";
  }

  get showRelatedBillingCombobox() {
    return !this.allowOtherAccountBilling;
  }

  get showOtherBillingPicker() {
    return this.allowOtherAccountBilling;
  }

  get showBillingAccountReadonly() {
    return this.isStandardFieldsReadonly || Boolean(this.billingAccountId);
  }

  get billingAccountComboboxOptions() {
    const selectedId = this.billingAccountId || "";
    const options = [
      {
        key: "__none__",
        label: "— なし —",
        value: "",
        selected: selectedId === ""
      }
    ];
    for (const account of this.relatedBillingAccounts) {
      options.push({
        key: account.id,
        label: account.name || account.id,
        value: account.id,
        selected: account.id === selectedId
      });
    }
    return options;
  }

  get isBillingAccountComboboxDisabled() {
    return !this.opportunityAccountId || this.orderedCustomFieldsOnly === true;
  }

  get isStandardFieldsReadonly() {
    return this.orderedCustomFieldsOnly === true;
  }

  get billingAccountDisplayValue() {
    if (!this.billingAccountId) {
      return "—";
    }
    const matched = this.relatedBillingAccounts.find(
      (account) => account.id === this.billingAccountId
    );
    if (matched?.name) {
      return matched.name;
    }
    if (this.linkedBillingAccountName) {
      return this.linkedBillingAccountName;
    }
    return this.billingAccountId;
  }

  get isContractServiceComboboxDisabled() {
    return (
      !this.opportunityAccountId ||
      this.editMode === true ||
      this.orderedCustomFieldsOnly === true ||
      this.loadingContractHistory === true ||
      this.loadingOpportunityAccount === true ||
      this.loadingContractServices === true
    );
  }

  get relatedBillingEmptyMessage() {
    if (this.billingAccountsLoadError) {
      return "";
    }
    if (!this.opportunityAccountId) {
      return "商談に取引先がないため、請求アカウントを選べません。";
    }
    if (this.relatedBillingAccounts.length === 0) {
      return "この取引先に紐づく請求アカウントがありません。他の取引先から選ぶ場合は下のチェックをオンにしてください。";
    }
    return "";
  }

  get showRelatedBillingEmptyMessage() {
    return (
      this.showRelatedBillingCombobox &&
      Boolean(this.relatedBillingEmptyMessage)
    );
  }

  get showBillingAccountsLoadError() {
    return (
      this.showRelatedBillingCombobox && Boolean(this.billingAccountsLoadError)
    );
  }

  get selectedContractService() {
    if (!this.contractServiceId) {
      return null;
    }
    return (
      this.activeContractServices.find(
        (service) => service.id === this.contractServiceId
      ) || null
    );
  }

  get servicePickerExpandedAria() {
    return this.servicePickerOpen ? "true" : "false";
  }

  get servicePickerClass() {
    return this.servicePickerOpen
      ? "est-service-picker est-service-picker_open"
      : "est-service-picker";
  }

  get servicePickerTriggerClass() {
    return this.servicePickerOpen
      ? "est-service-picker-trigger est-service-picker-trigger_open"
      : "est-service-picker-trigger";
  }

  buildServicePickerOption(service, selectedId) {
    const selected = !!(service && service.id === selectedId);
    const versionLabel = formatHistoryVersion(service?.version);
    const start = formatHelpDate(service?.termStart);
    const end = formatHelpDate(service?.termEnd);
    const name = service?.name || service?.id || "";
    const lifecycleLabel = service?.lifecycleLabel || "";
    const currentProducts = (service?.currentProductNames || "").trim();
    const isSpot = (service?.lifecycle || "") === "Spot";
    return {
      key: service?.id || "__none__",
      id: service?.id || "",
      nameLabel: name,
      versionLabel: versionLabel ? `V${versionLabel}` : "",
      lifecycleLabel,
      termLabel: start && end ? `${start}～${end}` : start || end || "",
      currentProductsLabel:
        !isSpot && currentProducts ? `現商品: ${currentProducts}` : "",
      billingLabel: service?.billingAccountName
        ? `請求: ${service.billingAccountName}`
        : "",
      selectedAria: selected ? "true" : "false",
      itemClass: selected
        ? "est-service-picker-item est-service-picker-item_selected"
        : "est-service-picker-item"
    };
  }

  get servicePickerOptions() {
    const selectedId = this.contractServiceId || "";
    return (this.activeContractServices || []).map((service) =>
      this.buildServicePickerOption(service, selectedId)
    );
  }

  get selectedServiceCard() {
    const service = this.selectedContractService;
    if (!service) {
      return null;
    }
    return this.buildServicePickerOption(service, service.id);
  }

  get hasSelectedServiceCard() {
    return Boolean(this.selectedServiceCard);
  }

  get selectedServiceCardClass() {
    const base =
      "est-service-picker-item est-service-picker-item_selected est-service-picker-selected-card";
    if (this.servicePickerOpen) {
      return `${base} est-service-picker-selected-card_open`;
    }
    if (this.isContractServiceComboboxDisabled) {
      return `${base} est-service-picker-selected-card_locked`;
    }
    return base;
  }

  get serviceLifecycle() {
    return (
      this.selectedContractService?.lifecycle ||
      this._wizardData?.serviceLifecycle ||
      ""
    );
  }

  /** 続き: 契約サービス選択後（または編集時）に詳細・操作を出す */
  get showContinuationAfterService() {
    if (this.isNewType) {
      return false;
    }
    if (this.editMode === true || this.orderedCustomFieldsOnly === true) {
      return true;
    }
    return Boolean(this.contractServiceId);
  }

  get showOperationTypes() {
    if (this.isNewType) {
      return false;
    }
    if (this.editMode === true || this.orderedCustomFieldsOnly === true) {
      return Boolean(this.selectedType && this.selectedType !== "New");
    }
    return Boolean(this.contractServiceId && this.operationTypeValues.length);
  }

  get operationTypeValues() {
    const lifecycle = this.serviceLifecycle || "";
    if (!this.contractServiceId && this.editMode !== true) {
      return [];
    }
    if (!lifecycle) {
      return [];
    }
    if (lifecycle === "Spot") {
      return ["Add"];
    }
    if (lifecycle === "Term") {
      return ["Change", "Renew", "Cancel"];
    }
    return [];
  }

  get typeOptions() {
    const termStartIso = formatOptionDate(
      this.selectedContractService?.termStart
    );
    const termEndIso = formatOptionDate(this.selectedContractService?.termEnd);
    return this.operationTypeValues.map((value) => {
      const meta = TYPE_META[value] || {
        label: value,
        iconName: "utility:touch_action"
      };
      const selected = this.selectedType === value;
      return {
        value,
        label: meta.label,
        helpLines: buildOperationHelpLines(value, termStartIso, termEndIso),
        iconName: meta.iconName,
        pressed: selected ? "true" : "false",
        disabled:
          this.editMode === true || this.orderedCustomFieldsOnly === true,
        buttonClass: selected
          ? "est-ops-card est-ops-card_active"
          : this.editMode === true || this.orderedCustomFieldsOnly === true
            ? "est-ops-card est-ops-card_locked"
            : "est-ops-card"
      };
    });
  }

  get opsGridClass() {
    return this.operationTypeValues.length === 1
      ? "est-ops-grid est-ops-grid_single"
      : "est-ops-grid";
  }

  get activeContractServiceEmptyMessage() {
    if (
      this.contractServicesLoadError ||
      this.loadingContractHistory ||
      this.loadingOpportunityAccount ||
      this.loadingContractServices
    ) {
      return "";
    }
    if (!this.opportunityAccountId) {
      return "商談に取引先がないため、契約サービスを選べません。";
    }
    if (this.activeContractServices.length === 0) {
      return "この取引先に、受注済かつ未解約の契約サービスがありません。";
    }
    return "";
  }

  get showActiveContractServiceEmptyMessage() {
    return Boolean(this.activeContractServiceEmptyMessage);
  }

  get showContractServicesLoadError() {
    return Boolean(this.contractServicesLoadError);
  }

  get showContractHistoryLoading() {
    return this.loadingContractHistory === true;
  }

  get showContractServicesLoading() {
    return (
      !this.isNewType &&
      (this.loadingOpportunityAccount || this.loadingContractServices)
    );
  }

  get displayNewHistoryVersion() {
    return "1";
  }

  get displayBaseHistoryVersion() {
    return formatHistoryVersion(this.baseHistoryVersion);
  }

  @wire(getBillingAccountsByAccount, { accountId: "$opportunityAccountId" })
  wiredRelatedBillingAccounts(result) {
    this._wiredRelatedBillingAccounts = result;
    const { data, error } = result;
    if (error) {
      this.relatedBillingAccounts = [];
      this.billingAccountsLoadError =
        "請求アカウントの読み込みに失敗しました。";
      return;
    }
    this.billingAccountsLoadError = "";
    if (!data) {
      return;
    }
    this.relatedBillingAccounts = data.map((item) => ({
      id: item.id,
      name: item.name
    }));
    this.maybeAutoSelectBillingAccount();
  }

  @wire(getActiveContractServicesByAccount, {
    accountId: "$opportunityAccountId"
  })
  wiredActiveContractServices(result) {
    this._wiredActiveContractServices = result;
    const { data, error } = result;

    if (!this.opportunityAccountId) {
      this.activeContractServices = [];
      this.contractServicesLoadError = "";
      // 取引先未確定中は「候補なし」と出さない（読込中扱い）
      this.loadingContractServices = this.loadingOpportunityAccount;
      return;
    }

    if (error) {
      this.activeContractServices = [];
      this.loadingContractServices = false;
      this.contractServicesLoadError = "契約サービスの読み込みに失敗しました。";
      return;
    }

    this.contractServicesLoadError = "";
    if (data === undefined) {
      this.loadingContractServices = true;
      return;
    }

    this.loadingContractServices = false;
    this.activeContractServices = data.map((item) => ({
      id: item.id,
      name: item.name,
      lifecycle: item.lifecycle || "",
      lifecycleLabel: item.lifecycleLabel || "",
      status: item.status || "",
      statusLabel: item.statusLabel || "",
      termStart: formatOptionDate(item.termStart),
      termEnd: formatOptionDate(item.termEnd),
      renewalRemainingMonths: item.renewalRemainingMonths,
      historyName: item.historyName || "",
      version: item.version,
      billingAccountId: item.billingAccountId || "",
      billingAccountName: item.billingAccountName || "",
      currentProductNames: item.currentProductNames || ""
    }));
    this.maybeAutoSelectContractService();
    this.maybeSyncLifecycleToParent();
  }

  @wire(getRecord, {
    recordId: "$recordId",
    fields: [OPP_NAME_FIELD, OPP_ACCOUNT_ID_FIELD]
  })
  wiredOpportunity({ data, error }) {
    if (error) {
      this.loadingOpportunityAccount = false;
      this.opportunityAccountId = "";
      return;
    }
    if (!data) {
      return;
    }
    this.loadingOpportunityAccount = false;
    const nextAccountId = getFieldValue(data, OPP_ACCOUNT_ID_FIELD) || "";
    if (nextAccountId !== this.opportunityAccountId) {
      // 取引先が決まった／変わった直後は候補 wire の応答まで読込中
      this.loadingContractServices = !this.isNewType && Boolean(nextAccountId);
      this.activeContractServices = [];
    }
    this.opportunityAccountId = nextAccountId;
    this.opportunityName = getFieldValue(data, OPP_NAME_FIELD) || "";
    this.maybeApplyDefaultNames();
  }

  @wire(getRecord, {
    recordId: "$contractServiceId",
    fields: [CS_BILLING_ACCOUNT_FIELD, CS_BILLING_ACCOUNT_NAME_FIELD]
  })
  wiredContractServiceBilling({ data }) {
    if (this.isNewType || !data) {
      return;
    }
    const billingId = getFieldValue(data, CS_BILLING_ACCOUNT_FIELD) || "";
    const billingName =
      getFieldValue(data, CS_BILLING_ACCOUNT_NAME_FIELD) || "";
    if (billingName) {
      this.linkedBillingAccountName = billingName;
    }
    // ユーザーが選び直したあとはサービス由来で上書きしない
    if (this._billingAccountResolved) {
      return;
    }
    if (billingId && billingId !== this.billingAccountId) {
      this.emitChange({ billingAccountId: billingId });
    }
  }

  @wire(getRecord, {
    recordId: "$billingAccountId",
    fields: [BA_NAME_FIELD]
  })
  wiredBillingAccountName({ data }) {
    if (!data) {
      return;
    }
    const name = getFieldValue(data, BA_NAME_FIELD) || "";
    if (name) {
      this.linkedBillingAccountName = name;
    }
  }

  maybeAutoSelectBillingAccount() {
    // New: 候補が1件なら自動選択。続きは契約サービス側の請求先をデフォルトにする。
    if (!this.isNewType) {
      return;
    }
    if (this._billingAccountResolved || this.billingAccountId) {
      return;
    }
    if (this.allowOtherAccountBilling) {
      return;
    }
    if (this.relatedBillingAccounts.length !== 1) {
      return;
    }
    this._billingAccountResolved = true;
    this.emitChange({ billingAccountId: this.relatedBillingAccounts[0].id });
  }

  /** 続き: 選択サービスに紐づく請求アカウントをデフォルトセット */
  applyBillingFromSelectedService(service) {
    this._billingAccountResolved = false;
    this.allowOtherAccountBilling = false;
    this.linkedBillingAccountName = service?.billingAccountName || "";
    this.emitChange({
      billingAccountId: service?.billingAccountId || ""
    });
  }

  maybeAutoSelectContractService() {
    if (this.isNewType || this.contractServiceId) {
      return;
    }
    if (this.activeContractServices.length !== 1) {
      return;
    }
    const only = this.activeContractServices[0];
    this.requestContractServiceSelection(
      only.id,
      only.name || "",
      only.lifecycle || ""
    );
    this.applyBillingFromSelectedService(only);
  }

  /**
   * 編集／コピーで preset に Lifecycle が無いとき、候補一覧から親 state へ補う。
   * サービス再選択はしない（明細・履歴を捨てない）。
   */
  maybeSyncLifecycleToParent() {
    if (this.isNewType || !this.contractServiceId) {
      return;
    }
    const current =
      (this._wizardData && this._wizardData.serviceLifecycle) || "";
    if (current) {
      return;
    }
    const option = this.selectedContractService;
    if (!option || !option.lifecycle) {
      return;
    }
    this.emitChange({ serviceLifecycle: option.lifecycle });
  }

  /**
   * 空欄のときだけ商談名ベースのデフォルトを入れる。
   * 全タイプ: 契約履歴名 = 「{商談名} の契約履歴」
   * New のみ: 契約サービス名 = 「{商談名} の契約サービス」
   */
  maybeApplyDefaultNames() {
    if (!this._wizardData || this.isStandardFieldsReadonly) {
      return;
    }
    const oppName = this.resolvedOpportunityName;
    if (!oppName) {
      return;
    }

    const fields = {};
    if (this.isNewType && !(this.contractServiceName || "").trim()) {
      fields.contractServiceName = `${oppName} の契約サービス`;
    }
    if (!(this.contractHistoryName || "").trim()) {
      // サービス切替で履歴名がクリアされたあとも、空なら都度入れる
      fields.contractHistoryName = `${oppName} の契約履歴`;
    }
    if (Object.keys(fields).length > 0) {
      this.emitChange(fields);
    }
  }

  handleServiceNameChange(event) {
    this.emitChange({ contractServiceName: event.target.value });
  }

  handleHistoryNameChange(event) {
    this.emitChange({ contractHistoryName: event.target.value });
  }

  handleBillingAccountComboboxChange(event) {
    this._billingAccountResolved = true;
    this.emitChange({ billingAccountId: event.target.value || "" });
  }

  handleBillingAccountChange(event) {
    this._billingAccountResolved = true;
    this.emitChange({ billingAccountId: event.detail.recordId || "" });
  }

  handleReselectBillingAccount() {
    // 続き系はサービス wire がデフォルトを戻さないよう resolved のままにする。
    // New は候補1件の自動選択を再度効かせるため false。
    this._billingAccountResolved = !this.isNewType;
    this.allowOtherAccountBilling = false;
    this.emitChange({ billingAccountId: "" });
  }

  handleAllowOtherAccountBillingChange(event) {
    this.allowOtherAccountBilling = event.target.checked === true;
    if (this.allowOtherAccountBilling) {
      return;
    }
    const relatedIds = new Set(
      this.relatedBillingAccounts.map((item) => item.id)
    );
    if (this.billingAccountId && !relatedIds.has(this.billingAccountId)) {
      this.emitChange({ billingAccountId: "" });
    }
  }

  handleServicePickerToggle() {
    if (this.isContractServiceComboboxDisabled) {
      return;
    }
    this.servicePickerOpen = !this.servicePickerOpen;
  }

  handleServicePickerFocusOut(event) {
    const next = event.relatedTarget;
    if (next && event.currentTarget.contains(next)) {
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    window.setTimeout(() => {
      this.servicePickerOpen = false;
    }, 0);
  }

  handleServicePickerSelect(event) {
    const contractServiceId = event.currentTarget.dataset.id || "";
    const matched = this.activeContractServices.find(
      (service) => service.id === contractServiceId
    );
    this.servicePickerOpen = false;
    this.requestContractServiceSelection(
      contractServiceId,
      matched?.name || "",
      matched?.lifecycle || ""
    );
    this.applyBillingFromSelectedService(matched);
  }

  handleTypeSelect(event) {
    if (this.editMode === true || this.orderedCustomFieldsOnly === true) {
      return;
    }
    const selectedType = event.currentTarget.dataset.type;
    if (!selectedType || selectedType === this.selectedType) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("typechange", {
        bubbles: true,
        composed: true,
        detail: { selectedType }
      })
    );
  }

  requestContractServiceSelection(
    contractServiceId,
    contractServiceName,
    serviceLifecycle
  ) {
    this.dispatchEvent(
      new CustomEvent("serviceselect", {
        bubbles: true,
        composed: true,
        detail: {
          contractServiceId: contractServiceId || "",
          contractServiceName: (contractServiceName || "").trim(),
          serviceLifecycle: serviceLifecycle || ""
        }
      })
    );
  }

  emitChange(fields) {
    if (!fields || Object.keys(fields).length === 0) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("changefield", {
        bubbles: true,
        composed: true,
        detail: fields
      })
    );
  }
}

function formatOptionDate(value) {
  if (!value) {
    return "";
  }
  if (typeof value === "string") {
    return value.slice(0, 10);
  }
  try {
    const year = value.getFullYear?.() ?? value.year;
    const month = (value.getMonth?.() ?? value.month - 1) + 1;
    const day = value.getDate?.() ?? value.day;
    if (!year || !month || !day) {
      return String(value).slice(0, 10);
    }
    return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
  } catch {
    return String(value).slice(0, 10);
  }
}

/** 操作ヘルプ用: YYYY/MM/DD */
function formatHelpDate(value) {
  const iso = formatOptionDate(value);
  if (!iso || iso.length < 10) {
    return "";
  }
  return `${iso.slice(0, 4)}/${iso.slice(5, 7)}/${iso.slice(8, 10)}`;
}

/**
 * 操作ヘルプ行。差し込み日付は emphasis: true（表示時に強調）。
 * 日付と助詞のあいだに余分な空白は入れない。
 */
function buildOperationHelpLines(type, termStartIso, termEndIso) {
  const termStart = formatHelpDate(termStartIso);
  const termEnd = formatHelpDate(termEndIso);
  const termEndNext = formatHelpDate(addDaysToIsoDate(termEndIso, 1));
  let lines = [];

  if (type === "Change") {
    const period = termStart && termEnd ? `${termStart}～${termEnd}` : "";
    const extendFrom = termEndNext || "";
    lines = [
      period
        ? [
            helpSeg(period, true),
            helpSeg("の期間内に課金変更を行います", false)
          ]
        : [helpSeg("期間内に課金変更を行います", false)],
      extendFrom
        ? [
            helpSeg(
              "商材追加 / 単価・数量・金額の変更 / 途中停止ができ、同時に",
              false
            ),
            helpSeg(extendFrom, true),
            helpSeg("から契約延長も可能です", false)
          ]
        : [
            helpSeg(
              "商材追加 / 単価・数量・金額の変更 / 途中停止ができ、同時に契約延長も可能です",
              false
            )
          ]
    ];
  } else if (type === "Renew") {
    lines = termEndNext
      ? [[helpSeg(termEndNext, true), helpSeg("から契約を延長します", false)]]
      : [[helpSeg("契約を延長します", false)]];
  } else if (type === "Cancel") {
    lines = termEnd
      ? [
          [
            helpSeg(termEnd, true),
            helpSeg("の期間満了をもって解約します", false)
          ]
        ]
      : [[helpSeg("期間満了をもって解約します", false)]];
  } else if (type === "Add") {
    lines = [[helpSeg("都度契約に1回課金を追加します", false)]];
  }

  return lines.map((segments, lineIndex) => ({
    key: `${type}-line-${lineIndex}`,
    segments: segments.map((seg, segIndex) => ({
      key: `${type}-line-${lineIndex}-seg-${segIndex}`,
      text: seg.text,
      emphasis: seg.emphasis === true,
      className:
        seg.emphasis === true ? "est-ops-help-date" : "est-ops-help-text"
    }))
  }));
}

function helpSeg(text, emphasis) {
  return { text, emphasis };
}
