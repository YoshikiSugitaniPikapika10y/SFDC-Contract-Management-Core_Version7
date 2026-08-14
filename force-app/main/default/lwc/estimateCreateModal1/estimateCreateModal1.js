import { LightningElement, api, wire } from "lwc";
import {
  getRecord,
  getFieldValue,
  getRecordNotifyChange
} from "lightning/uiRecordApi";
import OPP_NAME_FIELD from "@salesforce/schema/Opportunity.Name";
import ACCOUNT_NAME_FIELD from "@salesforce/schema/Opportunity.Account.Name";

const ENTRY_NEW = "new";
const ENTRY_CONTINUATION = "continuation";

/**
 * Step1 入口: 商談メタ + 新規 / 続きの2択カード。
 * 操作（Change/Renew/Cancel/Add）は契約サービス選択後に modal2 側で選ぶ。
 */
export default class EstimateCreateModal1 extends LightningElement {
  @api recordId;
  @api selectedType = "New";
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

  get stepDescription() {
    if (this.readOnly) {
      return "商談と見積の入口を確認します。編集時は入口を変更できません。";
    }
    return "";
  }

  get accountNameDisplay() {
    return this.accountName || "—";
  }

  get opportunityNameDisplay() {
    return this.opportunityName || "—";
  }

  get isEntryNew() {
    return this.entryMode === ENTRY_NEW;
  }

  get isEntryContinuation() {
    return this.entryMode === ENTRY_CONTINUATION;
  }

  get entryOptions() {
    return [
      {
        value: ENTRY_NEW,
        label: "新規契約を作成する",
        iconName: "utility:new",
        selected: this.isEntryNew && !this.isEntryContinuation,
        pressed: this.isEntryNew && !this.isEntryContinuation ? "true" : "false"
      },
      {
        value: ENTRY_CONTINUATION,
        label: "既存契約から作成する",
        iconName: "utility:contract_doc",
        selected: this.isEntryContinuation,
        pressed: this.isEntryContinuation ? "true" : "false"
      }
    ].map((option) => ({
      ...option,
      disabled: this.readOnly === true,
      buttonClass: option.selected
        ? "est-entry-card est-entry-card_active"
        : this.readOnly
          ? "est-entry-card est-entry-card_locked"
          : "est-entry-card"
    }));
  }

  @wire(getRecord, {
    recordId: "$recordId",
    fields: [OPP_NAME_FIELD, ACCOUNT_NAME_FIELD]
  })
  wiredOpportunity({ data }) {
    if (!data) {
      return;
    }
    const opportunityName = getFieldValue(data, OPP_NAME_FIELD) || "";
    const accountName = getFieldValue(data, ACCOUNT_NAME_FIELD) || "";
    if (!opportunityName && !accountName) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("opportunityloaded", {
        detail: { opportunityName, accountName }
      })
    );
  }

  handleEntrySelect(event) {
    if (this.readOnly) {
      return;
    }
    const entryMode = event.currentTarget.dataset.entry;
    if (!entryMode) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("entrychange", {
        detail: { entryMode }
      })
    );
    if (entryMode === ENTRY_NEW) {
      this.dispatchEvent(
        new CustomEvent("typechange", {
          detail: { selectedType: "New" }
        })
      );
    }
  }
}
