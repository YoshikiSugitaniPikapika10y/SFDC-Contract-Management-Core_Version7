import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getSettings from "@salesforce/apex/ContractDocumentSettingsController.getSettings";
import saveSettings from "@salesforce/apex/ContractDocumentSettingsController.saveSettings";
import issueOrgSettingsOperationKey from "@salesforce/apex/ContractDocumentSettingsController.issueOrgSettingsOperationKey";
import validateFieldCopyDefinitions from "@salesforce/apex/ContractDocumentSettingsController.validateFieldCopyDefinitions";
import hasOrgSettings from "@salesforce/customPermission/Loop_20_Can_OrgSettings";

const EMPTY_OPTION = { label: "（未設定）", value: "" };
// 仕様: Core 第11.6節・第4.3.12節。ContractOptimisticLockUtil.CONFLICT_MESSAGE と同一。
const VERSION_CONFLICT_MESSAGE =
  "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。";
const SEND_MODE_OPTIONS = [
  { label: "使わない", value: "Unused" },
  { label: "PDFのみ", value: "PdfOnly" },
  { label: "PDFとメール送付", value: "PdfAndEmail" }
];
const SEND_MODE_STORED_VALUES = SEND_MODE_OPTIONS.map((option) => option.value);
const REVENUE_RECOGNITION_BASIS_OPTIONS = [
  { label: "請求基準", value: "BillingBasis" },
  { label: "入金連動前受基準", value: "CashBasis" }
];
const TAX_RECOGNITION_TIMING_OPTIONS = [
  { label: "請求時", value: "AtInvoice" },
  { label: "売上計上時", value: "AtRecognition" }
];
const MONTHLY_BUCKET_METHOD_OPTIONS = [
  { label: "自動", value: "Auto" },
  { label: "契約日アンカー", value: "ContractAnchor" },
  { label: "暦月", value: "CalendarMonth" }
];
const MONTHLY_RECOGNITION_DATE_POSITION_OPTIONS = [
  { label: "バケット開始日", value: "BucketStart" },
  { label: "バケット終了日", value: "BucketEnd" },
  { label: "終了日所属月の末日", value: "MonthEnd" }
];
const ROUNDING_TARGET_BUCKET_OPTIONS = [
  { label: "最終バケット", value: "Last" },
  { label: "初回バケット", value: "First" }
];
const TAX_ROUNDING_MODE_OPTIONS = [
  { label: "0方向切捨て", value: "DOWN" },
  { label: "四捨五入", value: "HALF_UP" },
  { label: "0から離れる切上げ", value: "UP" }
];
const QUANTITY_UNIT_PRICE_ROUNDING_MODE_OPTIONS = [
  { label: "小数第2位の四捨五入", value: "Scale2HalfUp" }
];
const AMOUNT_ROUNDING_MODE_OPTIONS = [
  { label: "整数円の四捨五入", value: "Scale0HalfUp" }
];
const TAX_LINE_ALLOCATION_METHOD_OPTIONS = [
  { label: "符号付き最大剰余", value: "SignedLargestRemainder" }
];
const ALLOCATION_TIE_BREAK_OPTIONS = [
  { label: "請求明細の安定順", value: "InvoiceLineStableOrder" }
];
const MONTHLY_BUCKET_AMOUNT_METHOD_OPTIONS = [
  { label: "均等割り", value: "EqualSplit" }
];
const TAX_SCHEDULE_ALLOCATION_METHOD_OPTIONS = [
  { label: "符号付き売上比", value: "SignedRevenueRatio" }
];
const PAYMENT_LINE_ALLOCATION_METHOD_OPTIONS = [
  { label: "未処理税込の比例", value: "OpenInclusiveRatio" }
];
const ACCOUNT_BALANCE_ALLOCATION_METHOD_OPTIONS = [
  { label: "同じ率", value: "SameRate" }
];
const DOCUMENT_GROUP_TAX_ALLOCATION_METHOD_OPTIONS = [
  { label: "税抜比、最後のグループで吸収", value: "ExclusiveRatioLastAbsorbs" }
];
const AMOUNT_READONLY_FIELDS = [
  {
    key: "quantityUnitPriceRoundingMode",
    label: "数量・単価の丸め",
    options: QUANTITY_UNIT_PRICE_ROUNDING_MODE_OPTIONS
  },
  {
    key: "amountRoundingMode",
    label: "税抜金額の丸め",
    options: AMOUNT_ROUNDING_MODE_OPTIONS
  },
  {
    key: "taxLineAllocationMethod",
    label: "ヘッダ税の明細配分",
    options: TAX_LINE_ALLOCATION_METHOD_OPTIONS
  },
  {
    key: "allocationTieBreak",
    label: "同率の決定順",
    options: ALLOCATION_TIE_BREAK_OPTIONS
  },
  {
    key: "monthlyBucketAmountMethod",
    label: "月次バケットの金額",
    options: MONTHLY_BUCKET_AMOUNT_METHOD_OPTIONS
  },
  {
    key: "taxScheduleAllocationMethod",
    label: "税のスケジュール配分",
    options: TAX_SCHEDULE_ALLOCATION_METHOD_OPTIONS
  },
  {
    key: "paymentLineAllocationMethod",
    label: "一部入返金の初期配分",
    options: PAYMENT_LINE_ALLOCATION_METHOD_OPTIONS
  },
  {
    key: "accountBalanceAllocationMethod",
    label: "複数実勘定への配分",
    options: ACCOUNT_BALANCE_ALLOCATION_METHOD_OPTIONS
  },
  {
    key: "documentGroupTaxAllocationMethod",
    label: "帳票グループ税込",
    options: DOCUMENT_GROUP_TAX_ALLOCATION_METHOD_OPTIONS
  }
];

export default class ContractDocumentSettings extends LightningElement {
  settings = {};
  sendModeOptions = SEND_MODE_OPTIONS;
  revenueRecognitionBasisOptions = REVENUE_RECOGNITION_BASIS_OPTIONS;
  taxRecognitionTimingOptions = TAX_RECOGNITION_TIMING_OPTIONS;
  monthlyBucketMethodOptions = MONTHLY_BUCKET_METHOD_OPTIONS;
  monthlyRecognitionDatePositionOptions =
    MONTHLY_RECOGNITION_DATE_POSITION_OPTIONS;
  roundingTargetBucketOptions = ROUNDING_TARGET_BUCKET_OPTIONS;
  taxRoundingModeOptions = TAX_ROUNDING_MODE_OPTIONS;
  orgWideEmailAddresses = [EMPTY_OPTION];
  links = {};
  hasAccountingMaster = false;
  loading = true;
  _pendingOperationKey = "";

  // 仕様: Core 第11.6節
  get settingsPageTitle() {
    return "組織設定";
  }

  get canManageOrgSettings() {
    return hasOrgSettings === true;
  }

  get saveSuccessMessage() {
    return "組織設定を保存しました。";
  }

  get policyFrozen() {
    return this.settings?.policyFrozen === true;
  }

  get showAccountingMasterLinks() {
    return this.hasAccountingMaster === true;
  }

  get freezePolicyBadge() {
    return this.policyFrozen ? "変更不可" : "確定後は変更不可";
  }

  get freezePolicyBadgeClass() {
    return this.policyFrozen
      ? "slds-badge badge-locked"
      : "slds-badge badge-will-lock";
  }

  get freezePolicyHint() {
    return this.policyFrozen
      ? null
      : "最初の請求確定まで変えられる。確定後は104以外では戻せない";
  }

  get showFrozenBy() {
    return this.policyFrozen;
  }

  get amountCautionText() {
    return "変更しても保存済みは再計算しない";
  }

  get amountReadonlyItems() {
    return AMOUNT_READONLY_FIELDS.map((field) => ({
      key: field.key,
      label: field.label,
      text: this.optionLabel(field.options, this.settings?.[field.key])
    }));
  }

  /** 仕様: Core 第11.3.1節。見積または請求が使わない以外なら会社名・住所必須。 */
  get companyNameRequired() {
    return (
      this.isUsedSendMode(this.settings?.estimateSendMode) ||
      this.isUsedSendMode(this.settings?.invoiceSendMode)
    );
  }

  get addressRequired() {
    return this.companyNameRequired;
  }

  /** 仕様: Core 第11.3.1節。請求が使わない以外なら登録番号・振込先必須。 */
  get invoiceCompanyFieldsRequired() {
    return this.isUsedSendMode(this.settings?.invoiceSendMode);
  }

  /** 仕様: Core 第11.3.2節。請求がPDFとメール送付なら請求用組織送信元必須。 */
  get invoiceOrgWideRequired() {
    return this.settings?.invoiceSendMode === "PdfAndEmail";
  }

  get permissionSetsUrl() {
    return this.links.permissionSets;
  }
  get permissionSetGroupsUrl() {
    return this.links.permissionSetGroups;
  }
  get sharingUrl() {
    return this.links.sharing;
  }
  get productsUrl() {
    return this.links.products;
  }
  get documentCatalogUrl() {
    return this.links.documentCatalog;
  }
  get estimateNotesUrl() {
    return this.links.estimateNotes;
  }
  get emailCatalogUrl() {
    return this.links.emailCatalog;
  }
  get estimateWizardFieldsUrl() {
    return this.links.estimateWizardFields;
  }
  get orderWizardFieldsUrl() {
    return this.links.orderWizardFields;
  }
  get invoiceOpsFieldsUrl() {
    return this.links.invoiceOpsFields;
  }
  get fieldCopyUrl() {
    return this.links.fieldCopy;
  }
  get amountCalculationUrl() {
    return this.links.amountCalculation;
  }
  get glAccountsUrl() {
    return this.links.glAccounts;
  }
  get conditionSetsUrl() {
    return this.links.conditionSets;
  }
  get accountMapsUrl() {
    return this.links.accountMaps;
  }
  get tagRulesUrl() {
    return this.links.tagRules;
  }
  get manualJournalsUrl() {
    return this.links.manualJournals;
  }

  isUsedSendMode(mode) {
    return mode != null && mode !== "" && mode !== "Unused";
  }

  usesPdfSendMode(mode) {
    return mode === "PdfOnly" || mode === "PdfAndEmail";
  }

  isBlankSetting(value) {
    return value == null || String(value).trim() === "";
  }

  optionLabel(options, value) {
    const hit = (options || []).find((option) => option.value === value);
    return hit ? hit.label : value == null ? "" : String(value);
  }

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      const result = await getSettings();
      this.settings = { ...(result.settings || {}) };
      this.orgWideEmailAddresses = [
        EMPTY_OPTION,
        ...(result.orgWideEmailAddresses || [])
      ];
      this.hasAccountingMaster = result.hasAccountingMaster === true;
      const nextLinks = {};
      (result.settingLinks || []).forEach((row) => {
        if (row?.key) {
          nextLinks[row.key] = row.url;
        }
      });
      this.links = nextLinks;
    } catch (error) {
      this.toast("読込エラー", this.message(error), "error");
    } finally {
      this.loading = false;
    }
  }

  /**
   * 仕様: Core 第11.3節・第11.6節。3択の保存値は Unused／PdfOnly／PdfAndEmail。
   * combobox の event.target.value は表示ラベルになりうるので、detail.value を正とする。
   */
  handleChange(event) {
    const name = event.target?.name;
    if (!name) {
      return;
    }
    const type = event.target.type;
    const detailValue = event.detail ? event.detail.value : undefined;
    let nextValue;
    if (type === "checkbox") {
      nextValue = event.target.checked;
    } else if (type === "number") {
      const raw = detailValue !== undefined ? detailValue : event.target.value;
      nextValue = raw === "" || raw == null ? null : Number(raw);
    } else {
      nextValue = detailValue !== undefined ? detailValue : event.target.value;
    }
    this.settings = {
      ...this.settings,
      [name]: nextValue
    };
  }

  handleOpenLink(event) {
    const url = event.currentTarget?.href;
    if (!url) {
      return;
    }
    event.preventDefault();
    window.open(url, "_blank");
  }

  async handleValidateFieldCopy() {
    this.loading = true;
    try {
      const message = await validateFieldCopyDefinitions();
      this.toast("検証完了", message, "success");
    } catch (error) {
      this.toast("検証エラー", this.message(error), "error");
    } finally {
      this.loading = false;
    }
  }

  async handleSave() {
    this.applyNamedFieldValues();
    try {
      this.assertStoredSendModes();
    } catch (error) {
      this.toast("保存エラー", this.message(error), "error");
      return;
    }
    if (!this.reportValidity()) {
      return;
    }
    this.loading = true;
    try {
      // 仕様: Core 第11.6節。押下時サーバ発行。応答のキーだけを再試行に使う。
      if (!this._pendingOperationKey) {
        this._pendingOperationKey = await issueOrgSettingsOperationKey();
      }
      const saved = await saveSettings({
        input: {
          ...this.settings,
          businessOperationKey: this._pendingOperationKey
        }
      });
      this._pendingOperationKey = "";
      this.settings = { ...saved, businessOperationKey: null };
      this.toast("保存完了", this.saveSuccessMessage, "success");
    } catch (error) {
      const msg = this.message(error);
      this.toast("保存エラー", msg, "error");
      // 仕様: Core 第11.6節・第4.3.12節。版比較失敗時は画面を読み直す。
      if (msg === VERSION_CONFLICT_MESSAGE) {
        this._pendingOperationKey = "";
        await this.load();
      }
    } finally {
      this.loading = false;
    }
  }

  /**
   * 仕様: Core 第11.3節・第1.1.10節。保存値は Unused／PdfOnly／PdfAndEmail のみ。
   * 表示ラベルや空は不正として止める。PdfOnly へ落とさない。
   */
  assertStoredSendModes() {
    const estimate = this.settings?.estimateSendMode;
    const invoice = this.settings?.invoiceSendMode;
    if (!SEND_MODE_STORED_VALUES.includes(estimate)) {
      throw new Error("見積書の3択が無い、空、または不正です。");
    }
    if (!SEND_MODE_STORED_VALUES.includes(invoice)) {
      throw new Error("請求書の3択が無い、空、または不正です。");
    }
  }

  /** 仕様: Core 第11.6節。画面に出ている値を保存対象にする。3択は表示ラベルを保存値へ戻す。 */
  applyNamedFieldValues() {
    const next = { ...this.settings };
    this.template
      .querySelectorAll(
        "lightning-input, lightning-textarea, lightning-combobox"
      )
      .forEach((element) => {
        const name = element.name;
        if (!name) {
          return;
        }
        if (element.type === "checkbox") {
          next[name] = element.checked;
          return;
        }
        const raw = element.value;
        if (element.type === "number") {
          next[name] = raw === "" || raw == null ? null : Number(raw);
          return;
        }
        if (name === "estimateSendMode" || name === "invoiceSendMode") {
          next[name] = this.storedSendMode(raw);
          return;
        }
        next[name] = raw;
      });
    this.settings = next;
  }

  /**
   * 仕様: Core 第11.3節・第0.1節。保存値は Unused／PdfOnly／PdfAndEmail。
   * combobox の value が表示ラベルでも保存値へ戻す。未知値は落とさない。
   */
  storedSendMode(raw) {
    if (SEND_MODE_STORED_VALUES.includes(raw)) {
      return raw;
    }
    const hit = SEND_MODE_OPTIONS.find((option) => option.label === raw);
    return hit ? hit.value : raw;
  }

  /** 仕様: Core 第11.3.1節、第11.3.2節、第1.1.10節。必須空は画面で止める。空白のみは空。 */
  reportValidity() {
    this.applyRequiredFieldValidity();
    return [
      ...this.template.querySelectorAll(
        "lightning-input, lightning-textarea, lightning-combobox"
      )
    ].reduce((valid, component) => {
      component.reportValidity();
      return valid && component.checkValidity();
    }, true);
  }

  applyRequiredFieldValidity() {
    this.setRequiredBlankValidity(
      "companyName",
      this.companyNameRequired,
      "会社名を設定してください。"
    );
    this.setRequiredBlankValidity(
      "address",
      this.addressRequired,
      "住所を設定してください。"
    );
    this.setRequiredBlankValidity(
      "invoiceRegistrationNumber",
      this.invoiceCompanyFieldsRequired,
      "適格請求書発行事業者登録番号を設定してください。"
    );
    this.setRequiredBlankValidity(
      "bankTransferInfo",
      this.invoiceCompanyFieldsRequired,
      "振込先を設定してください。"
    );
    this.setRequiredBlankValidity(
      "invoiceOrgWideEmailAddress",
      this.invoiceOrgWideRequired,
      "PDFとメール送付のとき、組織の送信元を選んでください。"
    );
  }

  setRequiredBlankValidity(name, required, message) {
    const element = this.template.querySelector(`[name="${name}"]`);
    if (!element || typeof element.setCustomValidity !== "function") {
      return;
    }
    if (required && this.isBlankSetting(this.settings?.[name])) {
      element.setCustomValidity(message);
    } else {
      element.setCustomValidity("");
    }
  }

  message(error) {
    return (
      error?.body?.message ||
      error?.message ||
      "予期しないエラーが発生しました。"
    );
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
