import { LightningElement, api, wire } from "lwc";
import {
  getRecord,
  getFieldValue,
  getRecordNotifyChange
} from "lightning/uiRecordApi";
import OPP_NAME_FIELD from "@salesforce/schema/Opportunity.Name";
import ACCOUNT_NAME_FIELD from "@salesforce/schema/Opportunity.Account.Name";
import OPP_CONTACT_ID_FIELD from "@salesforce/schema/Opportunity.ContactId";

// 仕様: Core 第0.1節。見積種別の画面表示名。保存値は New／Change／Renew／Cancel。
const TYPE_OPTIONS = [
  { value: "New", label: "新規" },
  { value: "Change", label: "追加変更" },
  { value: "Renew", label: "更新" },
  { value: "Cancel", label: "解約" }
];

/**
 * Step1 基本情報: 取引先名｜商談名｜種別。
 * 仕様: Core 第4.3.3節・第0.1節。種別は商談名の右に均等幅の角丸ボタン。
 */
export default class EstimateCreateModal1 extends LightningElement {
  @api recordId;
  @api selectedType = "";
  @api entryMode = "";
  @api serviceLifecycle = "";
  @api opportunityName = "";
  @api accountName = "";
  @api readOnly = false;

  connectedCallback() {
    if (this.recordId) {
      getRecordNotifyChange([{ recordId: this.recordId }]);
    }
  }

  get accountNameDisplay() {
    return this.accountName || "—";
  }

  get opportunityNameDisplay() {
    return this.opportunityName || "—";
  }

  /** 仕様: Core 第4.3.3節・第0.1節。新規／追加変更／更新／解約。編集時は変更できない。 */
  get typeOptions() {
    return TYPE_OPTIONS.map((option) => {
      const selected = this.selectedType === option.value;
      return {
        ...option,
        selected,
        pressed: selected ? "true" : "false",
        disabled: this.readOnly === true,
        buttonClass: selected
          ? "est-type-btn est-type-btn_active"
          : this.readOnly
            ? "est-type-btn est-type-btn_locked"
            : "est-type-btn"
      };
    });
  }

  @wire(getRecord, {
    recordId: "$recordId",
    fields: [OPP_NAME_FIELD, ACCOUNT_NAME_FIELD, OPP_CONTACT_ID_FIELD]
  })
  wiredOpportunity({ data }) {
    if (!data) {
      return;
    }
    const opportunityName = getFieldValue(data, OPP_NAME_FIELD) || "";
    const accountName = getFieldValue(data, ACCOUNT_NAME_FIELD) || "";
    const opportunityContactId =
      getFieldValue(data, OPP_CONTACT_ID_FIELD) || "";
    if (!opportunityName && !accountName && !opportunityContactId) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("opportunityloaded", {
        detail: { opportunityName, accountName, opportunityContactId }
      })
    );
  }

  handleTypeSelect(event) {
    if (this.readOnly) {
      return;
    }
    const selectedType = event.currentTarget.dataset.type;
    if (!selectedType) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("typechange", {
        detail: { selectedType }
      })
    );
  }
}
