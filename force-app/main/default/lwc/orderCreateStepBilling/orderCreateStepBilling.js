import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import { getRecordNotifyChange } from "lightning/uiRecordApi";
import getOrderBillingFieldDefinitions from "@salesforce/apex/OrderWizardFieldService.getOrderBillingFieldDefinitions";
import getBillingAccountInvoiceSettings from "@salesforce/apex/EstimateCreateController.getBillingAccountInvoiceSettings";
import { buildCustomFieldInputs } from "c/estimateWizardCustomFields";

const EMPTY_LABEL = "—";

/** 2行目（アドレス行）に出す請求アカウント項目 */
const ADDRESS_FIELD_APIS = new Set([
  "BillingAddressee__c",
  "BillingEmailTo__c",
  "BillingEmailCc__c",
  "BillingEmailBcc__c"
]);

/** 仕様: Core 第5.2節 */
export default class OrderCreateStepBilling extends NavigationMixin(
  LightningElement
) {
  @api context;

  _billingCustomFields = {};
  _pendingBillingCustomFields = null;
  _wiredFieldDefinitions;
  _wiredBillingAccountInvoiceSettings;

  fieldDefinitions = [];

  connectedCallback() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    Promise.resolve().then(() => {
      this.refreshReferenceWires();
    });
  }

  /**
   * 請求項目定義・請求アカウント設定をサーバ最新で取り直す。
   */
  @api
  refreshReferenceWires() {
    const jobs = [];
    if (this._wiredFieldDefinitions) {
      jobs.push(refreshApex(this._wiredFieldDefinitions));
    }
    if (this._wiredBillingAccountInvoiceSettings) {
      jobs.push(refreshApex(this._wiredBillingAccountInvoiceSettings));
    }
    if (this.billingAccountId) {
      getRecordNotifyChange([{ recordId: this.billingAccountId }]);
    }
    return Promise.all(jobs);
  }

  @api
  get billingCustomFields() {
    return this._billingCustomFields;
  }

  set billingCustomFields(value) {
    const nextValues = value ? { ...value } : {};
    if (this.fieldDefinitions.length === 0) {
      this._pendingBillingCustomFields = nextValues;
      return;
    }
    this._billingCustomFields = this.mergeBillingCustomFields(nextValues);
    this._pendingBillingCustomFields = null;
  }

  @api
  getBillingCustomFields() {
    return this.buildCompleteBillingCustomFields();
  }

  /**
   * 仕様: Core 第5.2節。必須不足時は請求アカウントの正規編集画面へ誘導する。
   */
  @api
  openBillingAccountFormalEdit() {
    const recordId = this.billingAccountId;
    if (!recordId) {
      return false;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId,
        objectApiName: "BillingAccount__c",
        actionName: "edit"
      }
    });
    return true;
  }

  handleOpenFormalEdit() {
    this.openBillingAccountFormalEdit();
  }

  /** 仕様: Core 第5.2節 */
  @api
  validateBillingFields() {
    const missingLabels = [];
    for (const field of this.fieldDefinitions) {
      if (!field.required) {
        continue;
      }
      const value = this.resolveBillingFieldValue(
        field.apiName,
        field.fieldType
      );
      if (this.isMissingBillingFieldValue(field.fieldType, value)) {
        missingLabels.push(field.label);
      }
    }
    if (missingLabels.length === 0) {
      return null;
    }
    return (
      "請求アカウントの必須項目が未設定です。請求アカウントの正規編集画面で設定してください: " +
      missingLabels.join("、")
    );
  }

  buildCompleteBillingCustomFields() {
    const values = { ...this._billingCustomFields };
    for (const field of this.fieldDefinitions) {
      if (Object.prototype.hasOwnProperty.call(values, field.apiName)) {
        continue;
      }
      values[field.apiName] = field.fieldType === "BOOLEAN" ? false : "";
    }
    return values;
  }

  resolveBillingFieldValue(fieldApiName, fieldType) {
    if (
      Object.prototype.hasOwnProperty.call(
        this._billingCustomFields,
        fieldApiName
      )
    ) {
      return this._billingCustomFields[fieldApiName];
    }
    return fieldType === "BOOLEAN" ? false : "";
  }

  isMissingBillingFieldValue(fieldType, value) {
    if (fieldType === "BOOLEAN") {
      return false;
    }
    if (value === null || value === undefined) {
      return true;
    }
    return String(value).trim() === "";
  }

  @wire(getOrderBillingFieldDefinitions)
  wiredFieldDefinitions(result) {
    this._wiredFieldDefinitions = result;
    const { data } = result;
    if (!data) {
      return;
    }
    this.fieldDefinitions = data;
    const baseValues =
      this._pendingBillingCustomFields || this._billingCustomFields;
    this._billingCustomFields = this.mergeBillingCustomFields(baseValues);
    this._pendingBillingCustomFields = null;
    this.applyBillingSettingsFallback(this.context?.billingSettings);
  }

  get billingAccountId() {
    return this.context?.billingAccountId || null;
  }

  @wire(getBillingAccountInvoiceSettings, {
    billingAccountId: "$billingAccountId"
  })
  wiredBillingAccountInvoiceSettings(result) {
    this._wiredBillingAccountInvoiceSettings = result;
    const { data } = result;
    if (!data || !this.fieldDefinitions.length) {
      return;
    }
    this.applyBillingSettingsFallback(data);
  }

  applyBillingSettingsFallback(invoiceSettings) {
    if (!invoiceSettings) {
      return;
    }
    this._billingCustomFields = this.mergeBillingCustomFields(
      this._billingCustomFields,
      invoiceSettings
    );
  }

  // 仕様: Core 第5.2節。正規編集後は請求アカウントの最新を載せる。
  mergeBillingCustomFields(baseValues = {}, invoiceSettings = null) {
    const merged = { ...(baseValues || {}) };
    const incoming = invoiceSettings?.billingCustomFields;
    if (incoming && typeof incoming === "object") {
      Object.keys(incoming).forEach((key) => {
        merged[key] = incoming[key];
      });
    }
    return merged;
  }

  isBlankPicklistValue(value) {
    return value === null || value === undefined || String(value).trim() === "";
  }

  get hasBillingAccount() {
    return Boolean(this.context?.billingAccountId);
  }

  get billingCustomerAccountName() {
    return this.context?.billingCustomerAccountName || EMPTY_LABEL;
  }

  get billingAccountName() {
    return this.context?.billingAccountName || EMPTY_LABEL;
  }

  get billingFieldInputs() {
    return buildCustomFieldInputs(
      this.fieldDefinitions,
      this._billingCustomFields,
      "order-billing",
      true
    ).map((field) => ({
      ...field,
      displayValue: this.formatDisplayValue(field.displayValue),
      labelClass: field.required ? "est-label est-label_required" : "est-label"
    }));
  }

  get otherFieldInputs() {
    return this.billingFieldInputs.filter(
      (field) => !ADDRESS_FIELD_APIS.has(field.apiName)
    );
  }

  get addressFieldInputs() {
    return this.billingFieldInputs.filter((field) =>
      ADDRESS_FIELD_APIS.has(field.apiName)
    );
  }

  formatDisplayValue(value) {
    if (value === null || value === undefined) {
      return EMPTY_LABEL;
    }
    const text = String(value).trim();
    return text === "" ? EMPTY_LABEL : text;
  }
}
