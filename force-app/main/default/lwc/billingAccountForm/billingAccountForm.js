import { LightningElement, api, track, wire } from "lwc";
import { NavigationMixin, CurrentPageReference } from "lightning/navigation";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { CloseActionScreenEvent } from "lightning/actions";
import BILLING_ACCOUNT_OBJECT from "@salesforce/schema/BillingAccount__c";
import INVOICE_DATE_METHOD_FIELD from "@salesforce/schema/BillingAccount__c.InvoiceDateMethod__c";
import INVOICE_DATE_DAY_KIND_FIELD from "@salesforce/schema/BillingAccount__c.InvoiceDateDayKind__c";
import INVOICE_DATE_DAY_OF_MONTH_FIELD from "@salesforce/schema/BillingAccount__c.InvoiceDateDayOfMonth__c";
import INVOICE_DATE_MONTH_OFFSET_FIELD from "@salesforce/schema/BillingAccount__c.InvoiceDateMonthOffset__c";
import INVOICE_DATE_DAY_OFFSET_FIELD from "@salesforce/schema/BillingAccount__c.InvoiceDateDayOffset__c";
import INVOICE_DATE_ADJUST_FIELD from "@salesforce/schema/BillingAccount__c.InvoiceDateAdjust__c";
import PAYMENT_TERM_METHOD_FIELD from "@salesforce/schema/BillingAccount__c.PaymentTermMethod__c";
import PAYMENT_TERM_DAY_KIND_FIELD from "@salesforce/schema/BillingAccount__c.PaymentTermDayKind__c";
import PAYMENT_TERM_DAY_OF_MONTH_FIELD from "@salesforce/schema/BillingAccount__c.PaymentTermDayOfMonth__c";
import PAYMENT_TERM_MONTH_OFFSET_FIELD from "@salesforce/schema/BillingAccount__c.PaymentTermMonthOffset__c";
import PAYMENT_TERM_DAY_OFFSET_FIELD from "@salesforce/schema/BillingAccount__c.PaymentTermDayOffset__c";
import PAYMENT_TERM_ADJUST_FIELD from "@salesforce/schema/BillingAccount__c.PaymentTermAdjust__c";

export const METHOD_SAME_DAY = "SameDay";
export const METHOD_ON_OR_AFTER = "OnOrAfterSpecifiedDay";
export const METHOD_MONTH_OFFSET = "MonthOffset";
export const METHOD_DAY_OFFSET = "DayOffset";
export const DAY_KIND_DAY = "Day";

export const INVOICE_DATE_FIELD_APIS = [
  "InvoiceDateMethod__c",
  "InvoiceDateAdjust__c",
  "InvoiceDateDayKind__c",
  "InvoiceDateDayOfMonth__c",
  "InvoiceDateMonthOffset__c",
  "InvoiceDateDayOffset__c"
];

export const PAYMENT_TERM_FIELD_APIS = [
  "PaymentTermMethod__c",
  "PaymentTermAdjust__c",
  "PaymentTermDayKind__c",
  "PaymentTermDayOfMonth__c",
  "PaymentTermMonthOffset__c",
  "PaymentTermDayOffset__c"
];

export const DELIVERY_FIELD_APIS = [
  "BillingAddressee__c",
  "BillingEmailTo__c",
  "BillingEmailCc__c",
  "BillingEmailBcc__c",
  "InvoiceDeliveryMethod__c"
];

const RECORD_FIELDS = [
  INVOICE_DATE_METHOD_FIELD,
  INVOICE_DATE_DAY_KIND_FIELD,
  INVOICE_DATE_DAY_OF_MONTH_FIELD,
  INVOICE_DATE_MONTH_OFFSET_FIELD,
  INVOICE_DATE_DAY_OFFSET_FIELD,
  INVOICE_DATE_ADJUST_FIELD,
  PAYMENT_TERM_METHOD_FIELD,
  PAYMENT_TERM_DAY_KIND_FIELD,
  PAYMENT_TERM_DAY_OF_MONTH_FIELD,
  PAYMENT_TERM_MONTH_OFFSET_FIELD,
  PAYMENT_TERM_DAY_OFFSET_FIELD,
  PAYMENT_TERM_ADJUST_FIELD
];

/** 仕様: Core 第7.2節。方式に入らない項目は出さない。 */
export function isInvoiceDateFieldVisible(apiName, method, dayKind) {
  if (
    apiName === "InvoiceDateMethod__c" ||
    apiName === "InvoiceDateAdjust__c"
  ) {
    return true;
  }
  if (!method) {
    return false;
  }
  if (method === METHOD_SAME_DAY) {
    return false;
  }
  if (method === METHOD_ON_OR_AFTER) {
    if (apiName === "InvoiceDateDayKind__c") {
      return true;
    }
    return apiName === "InvoiceDateDayOfMonth__c" && dayKind === DAY_KIND_DAY;
  }
  if (method === METHOD_MONTH_OFFSET) {
    if (apiName === "InvoiceDateMonthOffset__c") {
      return true;
    }
    if (apiName === "InvoiceDateDayKind__c") {
      return true;
    }
    return apiName === "InvoiceDateDayOfMonth__c" && dayKind === DAY_KIND_DAY;
  }
  if (method === METHOD_DAY_OFFSET) {
    return apiName === "InvoiceDateDayOffset__c";
  }
  return false;
}

/** 仕様: Core 第7.5節。方式に入らない項目は出さない。 */
export function isPaymentTermFieldVisible(apiName, method, dayKind) {
  if (
    apiName === "PaymentTermMethod__c" ||
    apiName === "PaymentTermAdjust__c"
  ) {
    return true;
  }
  if (!method) {
    return false;
  }
  if (method === METHOD_MONTH_OFFSET) {
    if (apiName === "PaymentTermMonthOffset__c") {
      return true;
    }
    if (apiName === "PaymentTermDayKind__c") {
      return true;
    }
    return apiName === "PaymentTermDayOfMonth__c" && dayKind === DAY_KIND_DAY;
  }
  if (method === METHOD_DAY_OFFSET) {
    return apiName === "PaymentTermDayOffset__c";
  }
  return false;
}

/** 仕様: Core 第7.2節・第7.5節。正規画面と受注確認で空にする項目は出さない。 */
export function isBillingScheduleFieldVisible(apiName, values = {}) {
  if (INVOICE_DATE_FIELD_APIS.indexOf(apiName) !== -1) {
    return isInvoiceDateFieldVisible(
      apiName,
      values.InvoiceDateMethod__c,
      values.InvoiceDateDayKind__c
    );
  }
  if (PAYMENT_TERM_FIELD_APIS.indexOf(apiName) !== -1) {
    return isPaymentTermFieldVisible(
      apiName,
      values.PaymentTermMethod__c,
      values.PaymentTermDayKind__c
    );
  }
  return true;
}

/** 仕様: Core 第7.2節・第7.5節。方式を切り替えたら入らない項目は空にする。 */
export function applyClearedScheduleFields(fields = {}) {
  const next = { ...fields };
  INVOICE_DATE_FIELD_APIS.forEach((apiName) => {
    if (
      apiName === "InvoiceDateMethod__c" ||
      apiName === "InvoiceDateAdjust__c"
    ) {
      return;
    }
    if (
      !isInvoiceDateFieldVisible(
        apiName,
        next.InvoiceDateMethod__c,
        next.InvoiceDateDayKind__c
      )
    ) {
      next[apiName] = null;
    }
  });
  PAYMENT_TERM_FIELD_APIS.forEach((apiName) => {
    if (
      apiName === "PaymentTermMethod__c" ||
      apiName === "PaymentTermAdjust__c"
    ) {
      return;
    }
    if (
      !isPaymentTermFieldVisible(
        apiName,
        next.PaymentTermMethod__c,
        next.PaymentTermDayKind__c
      )
    ) {
      next[apiName] = null;
    }
  });
  return next;
}

/** 仕様: Core 第7.2節。各方式の計算。日付例は出さない。 */
export function invoiceDateMethodHelp(method) {
  if (method === METHOD_SAME_DAY) {
    return "請求基準日をそのまま請求日とする。";
  }
  if (method === METHOD_ON_OR_AFTER) {
    return "請求基準日以後で最初に到来する指定日または月末を請求日とする。請求基準日自身が該当すれば同日とする。";
  }
  if (method === METHOD_MONTH_OFFSET) {
    return "請求基準日の属する暦月を0として、指定した月数だけ前後へ移動した月の指定日または月末を請求日とする。";
  }
  if (method === METHOD_DAY_OFFSET) {
    return "請求基準日に指定日数を加減した日を請求日とする。先行請求を表せるよう負数も許可する。";
  }
  return "";
}

/** 仕様: Core 第7.5節。各方式の計算。日付例は出さない。 */
export function paymentTermMethodHelp(method) {
  if (method === METHOD_MONTH_OFFSET) {
    return "請求日の属する暦月を0として、当月、翌月、翌々月等の指定日または月末を入金予定日とする。";
  }
  if (method === METHOD_DAY_OFFSET) {
    return "請求日に0日以上の指定日数を加えた日を入金予定日とする。0日は即日払いを表す。";
  }
  return "";
}

/** 仕様: Core 第3.3.2節。取引先の関連リスト新規の初期値。 */
export function parseDefaultFieldValues(raw) {
  if (!raw || typeof raw !== "string") {
    return {};
  }
  const parsed = {};
  raw.split(",").forEach((pair) => {
    const idx = pair.indexOf("=");
    if (idx < 1) {
      return;
    }
    const apiName = decodeURIComponent(pair.slice(0, idx).trim());
    parsed[apiName] = decodeURIComponent(pair.slice(idx + 1));
  });
  return parsed;
}

function pickFieldValue(event) {
  const raw = event.detail?.value;
  if (Array.isArray(raw)) {
    return raw.length ? raw[0] : null;
  }
  return raw === undefined ? null : raw;
}

/** 仕様: Core 第3.3.2節・第3.3.3節。New／Edit／View の正規画面。 */
export default class BillingAccountForm extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  @api objectApiName = "BillingAccount__c";

  _pageRef;
  _objectInfo;
  @track draft = {};
  @track errorMessage = "";
  isSaving = false;

  @wire(CurrentPageReference)
  wiredPageRef(pageRef) {
    this._pageRef = pageRef;
    if (!pageRef || this.recordId) {
      return;
    }
    const defaults = parseDefaultFieldValues(
      pageRef.state?.defaultFieldValues
    );
    if (Object.keys(defaults).length === 0) {
      return;
    }
    this.draft = applyClearedScheduleFields({
      ...this.draft,
      ...defaults
    });
  }

  @wire(getObjectInfo, { objectApiName: BILLING_ACCOUNT_OBJECT })
  wiredObjectInfo({ data, error }) {
    if (data) {
      this._objectInfo = data;
      return;
    }
    if (error) {
      this._objectInfo = { createable: false, updateable: false };
    }
  }

  @wire(getRecord, { recordId: "$recordId", fields: RECORD_FIELDS })
  wiredRecord({ data }) {
    if (!data) {
      return;
    }
    this.draft = applyClearedScheduleFields({
      InvoiceDateMethod__c: getFieldValue(data, INVOICE_DATE_METHOD_FIELD),
      InvoiceDateDayKind__c: getFieldValue(data, INVOICE_DATE_DAY_KIND_FIELD),
      InvoiceDateDayOfMonth__c: getFieldValue(
        data,
        INVOICE_DATE_DAY_OF_MONTH_FIELD
      ),
      InvoiceDateMonthOffset__c: getFieldValue(
        data,
        INVOICE_DATE_MONTH_OFFSET_FIELD
      ),
      InvoiceDateDayOffset__c: getFieldValue(data, INVOICE_DATE_DAY_OFFSET_FIELD),
      InvoiceDateAdjust__c: getFieldValue(data, INVOICE_DATE_ADJUST_FIELD),
      PaymentTermMethod__c: getFieldValue(data, PAYMENT_TERM_METHOD_FIELD),
      PaymentTermDayKind__c: getFieldValue(data, PAYMENT_TERM_DAY_KIND_FIELD),
      PaymentTermDayOfMonth__c: getFieldValue(
        data,
        PAYMENT_TERM_DAY_OF_MONTH_FIELD
      ),
      PaymentTermMonthOffset__c: getFieldValue(
        data,
        PAYMENT_TERM_MONTH_OFFSET_FIELD
      ),
      PaymentTermDayOffset__c: getFieldValue(data, PAYMENT_TERM_DAY_OFFSET_FIELD),
      PaymentTermAdjust__c: getFieldValue(data, PAYMENT_TERM_ADJUST_FIELD)
    });
  }

  get actionName() {
    return this._pageRef?.attributes?.actionName || "";
  }

  get isNew() {
    return !this.recordId || this.actionName === "new";
  }

  get isEdit() {
    return Boolean(this.recordId) && this.actionName === "edit";
  }

  get isView() {
    return Boolean(this.recordId) && !this.isNew && !this.isEdit;
  }

  get canCreate() {
    return Boolean(this._objectInfo?.createable);
  }

  get canUpdate() {
    if (!this._objectInfo) {
      return true;
    }
    return Boolean(this._objectInfo.updateable);
  }

  get showForm() {
    if (this.isView) {
      return true;
    }
    if (this.isNew) {
      return this.canCreate;
    }
    return this.canUpdate;
  }

  get permissionDeniedMessage() {
    if (this.isView || this.showForm) {
      return "";
    }
    if (this.isNew) {
      return "請求アカウントを作る権限がありません。";
    }
    return "請求アカウントを直す権限がありません。";
  }

  get showEditButton() {
    return this.isView && this.canUpdate;
  }

  get showHasReference() {
    return !this.isNew;
  }

  get showKeyInput() {
    return this.isNew;
  }

  get showKeyOutput() {
    return !this.isNew;
  }

  get invoiceDateHelp() {
    return invoiceDateMethodHelp(this.draft.InvoiceDateMethod__c);
  }

  get hasInvoiceDateHelp() {
    return Boolean(this.invoiceDateHelp);
  }

  get paymentTermHelp() {
    return paymentTermMethodHelp(this.draft.PaymentTermMethod__c);
  }

  get hasPaymentTermHelp() {
    return Boolean(this.paymentTermHelp);
  }

  get accountIdValue() {
    return this.draft.Account__c || null;
  }

  get showInvoiceDayKind() {
    return isInvoiceDateFieldVisible(
      "InvoiceDateDayKind__c",
      this.draft.InvoiceDateMethod__c,
      this.draft.InvoiceDateDayKind__c
    );
  }

  get showInvoiceDayOfMonth() {
    return isInvoiceDateFieldVisible(
      "InvoiceDateDayOfMonth__c",
      this.draft.InvoiceDateMethod__c,
      this.draft.InvoiceDateDayKind__c
    );
  }

  get showInvoiceMonthOffset() {
    return isInvoiceDateFieldVisible(
      "InvoiceDateMonthOffset__c",
      this.draft.InvoiceDateMethod__c,
      this.draft.InvoiceDateDayKind__c
    );
  }

  get showInvoiceDayOffset() {
    return isInvoiceDateFieldVisible(
      "InvoiceDateDayOffset__c",
      this.draft.InvoiceDateMethod__c,
      this.draft.InvoiceDateDayKind__c
    );
  }

  get showPaymentDayKind() {
    return isPaymentTermFieldVisible(
      "PaymentTermDayKind__c",
      this.draft.PaymentTermMethod__c,
      this.draft.PaymentTermDayKind__c
    );
  }

  get showPaymentDayOfMonth() {
    return isPaymentTermFieldVisible(
      "PaymentTermDayOfMonth__c",
      this.draft.PaymentTermMethod__c,
      this.draft.PaymentTermDayKind__c
    );
  }

  get showPaymentMonthOffset() {
    return isPaymentTermFieldVisible(
      "PaymentTermMonthOffset__c",
      this.draft.PaymentTermMethod__c,
      this.draft.PaymentTermDayKind__c
    );
  }

  get showPaymentDayOffset() {
    return isPaymentTermFieldVisible(
      "PaymentTermDayOffset__c",
      this.draft.PaymentTermMethod__c,
      this.draft.PaymentTermDayKind__c
    );
  }

  handleFieldChange(event) {
    if (this.isSaving) {
      return;
    }
    const fieldName = event.target.fieldName;
    if (!fieldName) {
      return;
    }
    this.draft = applyClearedScheduleFields({
      ...this.draft,
      [fieldName]: pickFieldValue(event)
    });
  }

  /** 仕様: Core 第3.3.2節。保存を止める確認ゲートは置かない。 */
  /** 仕様: Core 第4.3.12節。画面の同時押下防止は補助。 */
  handleSubmit(event) {
    event.preventDefault();
    if (this.isSaving) {
      return;
    }
    const fields = applyClearedScheduleFields({
      ...event.detail.fields,
      ...this.draft
    });
    if (!this.isNew) {
      delete fields.BillingAccountKey__c;
    }
    const form = this.template.querySelector("lightning-record-edit-form");
    if (!form) {
      return;
    }
    this.isSaving = true;
    form.submit(fields);
  }

  handleSuccess(event) {
    this.isSaving = false;
    this.errorMessage = "";
    this.dispatchEvent(new CloseActionScreenEvent());
    const recordId = event.detail.id;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId,
        objectApiName: "BillingAccount__c",
        actionName: "view"
      }
    });
  }

  handleError(event) {
    this.isSaving = false;
    const detail = event.detail;
    this.errorMessage =
      detail?.detail ||
      detail?.message ||
      detail?.output?.errors?.[0]?.message ||
      "保存できませんでした。";
  }

  handleCancel() {
    if (this.isSaving) {
      return;
    }
    this.dispatchEvent(new CloseActionScreenEvent());
    if (this.recordId) {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: this.recordId,
          objectApiName: "BillingAccount__c",
          actionName: "view"
        }
      });
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: {
        objectApiName: "BillingAccount__c",
        actionName: "home"
      }
    });
  }

  handleOpenEdit() {
    if (!this.recordId || !this.canUpdate) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: this.recordId,
        objectApiName: "BillingAccount__c",
        actionName: "edit"
      }
    });
  }
}
