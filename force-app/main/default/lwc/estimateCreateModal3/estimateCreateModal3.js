import { LightningElement, api, track, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import {
  getRecord,
  getFieldValue,
  getRecordNotifyChange
} from "lightning/uiRecordApi";
import { refreshApex } from "@salesforce/apex";
import CS_TAX_PERCENT_FIELD from "@salesforce/schema/ContractService__c.TaxPercent__c";
import getProductDefaults from "@salesforce/apex/EstimateCreateController.getProductDefaults";
import getRecurringContractProducts from "@salesforce/apex/EstimateCreateController.getRecurringContractProducts";
import getRenewContractProducts from "@salesforce/apex/EstimateCreateController.getRenewContractProducts";
import getContractHistoryInfo from "@salesforce/apex/EstimateCreateController.getContractHistoryInfo";
import getEstimateRemarkMasterText from "@salesforce/apex/EstimateCreateController.getEstimateRemarkMasterText";
import getInvoiceSettingOptions from "@salesforce/apex/EstimateCreateController.getInvoiceSettingOptions";
import getDefaultInvoiceSettingLabel from "@salesforce/apex/EstimateCreateController.getDefaultInvoiceSettingLabel";
import {
  BILLING_TYPE_RECURRING,
  BILLING_TYPE_ONE_TIME,
  MONTHLY_BILLING_CYCLE,
  isRecurringLine,
  buildDisplayUnit,
  resolveDisplayUnit,
  resolveLineAmount,
  countBillingCycles,
  endDateForMonthlyCycles,
  alignMonthlyEndDate,
  adjustMonthlyEndByCycles,
  isHeaderDatesReady,
  filterInvoiceSettingOptions,
  resolveInvoiceTypeForBillingType,
  validateInvoiceSettingForBillingType,
  normalizeInvoiceSettingLabel,
  INVOICE_SETTING_PREPAID_START,
  addYearsToIsoDate,
  addMonthsToIsoDate,
  addDaysToIsoDate,
  normalizeDateInput,
  isValidIsoDate,
  PRODUCT_TYPE_NEW,
  PRODUCT_TYPE_RENEW,
  PRODUCT_TYPE_ORIGINAL,
  PRODUCT_TYPE_REMAKE,
  isChangeOriginalLine,
  isChangeRemakeLine,
  resolveChangePairAmountsFromSource,
  isRenewProductLine,
  resolveProductTypeBadge,
  isChangeContinuationLine,
  canDuplicateProductLine,
  getEarliestChangeBillingThresholdDate,
  formatCurrencyNumber,
  formatAmountYen,
  parseUnitPriceInput,
  parseQuantityInput,
  parseAmountYenInput,
  roundUnitPrice,
  roundQuantity,
  roundAmountYen,
  deriveUnitPriceFromAmount,
  resolveInvoicePreviewRoundingDiff,
  restoreAmountEntryFromSavedAmount,
  resolveInvoiceAnchorFields,
  INVOICE_ANCHOR_DISPLAY_TITLE
} from "c/estimateLineItemUtils";
import {
  buildCustomFieldInputs,
  filterCustomFieldDefinitionsForWizardType,
  filterVisibleCustomFieldDefinitions,
  syncCustomFieldsForVisibility,
  shallowEqualFieldMaps
} from "c/estimateWizardCustomFields";
import { createRowId } from "c/estimateWizardState";
import {
  UI_ONLY_PRODUCT_FIELDS,
  stripUiFields,
  serializeBusinessProduct
} from "./businessProduct";
import {
  buildProductsFingerprint,
  shouldSyncProductsFromParent
} from "./productDisplaySync";
import {
  resolveSavedContractStartDate,
  resolveSavedContractEndDate
} from "./contractDateInit";
import {
  createConfirmRequestId,
  hasEstimateRemarksText
} from "./remarksConfirm";

export { stripUiFields, serializeBusinessProduct, UI_ONLY_PRODUCT_FIELDS };

/** 契約サービス未作成時の見積総額（税込）表示用。保存・PDF の税率ロジックとは別。 */
const DEFAULT_TAX_PERCENT_WHEN_NO_SERVICE = 10;
/** 商品名: 長い商品時の下限サイズに統一（rem）。溢れは ellipsis。 */
const PRODUCT_NAME_FONT_REM = 0.5625;

export default class EstimateCreateModal3 extends LightningElement {
  @api recordId;
  @api orderedCustomFieldsOnly = false;

  _wizardData;
  _loadingContractHistory = false;
  _isConnected = false;
  /** bootstrap / async 読込の世代。切断・身元変更で進め、遅延 emit を捨てる。 */
  _bootstrapGeneration = 0;
  _wiredContractServiceTax;
  _wizardIdentityKey = "";
  _productFieldDefinitions = [];
  _serviceFieldDefinitions = [];
  _historyFieldDefinitions = [];
  _opportunityDefaultContext = {};
  /** 自 emit した selectedProducts の fingerprint（エコーバック同期を抑止）。 */
  _lastEmittedProductsFingerprint = "";
  /** 直近 syncDisplayFromParent 済み fingerprint。 */
  _lastSyncedProductsFingerprint = "";
  /** 行ごとの商品選択リクエスト連番（遅い getProductDefaults の後勝ち適用を捨てる）。 */
  _productSelectSeqByRowId = {};
  _fitProductNamesRaf = null;
  _resizeObserver = null;

  @api
  get productFieldDefinitions() {
    return this._productFieldDefinitions;
  }
  set productFieldDefinitions(value) {
    this._productFieldDefinitions = value || [];
    this.refreshCustomFieldsFromParentContext();
  }

  @api
  get serviceFieldDefinitions() {
    return this._serviceFieldDefinitions;
  }
  set serviceFieldDefinitions(value) {
    this._serviceFieldDefinitions = value || [];
    if (this._isConnected) {
      this.emitDefaultContractCustomFieldsIfNeeded();
    }
  }

  @api
  get historyFieldDefinitions() {
    return this._historyFieldDefinitions;
  }
  set historyFieldDefinitions(value) {
    this._historyFieldDefinitions = value || [];
    if (this._isConnected) {
      this.emitDefaultContractCustomFieldsIfNeeded();
    }
  }

  @api
  get opportunityDefaultContext() {
    return this._opportunityDefaultContext;
  }
  set opportunityDefaultContext(value) {
    this._opportunityDefaultContext = value || {};
    this.refreshCustomFieldsFromParentContext();
    if (this._isConnected) {
      this.emitDefaultContractCustomFieldsIfNeeded();
    }
  }

  @api
  get loadingContractHistory() {
    return this._loadingContractHistory;
  }

  set loadingContractHistory(value) {
    this._loadingContractHistory = value === true;
    this.maybeBootstrapForIdentityChange();
  }

  @api
  get wizardData() {
    return this._wizardData;
  }

  set wizardData(value) {
    this._wizardData = value;
    this.maybeBootstrapForIdentityChange();
    if (this._isConnected) {
      this.emitDefaultContractCustomFieldsIfNeeded();
    }
  }

  maybeBootstrapForIdentityChange() {
    // 親からの毎回書き戻しで再ブートストラップしない。
    // type / 契約サービス / 契約履歴 / 履歴読込中フラグの身元が変わったときだけやり直す。
    if (!this._isConnected) {
      return;
    }
    const identityKey = this.buildWizardIdentityKey();
    if (identityKey && identityKey !== this._wizardIdentityKey) {
      this._wizardIdentityKey = identityKey;
      // 進行中の非同期読込／emit を無効化してから再ブートストラップ
      this._bootstrapGeneration += 1;
      this.bootstrapFromWizardData();
    } else if (!this._bootstrapInFlight) {
      // 親が正。内容が変わったときだけ表示キャッシュを同期する。
      // 自 emit のエコーバックでは再 decorate しない。
      const parentProducts =
        (this._wizardData && this._wizardData.selectedProducts) || [];
      if (
        shouldSyncProductsFromParent(
          parentProducts,
          this._lastEmittedProductsFingerprint,
          this._lastSyncedProductsFingerprint
        )
      ) {
        this.syncDisplayFromParent();
      }
    }
  }

  /** 表示用キャッシュ。正本は wizardData.selectedProducts。 */
  @track itemList = [];
  @track isLoadingChangeProducts = false;
  @track isLoadingRenewProducts = false;
  @track changeLoadError = "";
  /** Global open/close for all product line custom fields (default open). 親へは送らない。 */
  @track productCustomFieldsExpanded = true;
  /** セクション開閉（ローカル表示のみ）。 */
  @track recurringPeriodExpanded = true;
  @track productLinesExpanded = true;
  @track renewLoadError = "";
  @track cancelLoadError = "";
  /** Renew/Cancel の有効日自動設定用（UI派生。親には持たない）。 */
  @track fixedEffectiveDate = "";
  @track isStartDateReadonly = false;
  @track isEndDateReadonly = false;
  @track isLoadingDates = false;
  @track remarkMasterPickerKey = "remark-master-0";
  @track invoiceSettingOptions = [];
  defaultInvoiceType = "";
  @track productModalRowId = null;
  @track productModalProductId = "";
  _wiredInvoiceSettingOptions;
  _wiredDefaultInvoiceSettingLabel;

  /** 初期化中フラグ。再入防止・表示同期抑止・commitItemList の emit 抑止。 */
  _bootstrapInFlight = false;
  _bootstrapQueued = false;
  /** 直近で親へ伝えた準備状態。変化したときだけ通知する。 */
  _lastNotifiedStepReady = true;
  /** 備考マスタ確認ダイアログの Promise resolve（requestId → resolve）。 */
  _confirmResolvers = new Map();
  _productModalFocused = false;
  _productModalReturnFocusEl = null;
  _boundProductModalKeydown = null;

  // --- 業務データは親の wizardData が唯一の正 ---
  get contractStartDate() {
    return (this._wizardData && this._wizardData.contractStartDate) || "";
  }
  get contractEndDate() {
    return resolveSavedContractEndDate(this._wizardData);
  }
  get contractEffectiveDate() {
    return (this._wizardData && this._wizardData.contractEffectiveDate) || "";
  }
  get previousTermStartDate() {
    return (this._wizardData && this._wizardData.previousTermStartDate) || "";
  }
  get previousTermEndDate() {
    return (this._wizardData && this._wizardData.previousTermEndDate) || "";
  }
  get contractHistoryName() {
    return (this._wizardData && this._wizardData.contractHistoryName) || "";
  }
  get estimateRemarkMasterId() {
    return (this._wizardData && this._wizardData.estimateRemarkMasterId) || "";
  }
  get estimateRemarks() {
    return (this._wizardData && this._wizardData.estimateRemarks) || "";
  }
  get changeSourceProducts() {
    return (this._wizardData && this._wizardData.changeSourceProducts) || [];
  }
  get contractServiceId() {
    return (this._wizardData && this._wizardData.contractServiceId) || "";
  }
  /** @wire 用。空文字だと不正 ID になるため undefined。 */
  get wiredContractServiceId() {
    return this.contractServiceId || undefined;
  }

  @wire(getRecord, {
    recordId: "$wiredContractServiceId",
    fields: [CS_TAX_PERCENT_FIELD]
  })
  wiredContractServiceTax(result) {
    this._wiredContractServiceTax = result;
  }

  matchingInfo = {
    primaryField: {
      fieldPath: "Name"
    }
  };

  productDisplayInfo = {
    additionalFields: ["ProductCode"]
  };

  // Apex 側の getProductDefaults と同じ条件で候補を絞り、選択できない商品を出さない。
  // Add は一回課金のみ（検索時点で継続課金を出さない）。
  get productPickerFilter() {
    const criteria = [
      {
        fieldPath: "AvailableForContract__c",
        operator: "eq",
        value: true
      }
    ];
    if (this.isAddType) {
      criteria.push({
        fieldPath: "BillingType__c",
        operator: "eq",
        value: BILLING_TYPE_ONE_TIME
      });
    }
    return { criteria };
  }

  remarkMasterMatchingInfo = {
    primaryField: {
      fieldPath: "Name"
    }
  };

  remarkMasterDisplayInfo = {
    additionalFields: ["NoteText__c"]
  };

  @wire(getInvoiceSettingOptions)
  wiredInvoiceSettingOptions(result) {
    this._wiredInvoiceSettingOptions = result;
    if (result?.data) {
      this.invoiceSettingOptions = result.data;
      this.refreshRowInvoiceSettings();
    }
  }

  @wire(getDefaultInvoiceSettingLabel)
  wiredDefaultInvoiceSettingLabel(result) {
    this._wiredDefaultInvoiceSettingLabel = result;
    if (result?.data) {
      this.defaultInvoiceType = result.data;
      this.refreshRowInvoiceSettings();
    }
  }

  get resolvedDefaultInvoiceType() {
    return this.defaultInvoiceType || INVOICE_SETTING_PREPAID_START;
  }

  refreshRowInvoiceSettings(options = {}) {
    const emit = options.emit !== false && !this._bootstrapInFlight;
    if (!this.itemList.length) {
      return;
    }
    let firstInvoiceSettingError = null;
    const next = this.itemList.map((item) => {
      const billingType = item.billingType || "";
      const invoiceType = resolveInvoiceTypeForBillingType(
        item.invoiceType,
        billingType,
        this.invoiceSettingOptions,
        this.resolvedDefaultInvoiceType
      );
      const invoiceSettingError = validateInvoiceSettingForBillingType(
        billingType,
        invoiceType
      );
      if (invoiceSettingError && !firstInvoiceSettingError) {
        firstInvoiceSettingError = invoiceSettingError;
      }
      return {
        ...item,
        invoiceType
      };
    });
    this.commitItemList(next, { emit });
    if (firstInvoiceSettingError) {
      this.showToast("請求設定が不正です", firstInvoiceSettingError, "error");
    }
  }

  @api
  get isStepReady() {
    return (
      !this._bootstrapInFlight &&
      !this.isLoadingChangeProducts &&
      !this.isLoadingRenewProducts &&
      !this.isLoadingDates
    );
  }

  get showStepBusyBanner() {
    return !this.isStepReady;
  }

  get stepBusyBannerMessage() {
    if (this.isLoadingDates) {
      return "契約期間を読み込んでいます。完了するまで内容は確定しません。";
    }
    if (this.isLoadingChangeProducts || this.isLoadingRenewProducts) {
      return "商品明細を読み込んでいます。完了するまで表示内容は保存対象と一致しません。";
    }
    if (this._bootstrapInFlight) {
      return "商品明細を更新しています。完了するまで保存しないでください。";
    }
    return "商品明細を更新しています。";
  }

  /**
   * 画面上の明細・期間・備考を親 wizardData へ強制同期する。
   * 保存直前に呼び、入力中の表示と保存ペイロードのズレを防ぐ。
   * @returns {boolean} 同期できた（読込中でない）とき true
   */
  @api
  flushToParent() {
    if (!this.isStepReady) {
      return false;
    }
    this.applyBusinessFields({
      contractStartDate: this.contractStartDate,
      contractEndDate: this.contractEndDate,
      contractEffectiveDate: this.contractEffectiveDate,
      previousTermStartDate: this.previousTermStartDate,
      previousTermEndDate: this.previousTermEndDate,
      estimateRemarkMasterId: this.estimateRemarkMasterId,
      estimateRemarks: this.estimateRemarks
    });
    this.emitProductsFromItemList();
    return true;
  }

  /**
   * 商品・日付の読込中は親が「次へ」「保存」を止められるようにする。
   * 未完成の明細のまま保存されるのを防ぐ。
   */
  notifyStepReadyChange() {
    if (!this._isConnected) {
      return;
    }
    const ready = this.isStepReady;
    if (ready === this._lastNotifiedStepReady) {
      return;
    }
    this._lastNotifiedStepReady = ready;
    this.dispatchEvent(
      new CustomEvent("loadingchange", {
        bubbles: true,
        composed: true,
        detail: { loading: !ready }
      })
    );
  }

  /**
   * 非同期完了後に、このインスタンス／ブートストラップ世代がまだ有効か。
   */
  isBootstrapGenerationCurrent(generation) {
    return (
      this._isConnected === true &&
      generation != null &&
      generation === this._bootstrapGeneration
    );
  }

  buildInvoiceTypeOptions(invoiceType, billingType) {
    const options = filterInvoiceSettingOptions(
      this.invoiceSettingOptions,
      billingType
    ).map((option) => ({
      label: option.label,
      value: option.label,
      isSelected: option.label === invoiceType
    }));
    const normalized = normalizeInvoiceSettingLabel(invoiceType);
    if (normalized && !options.some((option) => option.value === normalized)) {
      options.push({
        label: normalized,
        value: normalized,
        isSelected: true
      });
    }
    return options;
  }

  resolveRowInvoiceType(invoiceType, billingType) {
    return resolveInvoiceTypeForBillingType(
      invoiceType,
      billingType,
      this.invoiceSettingOptions,
      this.resolvedDefaultInvoiceType
    );
  }

  get effectiveSelectedType() {
    return (this._wizardData && this._wizardData.selectedType) || "";
  }

  get isNewType() {
    return this.effectiveSelectedType === "New";
  }

  get isAddType() {
    return this.effectiveSelectedType === "Add";
  }

  get isChangeType() {
    return this.effectiveSelectedType === "Change";
  }

  get isRenewType() {
    return this.effectiveSelectedType === "Renew";
  }

  get hasRecurringProductLines() {
    return (this.itemList || []).some(
      (row) =>
        row &&
        row.productId &&
        Number(row.quantity) > 0 &&
        isRecurringLine(row)
    );
  }

  /** 継続課金の契約期間パネル（1回のみ New/Add では出さない） */
  get showRecurringPeriodPanel() {
    if (this.isAddType) {
      return false;
    }
    if (this.isNewType) {
      return this.hasRecurringProductLines;
    }
    if (this.isChangeType) {
      // 一回追加のみでもヘッダ（継続期間）は前回継承で表示
      return true;
    }
    return this.isRenewType || this.isCancelType;
  }

  get isCancelType() {
    return this.effectiveSelectedType === "Cancel";
  }

  get isEffectiveDateReadonly() {
    return (
      this.orderedCustomFieldsOnly === true ||
      this.isNewType ||
      this.isRenewType ||
      this.isCancelType ||
      this.isChangeType
    );
  }

  get isHistoryNameReadonly() {
    return this.orderedCustomFieldsOnly === true;
  }

  get isRemarksReadonly() {
    return this.orderedCustomFieldsOnly === true;
  }

  get estimateRemarkMasterDisplayValue() {
    return this.estimateRemarkMasterId || "—";
  }

  get showProductTable() {
    const type = this.effectiveSelectedType;
    return (
      type === "New" ||
      type === "Change" ||
      type === "Renew" ||
      type === "Add"
    );
  }

  get showAddRowButton() {
    return (
      this.showProductTable &&
      this.canEditProducts &&
      !this.isChangeType &&
      this.orderedCustomFieldsOnly !== true
    );
  }

  buildBillingTypeFlipView(row, billingType, forceReadonly) {
    const masterBillingType =
      row.productMasterBillingType ||
      (billingType === BILLING_TYPE_RECURRING ||
      billingType === BILLING_TYPE_ONE_TIME
        ? billingType
        : "");
    const canFlipOnNew =
      this.isNewType &&
      !forceReadonly &&
      !!billingType &&
      masterBillingType === BILLING_TYPE_RECURRING;
    if (canFlipOnNew && billingType === BILLING_TYPE_RECURRING) {
      return {
        showBillingTypeFlipLink: true,
        billingTypeFlipTarget: BILLING_TYPE_ONE_TIME,
        billingTypeFlipTitle: "1回課金に切り替え"
      };
    }
    if (canFlipOnNew && billingType === BILLING_TYPE_ONE_TIME) {
      return {
        showBillingTypeFlipLink: true,
        billingTypeFlipTarget: BILLING_TYPE_RECURRING,
        billingTypeFlipTitle: "継続課金に切り替え"
      };
    }
    return {
      showBillingTypeFlipLink: false,
      billingTypeFlipTarget: "",
      billingTypeFlipTitle: ""
    };
  }

  get billingTypeSelectOptions() {
    return [
      { label: BILLING_TYPE_RECURRING, value: BILLING_TYPE_RECURRING },
      { label: BILLING_TYPE_ONE_TIME, value: BILLING_TYPE_ONE_TIME }
    ];
  }

  get changeProductGroups() {
    if (!this.isChangeType) {
      return [];
    }
    const groups = [];
    const groupMap = new Map();

    for (const row of this.itemList) {
      if (isChangeOriginalLine(row)) {
        const group = {
          pairId: row.pairId,
          sourceContractProductId: row.sourceContractProductId,
          productName: row.productName || "",
          original: row,
          remakeRows: []
        };
        groupMap.set(row.pairId, group);
        groups.push(group);
        continue;
      }
      if (isChangeRemakeLine(row) && row.pairId) {
        const group = groupMap.get(row.pairId);
        if (group) {
          group.remakeRows.push(row);
        }
      }
    }

    return groups.map((group) => ({
      ...group,
      remakeCount: group.remakeRows.length,
      addButtonKey: `add-${group.pairId}`
    }));
  }

  get changeNewProductRows() {
    if (!this.isChangeType) {
      return [];
    }
    return this.itemList.filter((row) => isChangeContinuationLine(row));
  }

  get displayItemList() {
    let rows;
    if (!this.isChangeType) {
      rows = this.itemList;
    } else {
      rows = this.buildChangeDisplayRows();
    }
    const withDetails = this.withCustomDetailRows(rows);
    const openId = this.productModalRowId;
    return withDetails.map((row) => {
      if (!row || row.isGroupHeader || row.isCustomDetailRow) {
        return row;
      }
      const isProductPickerOpen = openId != null && row.id === openId;
      return {
        ...row,
        isProductPickerOpen,
        productTdClass: isProductPickerOpen
          ? "est-td est-td-center est-td-product est-td-product_picking"
          : "est-td est-td-center est-td-product"
      };
    });
  }

  get productModalPickerKey() {
    return `product-picker-${this.productModalRowId || "none"}`;
  }

  buildChangeDisplayRows() {
    const rows = [];
    for (const group of this.changeProductGroups) {
      rows.push({
        id: `group-header-${group.pairId}`,
        isGroupHeader: true,
        isSectionHeader: false,
        groupHeaderTitle: group.productName || "（商品未選択）",
        groupHeaderClass: "est-change-group-card__header",
        groupHeaderRowClass: "est-change-group-header-row"
      });
      rows.push({
        ...group.original,
        rowContext: "changeOriginal",
        changeGroupBoundary: "start"
      });
      group.remakeRows.forEach((remake, index) => {
        rows.push({
          ...remake,
          rowContext: "changeRemake",
          canDelete:
            this.orderedCustomFieldsOnly !== true &&
            group.remakeRows.length > 1,
          showAddRemakeButton:
            this.orderedCustomFieldsOnly !== true &&
            index === group.remakeRows.length - 1,
          groupPairId: group.pairId,
          changeGroupBoundary:
            index === group.remakeRows.length - 1 ? "end" : "middle"
        });
      });
      if (group.remakeRows.length === 0) {
        const lastOriginal = rows[rows.length - 1];
        if (lastOriginal) {
          lastOriginal.changeGroupBoundary = "end";
        }
      }
    }

    rows.push({
      id: "__new_products_header__",
      rowContext: "newSectionHeader",
      isGroupHeader: true,
      isSectionHeader: this.orderedCustomFieldsOnly !== true,
      groupHeaderTitle: "新しい商品",
      groupHeaderClass:
        "est-change-group-card__header est-change-group-card__header_new",
      groupHeaderRowClass:
        "est-change-group-header-row est-change-group-header-row_new"
    });

    const newRows = this.changeNewProductRows;
    newRows.forEach((row, index) => {
      rows.push({
        ...row,
        rowContext: "changeNew",
        canDelete: this.orderedCustomFieldsOnly !== true,
        changeGroupBoundary: index === newRows.length - 1 ? "end" : "middle",
        changeGroupTone: "new"
      });
    });
    if (newRows.length === 0) {
      const headerRow = rows[rows.length - 1];
      if (headerRow) {
        headerRow.changeGroupBoundary = "end";
      }
    }

    return rows.map((row) => this.applyChangeGroupBoundaryClass(row));
  }

  get hasProductCustomFields() {
    // Product2 Visibility は行ごとに評価する。ヘッダーボタンは Type のみで判定。
    return (
      filterCustomFieldDefinitionsForWizardType(
        this.productFieldDefinitions,
        this.effectiveSelectedType
      ).length > 0
    );
  }

  get productCustomToggleClass() {
    return this.productCustomFieldsExpanded
      ? "est-btn-custom est-btn-custom_active"
      : "est-btn-custom";
  }

  get productCustomChevronClass() {
    return this.productCustomFieldsExpanded
      ? "est-custom-chevron est-custom-chevron_open"
      : "est-custom-chevron";
  }

  get productCustomExpandedAria() {
    return this.productCustomFieldsExpanded ? "true" : "false";
  }

  get contractServiceCustomFields() {
    return this._wizardData?.contractServiceCustomFields || {};
  }

  get contractHistoryCustomFields() {
    return this._wizardData?.contractHistoryCustomFields || {};
  }

  get serviceCustomFieldsExpanded() {
    return this._wizardData?.serviceCustomFieldsExpanded !== false;
  }

  get historyCustomFieldsExpanded() {
    return this._wizardData?.historyCustomFieldsExpanded !== false;
  }

  /** 契約カスタムは1トグル。サービス／履歴フラグは同期して扱う。 */
  get contractCustomFieldsExpanded() {
    return this.serviceCustomFieldsExpanded || this.historyCustomFieldsExpanded;
  }

  get contractCustomExpandedAria() {
    return this.contractCustomFieldsExpanded ? "true" : "false";
  }

  get hasServiceCustomFields() {
    return (
      filterVisibleCustomFieldDefinitions(
        this.serviceFieldDefinitions,
        undefined,
        this.effectiveSelectedType
      ).length > 0
    );
  }

  get hasHistoryCustomFields() {
    return (
      filterVisibleCustomFieldDefinitions(
        this.historyFieldDefinitions,
        undefined,
        this.effectiveSelectedType
      ).length > 0
    );
  }

  get hasContractCustomFields() {
    return this.hasServiceCustomFields || this.hasHistoryCustomFields;
  }

  /**
   * 契約サービス／履歴の追加項目があるときは常に表示する。
   * 必須項目（申込日など）を備考・商品明細の表示条件に縛ると入力できない。
   */
  get showContractCustomSection() {
    return this.hasContractCustomFields;
  }

  get contractCustomToggleClass() {
    return this.contractCustomFieldsExpanded
      ? "est-panel-toggle est-panel-toggle_active"
      : "est-panel-toggle";
  }

  get contractCustomChevronClass() {
    return this.contractCustomFieldsExpanded
      ? "est-custom-chevron est-custom-chevron_open"
      : "est-custom-chevron";
  }

  get remarksExpanded() {
    return this._wizardData?.remarksExpanded !== false;
  }

  get remarksExpandedAria() {
    return this.remarksExpanded ? "true" : "false";
  }

  get remarksToggleClass() {
    return this.remarksExpanded
      ? "est-panel-toggle est-panel-toggle_active"
      : "est-panel-toggle";
  }

  get remarksChevronClass() {
    return this.remarksExpanded
      ? "est-custom-chevron est-custom-chevron_open"
      : "est-custom-chevron";
  }

  get recurringPeriodExpandedAria() {
    return this.recurringPeriodExpanded ? "true" : "false";
  }

  get recurringPeriodToggleClass() {
    return this.recurringPeriodExpanded
      ? "est-panel-toggle est-panel-toggle_active"
      : "est-panel-toggle";
  }

  get recurringPeriodChevronClass() {
    return this.recurringPeriodExpanded
      ? "est-custom-chevron est-custom-chevron_open"
      : "est-custom-chevron";
  }

  get productLinesExpandedAria() {
    return this.productLinesExpanded ? "true" : "false";
  }

  get productLinesToggleClass() {
    return this.productLinesExpanded
      ? "est-panel-toggle est-panel-toggle_active"
      : "est-panel-toggle";
  }

  get productLinesChevronClass() {
    return this.productLinesExpanded
      ? "est-custom-chevron est-custom-chevron_open"
      : "est-custom-chevron";
  }

  get serviceCustomFieldInputs() {
    return buildCustomFieldInputs(
      this.serviceFieldDefinitions,
      this.contractServiceCustomFields,
      "service",
      false,
      undefined,
      this.effectiveSelectedType
    );
  }

  get historyCustomFieldInputs() {
    return buildCustomFieldInputs(
      this.historyFieldDefinitions,
      this.contractHistoryCustomFields,
      "history",
      false,
      undefined,
      this.effectiveSelectedType
    );
  }

  refreshCustomFieldsFromParentContext() {
    if (!this.itemList.length || this._bootstrapInFlight) {
      return;
    }
    this.commitItemList(
      this.itemList.map((row) => this.withSyncedProductCustomFields(row)),
      { emit: true }
    );
  }

  syncProductCustomFields(customFields, productVisibilityContext) {
    return syncCustomFieldsForVisibility(
      customFields,
      this.productFieldDefinitions,
      productVisibilityContext || {},
      this.effectiveSelectedType,
      this.opportunityDefaultContext
    );
  }

  withSyncedProductCustomFields(row) {
    if (!row || row.isGroupHeader || row.isCustomDetailRow) {
      return row;
    }
    if (isChangeOriginalLine(row)) {
      return {
        ...row,
        customFields: {}
      };
    }
    return {
      ...row,
      customFields: this.syncProductCustomFields(
        row.customFields,
        row.productVisibilityContext || {}
      )
    };
  }

  withCustomDetailRows(rows) {
    if (
      !this.hasProductCustomFields ||
      !this.productCustomFieldsExpanded ||
      !rows ||
      rows.length === 0
    ) {
      return rows;
    }
    const result = [];
    for (const row of rows) {
      result.push(row);
      if (row.isGroupHeader || row.isCustomDetailRow) {
        continue;
      }
      // Change の Original は追加項目 UI を出さない
      if (isChangeOriginalLine(row)) {
        continue;
      }
      const customFieldsReadonly =
        this.orderedCustomFieldsOnly === true ? false : row.isReadonly === true;
      const customFieldInputs = buildCustomFieldInputs(
        this.productFieldDefinitions,
        row.customFields || {},
        row.id,
        customFieldsReadonly,
        row.productVisibilityContext,
        this.effectiveSelectedType
      );
      if (customFieldInputs.length === 0) {
        continue;
      }
      result.push({
        id: `custom-detail-${row.id}`,
        isCustomDetailRow: true,
        isGroupHeader: false,
        parentRowId: row.id,
        isCustomReadonly: customFieldsReadonly,
        customFieldInputs,
        tableRowClass: "est-detail-row",
        changeGroupBoundary: row.changeGroupBoundary || null,
        changeGroupTone: row.changeGroupTone || null
      });
    }
    return this.reapplyChangeGroupBoundaries(result);
  }

  /**
   * 追加項目行を挟んでも Original→Remake（／新商品）の枠が途切れないよう、
   * グループヘッダー直後〜次ヘッダー前の連続行に start/middle/end を付け直す。
   */
  reapplyChangeGroupBoundaries(rows) {
    if (!this.isChangeType || !rows || rows.length === 0) {
      return rows;
    }
    const next = rows.map((row) => ({ ...row }));
    let i = 0;
    while (i < next.length) {
      if (next[i].isGroupHeader) {
        i += 1;
        continue;
      }
      let j = i;
      while (j < next.length && !next[j].isGroupHeader) {
        j += 1;
      }
      const runLen = j - i;
      for (let k = 0; k < runLen; k += 1) {
        const boundary =
          runLen === 1
            ? "end"
            : k === 0
              ? "start"
              : k === runLen - 1
                ? "end"
                : "middle";
        next[i + k] = this.applyChangeGroupBoundaryClass({
          ...next[i + k],
          changeGroupBoundary: boundary,
          changeGroupTone: next[i + k].changeGroupTone || null
        });
      }
      i = j;
    }
    return next;
  }

  applyChangeGroupBoundaryClass(row) {
    if (!row || row.isGroupHeader || !row.changeGroupBoundary) {
      return row;
    }
    const toneSuffix = row.changeGroupTone === "new" ? "_new" : "";
    const boundaryClass =
      row.changeGroupBoundary === "start"
        ? `est-change-group-boundary_start${toneSuffix}`
        : row.changeGroupBoundary === "middle"
          ? `est-change-group-boundary_middle${toneSuffix}`
          : row.changeGroupBoundary === "end"
            ? `est-change-group-boundary_end${toneSuffix}`
            : "";
    if (!boundaryClass) {
      return row;
    }
    const baseClass = (row.tableRowClass || "est-table-row")
      .replace(/\best-change-group-boundary_(start|middle|end)(_new)?\b/g, "")
      .replace(/\s+/g, " ")
      .trim();
    return {
      ...row,
      tableRowClass: `${baseClass} ${boundaryClass}`.trim()
    };
  }

  get isHeaderDatesReady() {
    return isHeaderDatesReady(this.contractStartDate, this.contractEndDate);
  }

  get canEditProducts() {
    if (
      this._bootstrapInFlight ||
      this.isLoadingChangeProducts ||
      this.isLoadingDates
    ) {
      return false;
    }
    if (this.isRenewType) {
      return (
        !this.isLoadingRenewProducts &&
        !this.renewLoadError &&
        this.itemList.length > 0
      );
    }
    // New / Add: 明細を先に入力（ヘッダは継続から自動）
    return true;
  }

  get showHeaderDatePrompt() {
    return false;
  }

  get headerDatePromptMessage() {
    return "";
  }

  /**
   * 請求プレビューに端数ずれが載り得る明細があるとき、ヘッダで案内する。
   * Change の据え置き Original/Remake は対象外。
   */
  get showAmountEntryRoundingAlert() {
    return (
      this.showProductTable &&
      this.itemList.some(
        (row) =>
          resolveInvoicePreviewRoundingDiff(row, this.itemList, {
            isChange: this.isChangeType
          }) != null
      )
    );
  }

  get amountEntryRoundingAlertMessage() {
    return "見積金額と請求再計算（単価×数量を月ごと四捨五入）が異なる明細があります。請求作成時に端数が出ることがあり、受注後の請求プレビューで調整できます。";
  }

  get productTableScrollClass() {
    let scrollClass = "est-table-wrap";
    if (!this.canEditProducts && this.orderedCustomFieldsOnly !== true) {
      scrollClass += " est-table-wrap_disabled";
    }
    if (this.isProductModalOpen) {
      scrollClass += " est-table-wrap_product-picking";
    }
    return scrollClass;
  }

  get isProductModalOpen() {
    return this.productModalRowId != null;
  }

  get showRemarksSection() {
    return (
      this.showProductTable &&
      this.isHeaderDatesReady &&
      this.itemList.length > 0
    );
  }

  get showTotalSummary() {
    return this.showRemarksSection;
  }

  get totalAmount() {
    let sum = 0;
    for (const item of this.itemList) {
      const price = Number(item.unitPrice);
      const amount = Number(item.amount);
      if (Number.isNaN(price) || Number.isNaN(amount)) {
        return Number.NaN;
      }
      if (item.amount != null && Number.isFinite(amount)) {
        sum += amount;
      }
    }
    return sum;
  }

  get formattedTotalAmount() {
    if (!Number.isFinite(this.totalAmount)) {
      return "—";
    }
    return new Intl.NumberFormat("ja-JP", {
      style: "currency",
      currency: "JPY"
    }).format(this.totalAmount);
  }

  /**
   * 表示％。CS 未作成は 10%。既存 CS は TaxPercent（未入力は 0%。TaxCalculationUtil と同じ）。
   */
  get resolvedTaxPercent() {
    if (!this.contractServiceId) {
      return DEFAULT_TAX_PERCENT_WHEN_NO_SERVICE;
    }
    const wired = this._wiredContractServiceTax;
    if (!wired || wired.data == null) {
      return null;
    }
    const raw = getFieldValue(wired.data, CS_TAX_PERCENT_FIELD);
    if (raw == null || raw === "") {
      return 0;
    }
    const numeric = Number(raw);
    if (!Number.isFinite(numeric)) {
      return 0;
    }
    // Apex と同様: 0<x<1 は小数表記（0.1＝10%）、それ以外は表示％
    if (numeric > 0 && numeric < 1) {
      return numeric * 100;
    }
    return numeric;
  }

  get totalTax() {
    const excl = this.totalAmount;
    const taxPercent = this.resolvedTaxPercent;
    if (
      !Number.isFinite(excl) ||
      taxPercent == null ||
      !Number.isFinite(taxPercent)
    ) {
      return Number.NaN;
    }
    // Apex RoundingMode.DOWN（0 方向）と同じ
    return Math.trunc((excl * taxPercent) / 100);
  }

  get totalAmountInclTax() {
    const excl = this.totalAmount;
    const tax = this.totalTax;
    if (!Number.isFinite(excl) || !Number.isFinite(tax)) {
      return Number.NaN;
    }
    return excl + tax;
  }

  get formattedTotalTax() {
    if (!Number.isFinite(this.totalTax)) {
      return "—";
    }
    return new Intl.NumberFormat("ja-JP", {
      style: "currency",
      currency: "JPY"
    }).format(this.totalTax);
  }

  get formattedTotalAmountInclTax() {
    if (!Number.isFinite(this.totalAmountInclTax)) {
      return "—";
    }
    return new Intl.NumberFormat("ja-JP", {
      style: "currency",
      currency: "JPY"
    }).format(this.totalAmountInclTax);
  }

  get totalLineCount() {
    return this.itemList.length;
  }

  getDefaultDates() {
    return {
      startDate: this.contractStartDate || "",
      endDate: this.contractEndDate || ""
    };
  }

  addOneDay(isoDate) {
    return addDaysToIsoDate(isoDate, 1);
  }

  addOneYearEndDate(isoStartDate) {
    return endDateForMonthlyCycles(isoStartDate, 12);
  }

  addOneMonthEndDate(isoStartDate) {
    return endDateForMonthlyCycles(isoStartDate, 1);
  }

  addYearsMinusOneDayEndDate(isoStartDate, years) {
    const n = Number(years);
    if (!Number.isFinite(n)) {
      return "";
    }
    return endDateForMonthlyCycles(isoStartDate, n * 12);
  }

  addMonthsMinusOneDayEndDate(isoStartDate, months) {
    return endDateForMonthlyCycles(isoStartDate, months);
  }

  /** ヘッダー開始日起点で終了日を月次境界へ切り捨て寄せ。 */
  alignContractEndDate(endDate, startDate = this.contractStartDate) {
    if (!endDate || !isValidIsoDate(endDate)) {
      return endDate || "";
    }
    if (!startDate || !isValidIsoDate(startDate)) {
      return endDate;
    }
    return alignMonthlyEndDate(startDate, endDate) || endDate;
  }

  /** 明細開始日起点で終了日を月次境界へ切り捨て寄せ。 */
  alignLineEndDate(startDate, endDate) {
    if (!endDate || !isValidIsoDate(endDate)) {
      return endDate || "";
    }
    if (!startDate || !isValidIsoDate(startDate)) {
      return endDate;
    }
    return alignMonthlyEndDate(startDate, endDate) || endDate;
  }

  get showContractEndDateShortcuts() {
    return (
      this.orderedCustomFieldsOnly !== true &&
      !this.isEndDateReadonly &&
      !!(this.contractEndDate || this.contractStartDate)
    );
  }

  ensureCancelDates() {
    if (!this.isCancelType) {
      return;
    }
    const cancelDate = this.contractStartDate || this.contractEndDate || "";
    if (cancelDate) {
      this.applyBusinessFields({
        contractStartDate: cancelDate,
        contractEndDate: cancelDate
      });
    }
  }

  ensureRenewEndDate() {
    if (this.isRenewType && this.contractStartDate && !this.contractEndDate) {
      this.applyBusinessFields({
        contractEndDate: this.addOneYearEndDate(this.contractStartDate)
      });
    }
  }

  async initContractDates() {
    const savedStart = resolveSavedContractStartDate(this._wizardData);
    const savedEnd = resolveSavedContractEndDate(this._wizardData);

    if (this.orderedCustomFieldsOnly === true) {
      this.isStartDateReadonly = true;
      this.isEndDateReadonly = true;
      this.applyBusinessFields({
        contractStartDate: savedStart,
        contractEndDate: savedEnd
      });
      return;
    }

    if (this.isNewType) {
      // 継続課金の契約期間は明細から自動（編集不可）
      this.isStartDateReadonly = true;
      this.isEndDateReadonly = true;
      this.applyBusinessFields({
        contractStartDate: savedStart,
        contractEndDate: savedEnd
      });
      return;
    }

    if (this.isAddType) {
      this.isStartDateReadonly = true;
      this.isEndDateReadonly = true;
      this.applyBusinessFields({
        contractStartDate: "",
        contractEndDate: "",
        contractEffectiveDate: ""
      });
      return;
    }

    if (this.isRenewType) {
      // 継続課金の契約期間は明細から自動（編集不可）
      this.isStartDateReadonly = true;
      this.isEndDateReadonly = true;

      if (savedStart && savedEnd) {
        this.applyBusinessFields({
          contractStartDate: savedStart,
          contractEndDate: savedEnd
        });
        return;
      }

      await this.loadHistoryDates();

      if (savedStart) {
        this.applyBusinessFields({ contractStartDate: savedStart });
      }
      this.ensureRenewEndDate();
      return;
    }

    if (this.isCancelType) {
      this.isStartDateReadonly = true;
      this.isEndDateReadonly = true;

      if (savedStart && savedEnd) {
        this.applyBusinessFields({
          contractStartDate: savedStart,
          contractEndDate: savedEnd
        });
        return;
      }

      await this.loadHistoryDates();
      this.ensureCancelDates();
      return;
    }

    if (this.isChangeType) {
      // 継続課金の契約期間は明細から自動（編集不可）
      this.isStartDateReadonly = true;
      this.isEndDateReadonly = true;
    }

    if (savedStart || savedEnd) {
      this.applyBusinessFields({
        contractStartDate: savedStart,
        contractEndDate: savedEnd
      });
      return;
    }

    await this.loadHistoryDates();
  }

  async loadHistoryDates() {
    const contractHistoryId =
      this._wizardData && this._wizardData.contractHistoryId;
    if (!contractHistoryId) {
      return;
    }

    this.isLoadingDates = true;
    this.notifyStepReadyChange();
    try {
      const info = await getContractHistoryInfo({
        contractHistoryId
      });
      if (!info) {
        return;
      }

      if (this.isChangeType) {
        this.applyBusinessFields({
          previousTermStartDate: info.termStartDate || "",
          previousTermEndDate: info.termEndDate || "",
          contractStartDate: info.termStartDate || "",
          contractEndDate: info.termEndDate || ""
        });
      } else if (this.isCancelType) {
        const cancelDate = this.addOneDay(info.termEndDate);
        this.applyBusinessFields({
          previousTermEndDate: info.termEndDate || "",
          fixedEffectiveDate: cancelDate,
          contractStartDate: cancelDate,
          contractEndDate: cancelDate
        });
      } else if (this.isRenewType) {
        const startDate = this.addOneDay(info.termEndDate);
        this.applyBusinessFields({
          previousTermEndDate: info.termEndDate || "",
          fixedEffectiveDate: startDate,
          contractStartDate: startDate,
          contractEndDate: this.addOneYearEndDate(startDate)
        });
      }
      this.syncFixedEffectiveDate();
    } catch (error) {
      const message =
        error.body && error.body.message
          ? error.body.message
          : "契約履歴の日付取得に失敗しました。";
      if (this.isRenewType) {
        this.renewLoadError = message;
      } else if (this.isCancelType) {
        this.cancelLoadError = message;
      } else {
        this.changeLoadError = message;
      }
    } finally {
      this.isLoadingDates = false;
      this.notifyStepReadyChange();
    }
  }

  readDateInputValue(event) {
    const detailValue =
      event && event.detail && event.detail.value !== undefined
        ? event.detail.value
        : undefined;
    const targetValue =
      event && event.target && event.target.value !== undefined
        ? event.target.value
        : "";
    return normalizeDateInput(
      detailValue !== undefined && detailValue !== null ? detailValue : targetValue
    );
  }

  handleContractStartDateChange(event) {
    const contractStartDate = this.readDateInputValue(event);
    const fields = { contractStartDate };
    // New/Renew: 終了が空／不正のときだけ 12 サイクル終了日を埋める（手入力終了は上書きしない）
    if (
      contractStartDate &&
      (this.isRenewType || this.isNewType) &&
      isValidIsoDate(contractStartDate) &&
      (!this.contractEndDate || !isValidIsoDate(this.contractEndDate))
    ) {
      fields.contractEndDate = this.addOneYearEndDate(contractStartDate);
    }
    // New: 有効日＝期間開始。親未反映の this.contractStartDate に依存しないよう同梱する
    if (this.isNewType) {
      fields.contractEffectiveDate = contractStartDate || "";
    }
    this.applyBusinessFields(fields);
    if (!this.isNewType) {
      this.syncFixedEffectiveDate(contractStartDate);
    }
    this.ensureNewInitialRow();
  }

  handleContractEndDateChange(event) {
    const raw = this.readDateInputValue(event);
    this.applyBusinessFields({
      contractEndDate: this.alignContractEndDate(raw)
    });
    this.ensureNewInitialRow();
  }

  handleEffectiveDateChange(event) {
    this.applyBusinessFields({
      contractEffectiveDate: this.readDateInputValue(event)
    });
  }

  handleFillContractEndOneYear() {
    this.adjustContractEndDate({ years: 1 });
  }

  handleFillContractEndOneMonth() {
    this.adjustContractEndDate({ months: 1 });
  }

  handleFillContractEndMinusOneYear() {
    this.adjustContractEndDate({ years: -1 });
  }

  handleFillContractEndMinusOneMonth() {
    this.adjustContractEndDate({ months: -1 });
  }

  adjustContractEndDate({ years = 0, months = 0 }) {
    const start = this.contractStartDate;
    if (!start || !isValidIsoDate(start)) {
      return;
    }
    const delta = Number(years || 0) * 12 + Number(months || 0);
    if (!delta) {
      return;
    }
    const next = adjustMonthlyEndByCycles(
      start,
      this.contractEndDate || "",
      delta
    );
    if (!next) {
      return;
    }
    this.applyBusinessFields({ contractEndDate: next });
    this.ensureNewInitialRow();
  }

  resolveLineStartAdjustBase(row) {
    return (
      row.startDate ||
      row.endDate ||
      this.contractStartDate ||
      this.contractEndDate ||
      ""
    );
  }

  resolveLineEndAdjustBase(row) {
    return (
      row.endDate ||
      row.startDate ||
      this.contractEndDate ||
      this.contractStartDate ||
      ""
    );
  }

  adjustLineStartDate(rowId, { years = 0, months = 0 }) {
    const row = this.itemList.find((item) => item.id === rowId);
    if (!row) {
      return;
    }
    const base = this.resolveLineStartAdjustBase(row);
    if (!base) {
      return;
    }
    let next = base;
    if (years) {
      next = addYearsToIsoDate(next, years);
    }
    if (months) {
      next = addMonthsToIsoDate(next, months);
    }
    if (!next) {
      return;
    }
    this.updateRow(rowId, { startDate: next });
  }

  adjustLineEndDate(rowId, { years = 0, months = 0 }) {
    const row = this.itemList.find((item) => item.id === rowId);
    if (!row) {
      return;
    }
    const start =
      row.startDate ||
      this.contractStartDate ||
      this.resolveLineEndAdjustBase(row);
    if (!start || !isValidIsoDate(start)) {
      return;
    }
    const delta = Number(years || 0) * 12 + Number(months || 0);
    if (!delta) {
      return;
    }
    const next = adjustMonthlyEndByCycles(start, row.endDate || "", delta);
    if (!next) {
      return;
    }
    this.updateRow(rowId, { endDate: next });
  }

  ensureNewInitialRow() {
    if (!this.isNewType) {
      return;
    }

    // New はヘッダ期間が明細から後で決まるため、日付未設定でも空行1つを出す
    // 商品選択済みの行がある場合は、ユーザー入力を尊重して自動調整しない
    const hasFilledProduct = this.itemList.some((row) => row.productId);
    if (hasFilledProduct) {
      return;
    }

    if (this.itemList.length === 0) {
      this.addRow(false);
      return;
    }

    // 空行だけが複数ある場合は先頭1行に畳む（再ブートストラップ二重追加の救済）
    if (this.itemList.length > 1) {
      this.commitItemList([this.itemList[0]], {
        emit: !this._bootstrapInFlight
      });
    }
  }

  initHistoryMetaDates() {
    const savedEffective =
      (this._wizardData && this._wizardData.contractEffectiveDate) || "";

    const fields = {};
    if (this._wizardData) {
      if (this._wizardData.previousTermStartDate) {
        fields.previousTermStartDate = this._wizardData.previousTermStartDate;
      }
      if (this._wizardData.previousTermEndDate) {
        fields.previousTermEndDate = this._wizardData.previousTermEndDate;
      }
    }

    if (savedEffective) {
      fields.contractEffectiveDate = savedEffective;
    } else if (this.isChangeType || this.isRenewType || this.isCancelType) {
      fields.contractEffectiveDate = this.contractStartDate || "";
    }

    this.applyBusinessFields(fields);
    this.syncFixedEffectiveDate();
  }

  /**
   * @param {string} [startDateOverride] 親未反映の期間開始（入力直後）を渡す
   */
  syncFixedEffectiveDate(startDateOverride) {
    const startDate =
      startDateOverride !== undefined
        ? startDateOverride || ""
        : this.contractStartDate || "";

    if (this.isNewType) {
      this.applyBusinessFields({ contractEffectiveDate: startDate });
      return;
    }
    if (this.isChangeType) {
      this.syncChangeEffectiveDateFromProducts(startDate);
      return;
    }
    if (this.contractEffectiveDate) {
      return;
    }
    if ((this.isRenewType || this.isCancelType) && this.fixedEffectiveDate) {
      this.applyBusinessFields({
        contractEffectiveDate: this.fixedEffectiveDate
      });
    }
  }

  syncChangeEffectiveDateFromProducts(startDateOverride) {
    if (!this.isChangeType) {
      return;
    }
    // 継続課金イベントの最早日のみ。一回課金の追加・変更は切替日に使わない。
    const earliest = getEarliestChangeBillingThresholdDate(
      this.itemList,
      startDateOverride !== undefined
        ? startDateOverride || ""
        : this.contractStartDate || ""
    );
    this.applyBusinessFields({
      contractEffectiveDate: earliest || ""
    });
  }

  /**
   * New / Renew / Change: 継続課金明細の min〜max から継続課金の契約期間を算出する。
   * 親 wizardData への反映は呼び出し側の emit に載せること
   * （先に applyBusinessFields すると直後の products emit が古い日付で上書きする）。
   * Change の切替日は別ロジック（最早課金イベント）のためここでは載せない。
   */
  computeHeaderDatesFromRecurringProducts() {
    if (
      !this.isNewType &&
      !this.isRenewType &&
      !this.isChangeType
    ) {
      return null;
    }
    let minStart = "";
    let maxEnd = "";
    for (const row of this.itemList || []) {
      if (
        !row ||
        !row.productId ||
        !(Number(row.quantity) > 0) ||
        !isRecurringLine(row)
      ) {
        continue;
      }
      if (row.startDate && (!minStart || row.startDate < minStart)) {
        minStart = row.startDate;
      }
      if (row.endDate && (!maxEnd || row.endDate > maxEnd)) {
        maxEnd = row.endDate;
      }
    }
    if (!minStart && !maxEnd) {
      // New のみクリア。Renew/Change は読込途中でヘッダを消さない。
      if (this.isNewType) {
        return {
          contractStartDate: "",
          contractEndDate: "",
          contractEffectiveDate: ""
        };
      }
      return null;
    }
    const contractStartDate = minStart;
    const contractEndDate = this.alignContractEndDate(maxEnd, minStart);
    if (this.isChangeType) {
      return {
        contractStartDate,
        contractEndDate
      };
    }
    return {
      contractStartDate,
      contractEndDate,
      contractEffectiveDate: contractStartDate
    };
  }

  handleContractHistoryNameChange(event) {
    this.applyBusinessFields({
      contractHistoryName: event.target.value
    });
  }

  buildWizardIdentityKey() {
    const data = this._wizardData;
    if (!data) {
      return "";
    }
    return [
      data.selectedType || "",
      data.contractServiceId || "",
      data.contractHistoryId || "",
      this._loadingContractHistory ? "loading" : "ready"
    ].join("|");
  }

  async bootstrapFromWizardData() {
    if (this._bootstrapInFlight) {
      this._bootstrapQueued = true;
      return;
    }

    const generation = ++this._bootstrapGeneration;
    this._bootstrapInFlight = true;
    this._bootstrapQueued = false;
    this._lastEmittedProductsFingerprint = "";
    this._lastSyncedProductsFingerprint = "";
    this.notifyStepReadyChange();

    try {
      // 契約履歴名は基本情報（modal2）が唯一の編集元。ここでは触らない。

      await this.initContractDates();
      if (!this.isBootstrapGenerationCurrent(generation)) {
        return;
      }
      this.initHistoryMetaDates();

      if (this._wizardData) {
        this.applyRemarkPresetFromWizardData();
      }

      const type = this.effectiveSelectedType;
      if (this.hasPresetSelectedProducts()) {
        this.applyPresetSelectedProducts();
        // 親に残った空行2件などが復元されても New は1行に揃える
        this.ensureNewInitialRow();
      } else if (type === "Renew") {
        await this.loadRenewProducts(generation);
      } else if (type === "New") {
        this.ensureNewInitialRow();
      } else if (type === "Change") {
        await this.loadChangeProducts(generation);
      } else if (type === "Cancel") {
        this.commitItemList([], { emit: false });
        this.initCancelEligibility();
      }
    } finally {
      if (this.isBootstrapGenerationCurrent(generation)) {
        this._bootstrapInFlight = false;
        this.notifyStepReadyChange();
      } else {
        this._bootstrapInFlight = false;
      }
    }

    if (!this.isBootstrapGenerationCurrent(generation)) {
      return;
    }

    // ブートストラップ中に emit:false で積んだ明細を親へ確定する
    this.emitProductsFromItemList();

    if (this._bootstrapQueued) {
      this._bootstrapQueued = false;
      await this.bootstrapFromWizardData();
    }
  }

  connectedCallback() {
    this._isConnected = true;
    this._wizardIdentityKey = this.buildWizardIdentityKey();
    this.bootstrapFromWizardData();
    this.emitDefaultContractCustomFieldsIfNeeded();
    // マウント時は請求設定・税率の wire／LDS キャッシュを捨てて最新化
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    Promise.resolve().then(() => {
      this.refreshReferenceWires();
    });
  }

  /**
   * 詳細パネル表示用の参照データ（請求設定・税率）を最新化する。
   */
  @api
  refreshReferenceWires() {
    const jobs = [];
    if (this._wiredInvoiceSettingOptions) {
      jobs.push(refreshApex(this._wiredInvoiceSettingOptions));
    }
    if (this._wiredDefaultInvoiceSettingLabel) {
      jobs.push(refreshApex(this._wiredDefaultInvoiceSettingLabel));
    }
    if (this.contractServiceId) {
      getRecordNotifyChange([{ recordId: this.contractServiceId }]);
    }
    return Promise.all(jobs);
  }

  disconnectedCallback() {
    this._isConnected = false;
    this._bootstrapGeneration += 1;
    this._bootstrapInFlight = false;
    this._bootstrapQueued = false;
    this._wizardIdentityKey = "";
    if (this._fitProductNamesRaf != null) {
      cancelAnimationFrame(this._fitProductNamesRaf);
      this._fitProductNamesRaf = null;
    }
    if (this._resizeObserver) {
      this._resizeObserver.disconnect();
      this._resizeObserver = null;
    }
    this.teardownProductModalA11y();
    this.rejectAllPendingConfirms();
    // アンマウント時は親の loadingStep3 を必ず解除（種別変更で DOM 破棄されても次へ／保存が死なないようにする）
    this._lastNotifiedStepReady = null;
    this.dispatchEvent(
      new CustomEvent("loadingchange", {
        bubbles: true,
        composed: true,
        detail: { loading: false }
      })
    );
  }

  hasPresetSelectedProducts() {
    return (
      this._wizardData &&
      Array.isArray(this._wizardData.selectedProducts) &&
      this._wizardData.selectedProducts.length > 0
    );
  }

  applyPresetSelectedProducts() {
    const defaultDates = this.getDefaultDates();
    const rows = this._wizardData.selectedProducts.map((item) => {
      return this.applyAmount(
        restoreAmountEntryFromSavedAmount(
          this.withSyncedProductCustomFields(
            this.normalizeRow({
              ...item,
              id: item.id || createRowId(),
              isReadonly:
                item.isReadonly === true ||
                item.recordType === PRODUCT_TYPE_ORIGINAL,
              startDate: item.startDate || defaultDates.startDate,
              endDate: item.endDate || defaultDates.endDate
            })
          )
        )
      );
    });
    const changeSourceProducts = this.isChangeType
      ? (() => {
          const presetSources =
            this._wizardData &&
            Array.isArray(this._wizardData.changeSourceProducts)
              ? this._wizardData.changeSourceProducts
              : [];
          return presetSources.length > 0
            ? presetSources.map((source) => ({ ...source }))
            : this.buildChangeSourceProductsFromOriginals(rows);
        })()
      : undefined;
    this.commitItemList(rows, {
      changeSourceProducts,
      emit: !this._bootstrapInFlight
    });
  }

  buildChangeSourceProductsFromOriginals(rows) {
    return (rows || [])
      .filter((row) => isChangeOriginalLine(row))
      .map((row) => ({
        contractProductId: row.sourceContractProductId,
        productId: row.productId,
        quantity: row.quantity,
        unitPrice: row.unitPrice,
        startDate: row.startDate || "",
        endDate: row.endDate || "",
        invoiceType: row.invoiceType || ""
      }))
      .filter((source) => source.contractProductId);
  }

  buildChangeSourceProductsFromLoaded(products) {
    return (products || []).map((product) => ({
      contractProductId: product.contractProductId,
      productId: product.productId,
      quantity: product.quantity,
      unitPrice: product.unitPrice,
      startDate: product.startDate || "",
      endDate: product.endDate || "",
      invoiceType: product.invoiceType || ""
    }));
  }

  initCancelEligibility() {
    if (!this.isCancelType) {
      return;
    }
    if (this._wizardData && this._wizardData.renewEligible === false) {
      this.cancelLoadError =
        "前回Versionの期間終了日と一致する継続課金商品がありません。Cancelできません。Newで作成してください。";
    }
  }

  async loadRenewProducts(generation = this._bootstrapGeneration) {
    const contractServiceId =
      this._wizardData && this._wizardData.contractServiceId;
    if (!contractServiceId) {
      this.renewLoadError = "";
      if (!this._loadingContractHistory) {
        this.renewLoadError =
          "契約サービスが設定されていません。基本情報に戻って契約サービスを選択してください。";
        this.addRow(false);
      } else {
        this.commitItemList([], { emit: false });
      }
      return;
    }

    this.isLoadingRenewProducts = true;
    this.notifyStepReadyChange();
    this.renewLoadError = "";
    try {
      const products = await getRenewContractProducts({
        contractServiceId
      });
      const currentServiceId =
        this._wizardData && this._wizardData.contractServiceId;
      if (
        !this.isBootstrapGenerationCurrent(generation) ||
        currentServiceId !== contractServiceId
      ) {
        return;
      }
      let nextList = this.buildRenewItemList(products || []);
      if (nextList.length === 0) {
        this.renewLoadError =
          "前回Versionの期間終了日と一致する継続課金商品がありません。Renewできません。Newで作成してください。";
        nextList = [];
      } else {
        this.renewLoadError = "";
      }
      this.commitItemList(nextList, { emit: false });
    } catch (error) {
      const currentServiceId =
        this._wizardData && this._wizardData.contractServiceId;
      if (
        !this.isBootstrapGenerationCurrent(generation) ||
        currentServiceId !== contractServiceId
      ) {
        return;
      }
      this.renewLoadError =
        error.body && error.body.message
          ? error.body.message
          : "見積商品の取得に失敗しました。";
      this.commitItemList([], { emit: false });
    } finally {
      this.isLoadingRenewProducts = false;
      if (this.isBootstrapGenerationCurrent(generation)) {
        this.notifyStepReadyChange();
      }
    }
  }

  buildRenewItemList(products) {
    const { startDate, endDate } = this.getDefaultDates();
    const items = [];
    products.forEach((product) => {
      const unitPrice = product.unitPrice != null ? product.unitPrice : 0;
      const quantity = product.quantity != null ? product.quantity : 1;
      items.push(
        this.applyAmount({
          id: createRowId(),
          productId: product.productId,
          productName: product.productName || "",
          unitName: product.unitName || "",
          unit:
            product.unit ||
            buildDisplayUnit(
              product.unitName,
              product.billingType || BILLING_TYPE_RECURRING,
              product.billingCycle
            ),
          billingType: product.billingType || BILLING_TYPE_RECURRING,
          billingCycle:
            product.billingType === BILLING_TYPE_RECURRING
              ? MONTHLY_BILLING_CYCLE
              : product.billingCycle || "",
          unitPrice,
          quantity,
          startDate,
          endDate,
          invoiceType: product.invoiceType || this.resolvedDefaultInvoiceType,
          recordType: PRODUCT_TYPE_RENEW,
          typeLabel: "Renew",
          isReadonly: false,
          rowClass: "",
          customFields: { ...(product.customFields || {}) },
          productVisibilityContext: {
            ...(product.productVisibilityContext || {})
          }
        })
      );
    });
    return this.decorateAllRows(items);
  }

  async loadChangeProducts(generation = this._bootstrapGeneration) {
    const contractHistoryId =
      this._wizardData && this._wizardData.contractHistoryId;
    if (!contractHistoryId) {
      // 契約サービス切替直後は履歴読込中のため、空履歴でエラーにしない。
      this.changeLoadError = "";
      this.commitItemList([], {
        changeSourceProducts: [],
        emit: false
      });
      if (!this._loadingContractHistory) {
        this.changeLoadError =
          "契約履歴が設定されていません。基本情報に戻って契約サービスを選択してください。";
      }
      return;
    }

    if (this._wizardData && this._wizardData.renewEligible === false) {
      this.commitItemList([], {
        changeSourceProducts: [],
        emit: false
      });
      this.changeLoadError =
        "前回Versionの期間終了日と一致する継続課金商品がありません。Changeできません。Newで作成してください。";
      return;
    }

    this.isLoadingChangeProducts = true;
    this.notifyStepReadyChange();
    this.changeLoadError = "";
    try {
      const products = await getRecurringContractProducts({
        contractHistoryId
      });
      const currentHistoryId =
        this._wizardData && this._wizardData.contractHistoryId;
      if (
        !this.isBootstrapGenerationCurrent(generation) ||
        currentHistoryId !== contractHistoryId
      ) {
        return;
      }
      const changeSourceProducts = this.buildChangeSourceProductsFromLoaded(
        products || []
      );
      const nextList = this.buildChangeItemList(products || []);
      if (nextList.length === 0) {
        this.commitItemList([], {
          changeSourceProducts: [],
          emit: false
        });
        this.changeLoadError =
          "前回Versionの期間終了日と一致する継続課金商品がありません。Changeできません。Newで作成してください。";
      } else {
        this.commitItemList(nextList, {
          changeSourceProducts,
          emit: false
        });
      }
    } catch (error) {
      const currentHistoryId =
        this._wizardData && this._wizardData.contractHistoryId;
      if (
        !this.isBootstrapGenerationCurrent(generation) ||
        currentHistoryId !== contractHistoryId
      ) {
        return;
      }
      this.changeLoadError =
        error.body && error.body.message
          ? error.body.message
          : "見積商品の取得に失敗しました。";
      this.commitItemList([], {
        changeSourceProducts: [],
        emit: false
      });
    } finally {
      this.isLoadingChangeProducts = false;
      if (this.isBootstrapGenerationCurrent(generation)) {
        this.notifyStepReadyChange();
      }
    }
  }

  buildChangeItemList(products) {
    const items = [];
    products.forEach((product, index) => {
      const pairId = `pair-${index + 1}`;
      const unitPrice = product.unitPrice != null ? product.unitPrice : 0;
      const positiveQuantity = product.quantity != null ? product.quantity : 1;
      const baseRow = {
        productId: product.productId,
        productName: product.productName || "",
        unitName: product.unitName || "",
        unit:
          product.unit ||
          buildDisplayUnit(
            product.unitName,
            product.billingType || BILLING_TYPE_RECURRING,
            product.billingCycle
          ),
        billingType: product.billingType || BILLING_TYPE_RECURRING,
        billingCycle:
          product.billingType === BILLING_TYPE_RECURRING
            ? MONTHLY_BILLING_CYCLE
            : product.billingCycle || "",
        unitPrice,
        quantity: positiveQuantity,
        startDate: product.startDate || "",
        endDate: product.endDate || "",
        invoiceType: product.invoiceType || this.resolvedDefaultInvoiceType,
        sourceContractProductId: product.contractProductId,
        pairId,
        productVisibilityContext: {
          ...(product.productVisibilityContext || {})
        }
      };

      // 前回 Amount の符号を保持（値引きの負金額を Math.abs で壊さない）
      const pairAmounts = resolveChangePairAmountsFromSource(product.amount);
      const originalAmount = pairAmounts.originalAmount;
      const remakeAmount = pairAmounts.remakeAmount;

      items.push(
        this.applyAmount(
          restoreAmountEntryFromSavedAmount({
            ...baseRow,
            id: createRowId(),
            amount: originalAmount,
            recordType: PRODUCT_TYPE_ORIGINAL,
            typeLabel: "Original",
            isReadonly: true,
            rowClass: "est-row-readonly",
            // Original は処理用打消し行。ウィザード追加項目は持たない
            customFields: {}
          })
        )
      );

      items.push(
        this.applyAmount(
          restoreAmountEntryFromSavedAmount({
            ...baseRow,
            id: createRowId(),
            amount: remakeAmount,
            recordType: PRODUCT_TYPE_REMAKE,
            typeLabel: "Remake",
            isReadonly: false,
            isDuplicate: false,
            rowClass: "",
            customFields: { ...(product.customFields || {}) }
          })
        )
      );
    });
    return this.decorateAllRows(items);
  }

  decorateRow(row, rowIndex = -1, remakeCountByPairId = null, products = null) {
    const rowClass = row.rowClass || "";
    const billingType = row.billingType || "";
    const invoiceType = this.resolveRowInvoiceType(
      row.invoiceType,
      billingType
    );
    const invoiceTypeOptions = this.buildInvoiceTypeOptions(
      invoiceType,
      billingType
    );
    const canCopyDatesFromAbove =
      this.orderedCustomFieldsOnly !== true && !row.isReadonly && rowIndex > 0;
    const canDuplicate = canDuplicateProductLine(row, {
      orderedCustomFieldsOnly: this.orderedCustomFieldsOnly === true,
      wizardType: this.effectiveSelectedType
    });
    const remakeCountForPair =
      remakeCountByPairId && row.pairId
        ? remakeCountByPairId.get(row.pairId) || 0
        : 0;
    const canDelete =
      this.orderedCustomFieldsOnly !== true &&
      (this.isNewType ||
        this.isRenewType ||
        (this.isChangeType &&
          isChangeRemakeLine(row) &&
          remakeCountForPair > 1) ||
        (this.isChangeType && isChangeContinuationLine(row)));
    const typeBadge = resolveProductTypeBadge(row.recordType, row.typeLabel);
    const boundaryClass =
      row.changeGroupBoundary === "start"
        ? "est-change-group-boundary_start"
        : row.changeGroupBoundary === "middle"
          ? "est-change-group-boundary_middle"
          : row.changeGroupBoundary === "end"
            ? "est-change-group-boundary_end"
            : "";
    const forceReadonly =
      this.orderedCustomFieldsOnly === true || row.isReadonly === true;
    const invoiceAnchor = resolveInvoiceAnchorFields(
      row,
      this.effectiveSelectedType,
      this.contractEffectiveDate,
      { products }
    );
    return {
      ...row,
      ...typeBadge,
      rowIndex,
      invoiceType,
      invoiceTypeOptions,
      isInvoiceTypeDisabled:
        forceReadonly || !billingType || invoiceTypeOptions.length === 0,
      canCopyDatesFromAbove,
      gridRowClass: `est-line ${rowClass}`.trim(),
      tableRowClass: `est-table-row ${rowClass} ${boundaryClass}`.trim(),
      isReadonly: forceReadonly,
      isEditable: !forceReadonly,
      // Remake / 引継ぎ Renew は Product2 差し替え不可（条件・期間編集と削除は可）
      isProductLocked:
        forceReadonly || isChangeRemakeLine(row) || isRenewProductLine(row),
      canDuplicate,
      canDelete,
      displayUnitName: resolveDisplayUnit(
        row.unit,
        row.unitName,
        billingType,
        row.billingCycle
      ),
      showBillingType: !!billingType,
      displayBillingType: billingType,
      // New: 通常は読取表示。マスタが継続のときだけリンクで一回へ（／戻す）
      ...this.buildBillingTypeFlipView(row, billingType, forceReadonly),
      showPriceCycle: billingType === BILLING_TYPE_RECURRING,
      priceCycleLabel: "/ month",
      showPriceMeta: billingType === BILLING_TYPE_RECURRING,
      showQuantityUnit: !!resolveDisplayUnit(
        row.unit,
        row.unitName,
        billingType,
        row.billingCycle
      ),
      cycleCountDisplay: this.resolveCycleCountDisplay(row),
      displayUnitPrice: Number.isNaN(Number(row.unitPrice))
        ? "NaN"
        : formatCurrencyNumber(row.unitPrice),
      displayAmount: formatAmountYen(row.amount),
      isUnitPriceLocked: !forceReadonly && row.amountEntryMode === true,
      isUnitPriceNan: Number.isNaN(Number(row.unitPrice)),
      canEditAmount:
        !forceReadonly &&
        row.amountEntryMode === true &&
        row.amountInvalid !== true,
      showAmountEntryButton:
        !forceReadonly &&
        row.amountEntryMode !== true &&
        row.amountInvalid !== true,
      showUnitPriceUnlock: !forceReadonly && row.amountEntryMode === true,
      ...this.resolveAmountEntryRoundingDisplay(row, products),
      displayInvoiceAnchor: invoiceAnchor.displayValue,
      showInvoiceAnchor: invoiceAnchor.showInvoiceAnchor,
      invoiceAnchorTitle: INVOICE_ANCHOR_DISPLAY_TITLE,
      customFields: { ...(row.customFields || {}) },
      productVisibilityContext: {
        ...(row.productVisibilityContext || {})
      },
      showCustomFieldsToggle: false
    };
  }

  resolveAmountEntryRoundingDisplay(row, products = null) {
    const productRows = products || this.itemList;
    const diff = resolveInvoicePreviewRoundingDiff(row, productRows, {
      isChange: this.isChangeType
    });
    if (!diff) {
      return {
        showAmountEntryRoundingDiff: false,
        amountEntryBillingTotalLabel: "",
        amountEntryRoundingDiffLabel: "",
        amountEntryRoundingTitle: ""
      };
    }
    const sign = diff.delta > 0 ? "+" : "";
    return {
      showAmountEntryRoundingDiff: true,
      amountEntryBillingTotalLabel: formatAmountYen(diff.billingTotal),
      amountEntryRoundingDiffLabel: `${sign}${formatAmountYen(diff.delta)}`,
      amountEntryRoundingTitle:
        "見積金額と請求再計算（単価×数量を月ごと四捨五入）が異なります。請求作成時に端数が出ることがあり、請求プレビューで調整できます。"
    };
  }

  resolveCycleCountDisplay(row) {
    const billingType = row && row.billingType ? row.billingType : "";
    if (billingType !== BILLING_TYPE_RECURRING) {
      return "-";
    }
    if (!row.startDate || !row.endDate) {
      return "-";
    }
    const cycles = countBillingCycles(row.startDate, row.endDate);
    if (cycles == null || cycles < 1) {
      return "—";
    }
    return `${cycles} month`;
  }

  decorateAllRows(items) {
    const list = items || [];
    const remakeCountByPairId = new Map();
    if (this.isChangeType) {
      for (const item of list) {
        if (isChangeRemakeLine(item) && item.pairId) {
          remakeCountByPairId.set(
            item.pairId,
            (remakeCountByPairId.get(item.pairId) || 0) + 1
          );
        }
      }
    }
    const decorated = list.map((item, index) =>
      this.decorateRow(item, index, remakeCountByPairId, list)
    );
    return this.applyLineNumbers(decorated);
  }

  applyLineNumbers(items) {
    let counter = 0;
    return items.map((item) => {
      if (
        !item ||
        item.isGroupHeader ||
        item.isCustomDetailRow ||
        item.isSectionHeader
      ) {
        return {
          ...item,
          showLineNumber: false,
          lineNumberLabel: ""
        };
      }
      counter += 1;
      return {
        ...item,
        showLineNumber: true,
        lineNumberLabel: String(counter)
      };
    });
  }

  handleAddRow() {
    if (!this.canEditProducts || this.orderedCustomFieldsOnly === true) {
      return;
    }
    this.addRow(true);
  }

  handleAddChangeRemake(event) {
    if (!this.canEditProducts || this.orderedCustomFieldsOnly === true) {
      return;
    }
    const pairId = event.currentTarget.dataset.pairId;
    const group = this.changeProductGroups.find(
      (item) => item.pairId === pairId
    );
    if (!group || !group.original) {
      return;
    }
    const templateRow =
      group.remakeRows[group.remakeRows.length - 1] || group.original;
    this.insertChangeRemakeRow(templateRow, group);
  }

  handleAddChangeNewProduct() {
    if (!this.canEditProducts || this.orderedCustomFieldsOnly === true) {
      return;
    }
    this.addChangeNewRow(true);
  }

  insertChangeRemakeRow(source, group) {
    const insertAfterIndex = this.findLastIndexByPairId(group.pairId);
    const duplicate = this.buildCopiedRow(source, {
      recordType: PRODUCT_TYPE_REMAKE,
      typeLabel: "Remake",
      isDuplicate: false,
      sourceContractProductId: group.sourceContractProductId,
      pairId: group.pairId
    });
    const newList = [...this.itemList];
    newList.splice(insertAfterIndex + 1, 0, duplicate);
    this.commitItemList(newList);
  }

  findLastIndexByPairId(pairId) {
    let lastIndex = -1;
    this.itemList.forEach((item, index) => {
      if (item.pairId === pairId) {
        lastIndex = index;
      }
    });
    return lastIndex;
  }

  addChangeNewRow(shouldEmit = true) {
    const { startDate, endDate } = this.getDefaultDates();
    this.commitItemList(
      [
        ...this.itemList,
        this.applyAmount({
          id: createRowId(),
          productId: "",
          productName: "",
          quantity: 1,
          unit: "",
          billingType: "",
          billingCycle: "",
          unitPrice: 0,
          amount: 0,
          startDate,
          endDate,
          recordType: PRODUCT_TYPE_NEW,
          typeLabel: "New",
          invoiceType: "",
          sourceContractProductId: null,
          pairId: null,
          isReadonly: false,
          rowClass: ""
        })
      ],
      { emit: shouldEmit !== false }
    );
  }

  findPreviousEditableRow(rowIndex) {
    for (let index = rowIndex - 1; index >= 0; index--) {
      const row = this.itemList[index];
      if (!row) {
        continue;
      }
      if (this.orderedCustomFieldsOnly === true || !row.isReadonly) {
        return row;
      }
    }
    return null;
  }

  buildCopiedRow(source, options = {}) {
    const recordType =
      options.recordType ?? source.recordType ?? PRODUCT_TYPE_NEW;
    const typeLabel =
      options.typeLabel ??
      (recordType === PRODUCT_TYPE_RENEW
        ? "Renew"
        : recordType === PRODUCT_TYPE_REMAKE
          ? "Remake"
          : recordType === PRODUCT_TYPE_ORIGINAL
            ? "Original"
            : "New");
    const copied = {
      ...source,
      id: createRowId(),
      recordType,
      typeLabel,
      isDuplicate: options.isDuplicate === true,
      isReadonly: false,
      rowClass: ""
    };
    if (
      Object.prototype.hasOwnProperty.call(options, "sourceContractProductId")
    ) {
      copied.sourceContractProductId = options.sourceContractProductId;
    }
    if (Object.prototype.hasOwnProperty.call(options, "pairId")) {
      copied.pairId = options.pairId;
    }
    // 元行の金額表示（金額入力モード含む）をコピー先でも維持する
    return this.applyAmount(restoreAmountEntryFromSavedAmount(copied));
  }

  insertCopiedRow(source, insertAfterIndex = null) {
    const copyOptions = {
      isDuplicate: false,
      recordType: PRODUCT_TYPE_NEW,
      typeLabel: "New",
      sourceContractProductId: null,
      pairId: null
    };
    const duplicate = this.buildCopiedRow(source, copyOptions);
    const newList = [...this.itemList];
    const index =
      insertAfterIndex == null ? newList.length : insertAfterIndex + 1;
    newList.splice(index, 0, duplicate);
    this.commitItemList(newList);
  }

  addRow(shouldEmit = true) {
    const { startDate, endDate } = this.getDefaultDates();
    this.commitItemList(
      [
        ...this.itemList,
        this.applyAmount({
          id: createRowId(),
          productId: "",
          productName: "",
          quantity: 1,
          unit: "",
          billingType: "",
          billingCycle: "",
          unitPrice: 0,
          amount: 0,
          startDate,
          endDate,
          recordType: PRODUCT_TYPE_NEW,
          typeLabel: "New",
          invoiceType: "",
          isReadonly: false,
          customFields: {},
          rowClass: ""
        })
      ],
      { emit: shouldEmit !== false && !this._bootstrapInFlight }
    );
  }

  normalizeRow(item) {
    const { startDate, endDate } = this.getDefaultDates();
    let recordType = item.recordType || PRODUCT_TYPE_NEW;
    let sourceContractProductId = item.sourceContractProductId;
    let pairId = item.pairId;

    if (this.isChangeType) {
      if (recordType === PRODUCT_TYPE_NEW) {
        sourceContractProductId = null;
        pairId = null;
      }
    }

    return {
      quantity: 1,
      unit: "",
      productName: "",
      billingType: "",
      billingCycle: "",
      amount: 0,
      unitPrice: 0,
      startDate,
      endDate,
      invoiceType: "",
      typeLabel:
        item.typeLabel ||
        (recordType === PRODUCT_TYPE_ORIGINAL
          ? "Original"
          : recordType === PRODUCT_TYPE_REMAKE
            ? "Remake"
            : recordType === PRODUCT_TYPE_RENEW
              ? "Renew"
              : "New"),
      isReadonly: item.isReadonly === true,
      rowClass: item.isReadonly ? "est-row-readonly" : "",
      ...item,
      recordType,
      sourceContractProductId,
      pairId,
      customFields: { ...(item.customFields || {}) },
      productVisibilityContext: {
        ...(item.productVisibilityContext || {})
      }
    };
  }

  applyAmount(row) {
    const rawPrice = Number(row.unitPrice);
    const unitPrice = Number.isFinite(rawPrice)
      ? roundUnitPrice(rawPrice)
      : Number.isNaN(rawPrice)
        ? Number.NaN
        : 0;
    const manualAmount =
      row.amountEntryMode === true && row.manualAmount != null
        ? roundAmountYen(row.manualAmount)
        : row.manualAmount;
    const rawQty = Number(row.quantity);
    const quantity = Number.isFinite(rawQty)
      ? roundQuantity(rawQty)
      : Number(row.quantity) || 0;
    const normalized = {
      ...row,
      quantity: quantity == null ? 0 : quantity,
      unitPrice,
      manualAmount,
      billingCycle:
        row.billingType === BILLING_TYPE_RECURRING
          ? MONTHLY_BILLING_CYCLE
          : row.billingCycle
    };

    const amount = resolveLineAmount({ ...normalized, ...row, manualAmount });
    const amountInvalid =
      amount == null &&
      row.amountEntryMode !== true &&
      normalized.billingType === BILLING_TYPE_RECURRING &&
      !!normalized.startDate &&
      !!normalized.endDate;

    if (!Number.isFinite(unitPrice) && row.amountEntryMode !== true) {
      return {
        ...normalized,
        unitPrice: Number.NaN,
        amount: Number.isFinite(amount) ? amount : Number.NaN,
        amountInvalid,
        unitPriceInvalid: true
      };
    }

    return {
      ...normalized,
      amount,
      amountInvalid,
      unitPriceInvalid:
        row.amountEntryMode === true && !Number.isFinite(unitPrice)
    };
  }

  updateRow(rowId, updates) {
    if (!this.canEditProducts) {
      return;
    }
    const numericUpdates = { ...updates };
    if ("quantity" in numericUpdates) {
      const parsedQty = parseQuantityInput(numericUpdates.quantity);
      if (parsedQty == null) {
        numericUpdates.quantity = 0;
      } else if (Number.isNaN(parsedQty)) {
        numericUpdates.quantity = Number.NaN;
      } else {
        numericUpdates.quantity = parsedQty;
      }
    }
    if ("unitPrice" in numericUpdates) {
      const raw = Number(numericUpdates.unitPrice);
      numericUpdates.unitPrice = Number.isFinite(raw)
        ? roundUnitPrice(raw)
        : Number.isNaN(raw)
          ? Number.NaN
          : 0;
    }
    if (
      "manualAmount" in numericUpdates &&
      numericUpdates.manualAmount != null
    ) {
      const rawManual = Number(numericUpdates.manualAmount);
      numericUpdates.manualAmount = Number.isFinite(rawManual)
        ? roundAmountYen(rawManual)
        : 0;
    }

    const nextList = this.itemList.map((item) => {
      if (item.id !== rowId) {
        return item;
      }
      if (item.isReadonly) {
        return item;
      }
      const rowUpdates = { ...numericUpdates };
      if (isChangeRemakeLine(item)) {
        delete rowUpdates.productId;
        delete rowUpdates.productName;
        delete rowUpdates.unit;
        delete rowUpdates.unitName;
        delete rowUpdates.billingType;
        delete rowUpdates.billingCycle;
      }
      let merged = { ...item, ...rowUpdates };
      const structuralChange =
        "quantity" in rowUpdates ||
        "startDate" in rowUpdates ||
        "endDate" in rowUpdates ||
        "billingType" in rowUpdates ||
        "billingCycle" in rowUpdates;
      if (
        merged.amountEntryMode === true &&
        merged.manualAmount != null &&
        structuralChange &&
        rowUpdates.amountEntryMode !== false
      ) {
        merged = {
          ...merged,
          unitPrice: deriveUnitPriceFromAmount(merged, merged.manualAmount)
        };
      }
      let updated = this.applyAmount(merged);
      if (
        "startDate" in rowUpdates &&
        updated.startDate &&
        isValidIsoDate(updated.startDate) &&
        (!updated.endDate || !isValidIsoDate(updated.endDate))
      ) {
        updated = this.applyAmount({
          ...updated,
          endDate: this.addOneYearEndDate(updated.startDate)
        });
      } else if (
        ("endDate" in rowUpdates || "startDate" in rowUpdates) &&
        updated.startDate &&
        updated.endDate &&
        isValidIsoDate(updated.startDate) &&
        isValidIsoDate(updated.endDate)
      ) {
        const alignedEnd = this.alignLineEndDate(
          updated.startDate,
          updated.endDate
        );
        if (alignedEnd && alignedEnd !== updated.endDate) {
          updated = this.applyAmount({ ...updated, endDate: alignedEnd });
        }
      }
      return {
        ...updated,
        amountEntryMode: merged.amountEntryMode === true,
        manualAmount:
          merged.amountEntryMode === true ? merged.manualAmount : null
      };
    });
    this.commitItemList(nextList);
  }

  handleDeleteRow(event) {
    if (!this.canEditProducts || this.orderedCustomFieldsOnly === true) {
      return;
    }
    const rowId = event.currentTarget.dataset.id;
    const target = this.itemList.find((item) => item.id === rowId);
    if (!target || !target.canDelete) {
      return;
    }
    this.commitItemList(this.itemList.filter((item) => item.id !== rowId));
  }

  handleDuplicateRow(event) {
    const rowId = event.currentTarget.dataset.id;
    const sourceIndex = this.itemList.findIndex((item) => item.id === rowId);
    if (sourceIndex === -1) {
      return;
    }

    const source = this.itemList[sourceIndex];
    if (!source.canDuplicate) {
      return;
    }

    this.insertCopiedRow(source, sourceIndex);
  }

  handleLineDateInputChange(event) {
    const rowId = event.currentTarget.dataset.id;
    const field = event.currentTarget.dataset.field;
    const value = this.readDateInputValue(event);
    if (field === "startDate") {
      this.updateRow(rowId, { startDate: value });
      return;
    }
    if (field === "endDate") {
      this.updateRow(rowId, { endDate: value });
    }
  }

  handleCopyDateFromAbove(event) {
    const rowId = event.currentTarget.dataset.id;
    const field = event.currentTarget.dataset.field;
    const rowIndex = this.itemList.findIndex((item) => item.id === rowId);
    if (rowIndex <= 0) {
      return;
    }
    const previous = this.findPreviousEditableRow(rowIndex);
    if (!previous) {
      return;
    }
    if (field === "startDate") {
      this.updateRow(rowId, { startDate: previous.startDate || "" });
      return;
    }
    if (field === "endDate") {
      this.updateRow(rowId, { endDate: previous.endDate || "" });
      return;
    }
    this.updateRow(rowId, {
      startDate: previous.startDate || "",
      endDate: previous.endDate || ""
    });
  }

  handleFillLineStartFromContract(event) {
    const rowId = event.currentTarget.dataset.id;
    this.updateRow(rowId, { startDate: this.contractStartDate || "" });
  }

  handleFillLineStartOneYear(event) {
    this.adjustLineStartDate(event.currentTarget.dataset.id, { years: 1 });
  }

  handleFillLineStartOneMonth(event) {
    this.adjustLineStartDate(event.currentTarget.dataset.id, { months: 1 });
  }

  handleFillLineStartMinusOneYear(event) {
    this.adjustLineStartDate(event.currentTarget.dataset.id, { years: -1 });
  }

  handleFillLineStartMinusOneMonth(event) {
    this.adjustLineStartDate(event.currentTarget.dataset.id, { months: -1 });
  }

  handleFillLineEndFromContract(event) {
    const rowId = event.currentTarget.dataset.id;
    this.updateRow(rowId, { endDate: this.contractEndDate || "" });
  }

  handleFillLineEndOneYear(event) {
    this.adjustLineEndDate(event.currentTarget.dataset.id, { years: 1 });
  }

  handleFillLineEndOneMonth(event) {
    this.adjustLineEndDate(event.currentTarget.dataset.id, { months: 1 });
  }

  handleFillLineEndMinusOneYear(event) {
    this.adjustLineEndDate(event.currentTarget.dataset.id, { years: -1 });
  }

  handleFillLineEndMinusOneMonth(event) {
    this.adjustLineEndDate(event.currentTarget.dataset.id, { months: -1 });
  }

  handleOpenProductModal(event) {
    const rowId = event.currentTarget.dataset.id;
    const row = this.itemList.find((item) => item.id === rowId);
    if (
      !row ||
      row.isReadonly ||
      isChangeRemakeLine(row) ||
      isRenewProductLine(row)
    ) {
      return;
    }
    this._productModalReturnFocusEl = event.currentTarget;
    this.productModalRowId = rowId;
    this.productModalProductId = row.productId || "";
  }

  handleCloseProductModal() {
    this.productModalRowId = null;
    this.productModalProductId = "";
  }

  handleProductModalKeydown(event) {
    if (!this.isProductModalOpen) {
      return;
    }
    if (event.key === "Escape") {
      event.preventDefault();
      this.handleCloseProductModal();
    }
  }

  renderedCallback() {
    if (this.isProductModalOpen && !this._productModalFocused) {
      this._productModalFocused = true;
      Promise.resolve().then(() => {
        const picker = this.template.querySelector(
          '[data-id="product-inline-picker"] lightning-record-picker'
        );
        if (picker && typeof picker.focus === "function") {
          try {
            picker.focus();
          } catch {
            // ignore
          }
        }
      });
      this._boundProductModalKeydown =
        this.handleProductModalKeydown.bind(this);
      window.addEventListener("keydown", this._boundProductModalKeydown);
    } else if (!this.isProductModalOpen && this._productModalFocused) {
      this.teardownProductModalA11y(true);
    }
    if (!this._resizeObserver && typeof ResizeObserver !== "undefined") {
      this._resizeObserver = new ResizeObserver(() => {
        this.scheduleFitProductNames();
      });
      this._resizeObserver.observe(this.template.host);
    }
    this.scheduleFitProductNames();
  }

  scheduleFitProductNames() {
    if (this._fitProductNamesRaf != null) {
      return;
    }
    this._fitProductNamesRaf = requestAnimationFrame(() => {
      this._fitProductNamesRaf = null;
      this.fitProductNameFonts();
    });
  }

  /**
   * 商品名フォントを長い商品時のサイズに統一（「商品を検索」含む）。
   * 溢れは CSS ellipsis（title で全文）。
   */
  fitProductNameFonts() {
    const nodes = this.template.querySelectorAll(".est-product-name");
    if (!nodes || nodes.length === 0) {
      return;
    }
    const size = `${PRODUCT_NAME_FONT_REM}rem`;
    nodes.forEach((el) => {
      if (el) {
        el.style.fontSize = size;
      }
    });
  }

  teardownProductModalA11y(restoreFocus = false) {
    this._productModalFocused = false;
    if (this._boundProductModalKeydown) {
      window.removeEventListener("keydown", this._boundProductModalKeydown);
      this._boundProductModalKeydown = null;
    }
    if (!restoreFocus) {
      this._productModalReturnFocusEl = null;
      return;
    }
    const el = this._productModalReturnFocusEl;
    this._productModalReturnFocusEl = null;
    if (el && typeof el.focus === "function") {
      Promise.resolve().then(() => {
        try {
          el.focus();
        } catch {
          // ignore detached nodes
        }
      });
    }
  }

  async handleInlineProductChange(event) {
    const rowId = this.productModalRowId;
    const selectedProductId = event.detail.recordId || "";
    this.productModalProductId = selectedProductId;
    if (!rowId) {
      return;
    }
    // 選択（またはクリア）したらセル内ピッカーを閉じて即反映
    this.handleCloseProductModal();
    await this.applyProductSelection(rowId, selectedProductId);
  }

  async applyProductSelection(rowId, selectedProductId) {
    const row = this.itemList.find((item) => item.id === rowId);
    if (
      !row ||
      row.isReadonly ||
      isChangeRemakeLine(row) ||
      isRenewProductLine(row)
    ) {
      return;
    }
    const selectSeq =
      (this._productSelectSeqByRowId[rowId] || 0) + 1;
    this._productSelectSeqByRowId[rowId] = selectSeq;
    if (!selectedProductId) {
      this.updateRow(rowId, {
        productId: "",
        productName: "",
        unit: "",
        billingType: "",
        productMasterBillingType: "",
        billingCycle: "",
        unitPrice: 0,
        // 商品クリア時は金額入力モードも解除（旧 manualAmount を残さない）
        amountEntryMode: false,
        manualAmount: null,
        productVisibilityContext: {},
        customFields: this.syncProductCustomFields(row.customFields)
      });
      return;
    }

    try {
      const defaults = await getProductDefaults({
        productId: selectedProductId
      });
      // より新しい選択／クリアが始まっていたら、この応答は捨てる
      if (this._productSelectSeqByRowId[rowId] !== selectSeq) {
        return;
      }
      if (!defaults) {
        this.showToast(
          "商品を選択できません",
          "選択した商品の情報を取得できませんでした。契約管理で利用可能な商品を選択してください。",
          "error"
        );
        return;
      }
      const billingType =
        defaults && defaults.billingType ? defaults.billingType : "";
      const rawInvoiceType =
        defaults && defaults.invoiceType ? defaults.invoiceType : "";
      const invoiceSettingError = validateInvoiceSettingForBillingType(
        billingType,
        rawInvoiceType
      );
      if (invoiceSettingError) {
        this.showToast("商品を選択できません", invoiceSettingError, "error");
        return;
      }
      const invoiceType = this.resolveRowInvoiceType(
        rawInvoiceType,
        billingType
      );
      const productVisibilityContext = {
        ...((defaults && defaults.productVisibilityContext) || {})
      };

      if (this._productSelectSeqByRowId[rowId] !== selectSeq) {
        return;
      }
      this.updateRow(rowId, {
        productId: selectedProductId,
        productName:
          defaults && defaults.productName ? defaults.productName : "",
        unitName: defaults && defaults.unitName ? defaults.unitName : "",
        unit:
          defaults && defaults.displayUnit
            ? defaults.displayUnit
            : buildDisplayUnit(
                defaults ? defaults.unitName : "",
                billingType,
                defaults ? defaults.billingCycle : ""
              ),
        billingType,
        productMasterBillingType: billingType,
        billingCycle:
          billingType === BILLING_TYPE_RECURRING
            ? MONTHLY_BILLING_CYCLE
            : defaults && defaults.billingCycle
              ? defaults.billingCycle
              : "",
        unitPrice:
          defaults && defaults.unitPrice != null ? defaults.unitPrice : 0,
        invoiceType,
        // 商品差し替え時は金額入力を解除し、新単価から金額を再計算する
        amountEntryMode: false,
        manualAmount: null,
        productVisibilityContext,
        customFields: this.syncProductCustomFields(
          row.customFields,
          productVisibilityContext
        )
      });
    } catch (error) {
      if (this._productSelectSeqByRowId[rowId] !== selectSeq) {
        return;
      }
      // 取得に失敗した場合は行を書き換えず、直前の選択状態を保つ
      this.showToast(
        "商品を選択できません",
        this.reduceErrorMessage(error),
        "error"
      );
    }
  }

  handleQuantityChange(event) {
    const rowId = event.currentTarget.dataset.id;
    this.updateRow(rowId, {
      quantity: parseQuantityInput(event.target.value)
    });
  }

  handleUnitPriceChange(event) {
    const rowId = event.currentTarget.dataset.id;
    this.updateRow(rowId, {
      unitPrice: parseUnitPriceInput(event.target.value),
      amountEntryMode: false,
      manualAmount: null
    });
  }

  handleAmountChange(event) {
    const rowId = event.currentTarget.dataset.id;
    const row = this.itemList.find((item) => item.id === rowId);
    if (!row || row.isReadonly) {
      return;
    }
    const manualAmount = parseAmountYenInput(event.target.value);
    const unitPrice = deriveUnitPriceFromAmount(row, manualAmount);
    this.updateRow(rowId, {
      unitPrice,
      amountEntryMode: true,
      manualAmount
    });
  }

  handleEnableAmountEntry(event) {
    const rowId = event.currentTarget.dataset.id;
    const row = this.itemList.find((item) => item.id === rowId);
    if (!row || row.isReadonly) {
      return;
    }
    const manualAmount =
      row.amount != null && Number.isFinite(Number(row.amount))
        ? roundAmountYen(row.amount)
        : 0;
    const unitPrice = deriveUnitPriceFromAmount(row, manualAmount);
    this.updateRow(rowId, {
      unitPrice,
      amountEntryMode: true,
      manualAmount
    });
  }

  handleUnlockUnitPrice(event) {
    const rowId = event.currentTarget.dataset.id;
    const row = this.itemList.find((item) => item.id === rowId);
    const unitPrice = Number.isFinite(Number(row && row.unitPrice))
      ? Number(row.unitPrice)
      : 0;
    this.updateRow(rowId, {
      unitPrice,
      amountEntryMode: false,
      manualAmount: null
    });
  }

  handleInvoiceTypeChange(event) {
    const rowId = event.currentTarget.dataset.id;
    const value = event.target.value;
    const row = this.itemList.find((item) => item.id === rowId);
    if (!row) {
      return;
    }
    const validationError = validateInvoiceSettingForBillingType(
      row.billingType,
      value,
      this.invoiceSettingOptions
    );
    if (validationError) {
      // 不正な選択は元の値に戻しつつ、理由を通知する（無言リバートを避ける）。
      event.target.value = row.invoiceType;
      this.showToast("請求設定を変更できません", validationError, "error");
      return;
    }
    this.updateRow(rowId, {
      invoiceType: value
    });
  }

  handleBillingTypeFlip(event) {
    if (!this.isNewType) {
      return;
    }
    const rowId = event.currentTarget.dataset.rowId;
    const value = event.currentTarget.dataset.nextBillingType;
    const row = this.itemList.find((item) => item.id === rowId);
    if (!row) {
      return;
    }
    const masterBillingType =
      row.productMasterBillingType || BILLING_TYPE_RECURRING;
    if (masterBillingType !== BILLING_TYPE_RECURRING) {
      this.showToast(
        "課金種別を変更できません",
        "この商品の課金種別は変更できません。",
        "error"
      );
      return;
    }
    if (
      value !== BILLING_TYPE_RECURRING &&
      value !== BILLING_TYPE_ONE_TIME
    ) {
      return;
    }
    if (value === row.billingType) {
      return;
    }
    const nextInvoiceType = this.resolveRowInvoiceType(row.invoiceType, value);
    const billingCycle =
      value === BILLING_TYPE_ONE_TIME ? "" : MONTHLY_BILLING_CYCLE;
    this.updateRow(rowId, {
      billingType: value,
      invoiceType: nextInvoiceType,
      productMasterBillingType: masterBillingType,
      billingCycle,
      unit: buildDisplayUnit(row.unitName || "", value, billingCycle)
    });
  }

  applyRemarkPresetFromWizardData() {
    const masterId = this.estimateRemarkMasterId || "";
    const remarks = this.estimateRemarks || "";
    if (masterId || remarks) {
      this.remarkMasterPickerKey = `remark-master-${Date.now()}`;
    }
  }

  async handleRemarkMasterChange(event) {
    const masterId = event.detail.recordId || "";
    const previousMasterId = this.estimateRemarkMasterId || "";

    if (masterId === previousMasterId) {
      return;
    }

    if (!masterId) {
      if (this.hasEstimateRemarksText()) {
        const confirmed = await this.requestUserConfirm(
          "見積備考マスタの選択を解除すると、見積備考の内容もクリアされます。よろしいですか？"
        );
        if (!confirmed) {
          await this.revertRemarkMasterPicker(previousMasterId);
          return;
        }
      }
      this.applyBusinessFields({
        estimateRemarkMasterId: "",
        estimateRemarks: ""
      });
      return;
    }

    let masterText = "";
    try {
      masterText = (await getEstimateRemarkMasterText({ masterId })) || "";
    } catch (error) {
      await this.revertRemarkMasterPicker(previousMasterId);
      this.showToast(
        "見積備考マスタの取得に失敗しました。",
        this.reduceErrorMessage(error),
        "error"
      );
      return;
    }

    if (this.hasEstimateRemarksText()) {
      const confirmed = await this.requestUserConfirm(
        "見積備考に入力済みの文章があります。選択した見積備考マスタの内容で上書きしますか？"
      );
      if (!confirmed) {
        await this.revertRemarkMasterPicker(previousMasterId);
        return;
      }
    }

    this.applyBusinessFields({
      estimateRemarkMasterId: masterId,
      estimateRemarks: masterText
    });
  }

  requestUserConfirm(message) {
    const requestId = createConfirmRequestId(this._confirmResolvers.size);
    return new Promise((resolve) => {
      this._confirmResolvers.set(requestId, resolve);
      this.dispatchEvent(
        new CustomEvent("confirmrequest", {
          bubbles: true,
          composed: true,
          detail: { message, requestId }
        })
      );
    });
  }

  @api
  resolveConfirmRequest(requestId, confirmed) {
    const resolve = this._confirmResolvers.get(requestId);
    if (!resolve) {
      return;
    }
    this._confirmResolvers.delete(requestId);
    resolve(confirmed === true);
  }

  rejectAllPendingConfirms() {
    for (const resolve of this._confirmResolvers.values()) {
      resolve(false);
    }
    this._confirmResolvers.clear();
  }

  hasEstimateRemarksText() {
    return hasEstimateRemarksText(this.estimateRemarks);
  }

  async revertRemarkMasterPicker() {
    // record-picker を強制再描画して親の現在値に戻す
    this.remarkMasterPickerKey = `remark-master-${Date.now()}`;
  }

  reduceErrorMessage(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    if (error && error.message) {
      return error.message;
    }
    return "不明なエラーが発生しました。";
  }

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title,
        message,
        variant
      })
    );
  }

  handleRemarksChange(event) {
    this.applyBusinessFields({
      estimateRemarks: event.target.value
    });
  }

  /**
   * 日付・備考・履歴名などの業務項目を親へ送る。
   * ローカルには持たない（fixedEffectiveDate のみ UI 派生として例外）。
   */
  applyBusinessFields(fields, options = {}) {
    if (!fields) {
      return;
    }
    if (fields.fixedEffectiveDate !== undefined) {
      this.fixedEffectiveDate = fields.fixedEffectiveDate;
    }
    const detail = {};
    if (fields.contractStartDate !== undefined) {
      detail.contractStartDate = fields.contractStartDate;
    }
    if (fields.contractEndDate !== undefined) {
      const startForAlign =
        fields.contractStartDate !== undefined
          ? fields.contractStartDate
          : this.contractStartDate;
      detail.contractEndDate = this.alignContractEndDate(
        fields.contractEndDate,
        startForAlign
      );
    }
    if (fields.contractEffectiveDate !== undefined) {
      detail.contractEffectiveDate = fields.contractEffectiveDate;
    }
    if (fields.previousTermStartDate !== undefined) {
      detail.previousTermStartDate = fields.previousTermStartDate;
    }
    if (fields.previousTermEndDate !== undefined) {
      detail.previousTermEndDate = fields.previousTermEndDate;
    }
    if (fields.contractHistoryName !== undefined) {
      detail.contractHistoryName = fields.contractHistoryName;
    }
    if (fields.estimateRemarkMasterId !== undefined) {
      detail.estimateRemarkMasterId = fields.estimateRemarkMasterId;
    }
    if (fields.estimateRemarks !== undefined) {
      detail.estimateRemarks = fields.estimateRemarks;
    }
    if (options.emit === false) {
      return;
    }
    if (Object.keys(detail).length === 0) {
      return;
    }
    this.emitChange(detail);
  }

  /**
   * 商品明細を表示キャッシュへ反映し、親へ送る。
   * ブートストラップ中は emit しない（最後に emitProductsFromItemList）。
   */
  commitItemList(nextList, options = {}) {
    const decorated = this.decorateAllRows(nextList || []);
    this.itemList = decorated;
    const headerDates = this.computeHeaderDatesFromRecurringProducts();
    const shouldEmit = options.emit !== false && !this._bootstrapInFlight;
    if (!shouldEmit) {
      return;
    }
    const detail = {
      selectedProducts: this.serializeProducts(decorated)
    };
    if (options.changeSourceProducts !== undefined) {
      detail.changeSourceProducts = options.changeSourceProducts || [];
    }
    if (headerDates) {
      if (headerDates.contractStartDate !== undefined) {
        detail.contractStartDate = headerDates.contractStartDate;
      }
      if (headerDates.contractEndDate !== undefined) {
        detail.contractEndDate = headerDates.contractEndDate;
      }
      if (headerDates.contractEffectiveDate !== undefined) {
        detail.contractEffectiveDate = headerDates.contractEffectiveDate;
      }
    }
    if (this.isChangeType && decorated.length > 0) {
      const startForChange =
        (headerDates && headerDates.contractStartDate) ||
        this.contractStartDate ||
        "";
      const earliest = this.computeChangeEffectiveDate(
        decorated,
        startForChange
      );
      if (earliest) {
        detail.contractEffectiveDate = earliest;
      } else {
        // 一回追加のみなど切替日なし
        detail.contractEffectiveDate = "";
      }
    }
    if (this.isAddType) {
      detail.contractStartDate = "";
      detail.contractEndDate = "";
      detail.contractEffectiveDate = "";
    }
    this._lastEmittedProductsFingerprint = buildProductsFingerprint(
      detail.selectedProducts
    );
    this._lastSyncedProductsFingerprint = this._lastEmittedProductsFingerprint;
    this.emitChange(detail);
  }

  serializeProducts(rows) {
    return (rows || [])
      .filter((item) => item && !item.isGroupHeader && !item.isCustomDetailRow)
      .map((item) => serializeBusinessProduct(item))
      .filter((item) => item != null);
  }

  computeChangeEffectiveDate(rows = this.itemList, startDateOverride) {
    if (!this.isChangeType) {
      return "";
    }
    return (
      getEarliestChangeBillingThresholdDate(
        rows,
        startDateOverride !== undefined
          ? startDateOverride || ""
          : this.contractStartDate || ""
      ) || ""
    );
  }

  emitChange(detail) {
    if (!this._isConnected) {
      return;
    }
    if (!detail || Object.keys(detail).length === 0) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("changefield", {
        bubbles: true,
        composed: true,
        detail
      })
    );
  }

  emitProductsFromItemList() {
    const detail = {
      selectedProducts: this.serializeProducts(this.itemList)
    };
    const headerDates = this.computeHeaderDatesFromRecurringProducts();
    if (headerDates) {
      if (headerDates.contractStartDate !== undefined) {
        detail.contractStartDate = headerDates.contractStartDate;
      }
      if (headerDates.contractEndDate !== undefined) {
        detail.contractEndDate = headerDates.contractEndDate;
      }
      if (headerDates.contractEffectiveDate !== undefined) {
        detail.contractEffectiveDate = headerDates.contractEffectiveDate;
      }
    }
    if (this.isChangeType) {
      detail.changeSourceProducts = (this.changeSourceProducts || []).map(
        (source) => ({ ...source })
      );
      const earliest = this.computeChangeEffectiveDate();
      if (earliest) {
        detail.contractEffectiveDate = earliest;
      } else {
        detail.contractEffectiveDate = "";
      }
    }
    this._lastEmittedProductsFingerprint = buildProductsFingerprint(
      detail.selectedProducts
    );
    this._lastSyncedProductsFingerprint = this._lastEmittedProductsFingerprint;
    this.emitChange(detail);
  }

  syncDisplayFromParent() {
    const products =
      (this._wizardData && this._wizardData.selectedProducts) || [];
    this._lastSyncedProductsFingerprint = buildProductsFingerprint(products);
    // 親は業務フィールドのみ。表示用プロパティは再 decorate で付与する。
    this.itemList = this.decorateAllRows(
      products.map((item) =>
        this.applyAmount(
          restoreAmountEntryFromSavedAmount(
            this.normalizeRow(stripUiFields(item) || {})
          )
        )
      )
    );
  }

  handleToggleAllProductCustomFields() {
    this.productCustomFieldsExpanded = !this.productCustomFieldsExpanded;
    // expand はローカル表示のみ。親へは送らない。
    this.itemList = this.decorateAllRows(this.itemList);
  }

  handleToggleRecurringPeriod() {
    this.recurringPeriodExpanded = !this.recurringPeriodExpanded;
  }

  handleToggleProductLines() {
    this.productLinesExpanded = !this.productLinesExpanded;
  }

  emitDefaultContractCustomFieldsIfNeeded() {
    if (!this._wizardData) {
      return;
    }
    const fields = {};
    // 商品と同じ: ShowOn* 非表示は prune し、再表示時は Default を入れ直す
    const currentService = this.contractServiceCustomFields;
    const nextService = syncCustomFieldsForVisibility(
      currentService,
      this.serviceFieldDefinitions,
      undefined,
      this.effectiveSelectedType,
      this.opportunityDefaultContext
    );
    if (!shallowEqualFieldMaps(nextService, currentService)) {
      fields.contractServiceCustomFields = nextService;
    }
    const currentHistory = this.contractHistoryCustomFields;
    const nextHistory = syncCustomFieldsForVisibility(
      currentHistory,
      this.historyFieldDefinitions,
      undefined,
      this.effectiveSelectedType,
      this.opportunityDefaultContext
    );
    if (!shallowEqualFieldMaps(nextHistory, currentHistory)) {
      fields.contractHistoryCustomFields = nextHistory;
    }
    if (Object.keys(fields).length > 0) {
      this.emitChange(fields);
    }
  }

  handleToggleContractCustomFields() {
    const next = !this.contractCustomFieldsExpanded;
    this.emitChange({
      serviceCustomFieldsExpanded: next,
      historyCustomFieldsExpanded: next
    });
  }

  handleToggleRemarks() {
    this.emitChange({
      remarksExpanded: !this.remarksExpanded
    });
  }

  handleContractCustomFieldChange(event) {
    const { fieldTarget, fieldApi, value } = event.detail || {};
    if (!fieldApi) {
      return;
    }
    if (fieldTarget === "contractService") {
      this.emitChange({
        contractServiceCustomFields: {
          ...this.contractServiceCustomFields,
          [fieldApi]: value
        }
      });
    } else if (fieldTarget === "contractHistory") {
      this.emitChange({
        contractHistoryCustomFields: {
          ...this.contractHistoryCustomFields,
          [fieldApi]: value
        }
      });
    }
  }

  handleLineCustomFieldChange(event) {
    const { fieldTarget, fieldApi, value } = event.detail || {};
    if (!fieldTarget || !fieldApi) {
      return;
    }
    this.productCustomFieldsExpanded = true;
    this.commitItemList(
      this.itemList.map((item) => {
        if (item.id !== fieldTarget) {
          return item;
        }
        return {
          ...item,
          customFields: {
            ...(item.customFields || {}),
            [fieldApi]: value
          }
        };
      })
    );
  }
}
