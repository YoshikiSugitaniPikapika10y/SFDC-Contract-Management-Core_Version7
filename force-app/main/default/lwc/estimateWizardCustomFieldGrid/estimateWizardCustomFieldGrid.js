import { LightningElement, api } from "lwc";

/** User は表示項目と検索項目を渡さないと record-picker が設定エラーになる。 */
const USER_DISPLAY_INFO = {
  primaryField: "Name",
  additionalFields: ["Email"]
};
const USER_MATCHING_INFO = {
  primaryField: { fieldPath: "Name" },
  additionalFields: [{ fieldPath: "Email" }]
};

export default class EstimateWizardCustomFieldGrid extends LightningElement {
  @api fields = [];
  @api fieldTarget = "";
  /** When true, use table-cell font size (matches Step3 請求設定). */
  @api dense = false;
  @api disabled = false;

  get gridClass() {
    return this.dense
      ? "est-custom-grid est-custom-grid_dense"
      : "est-custom-grid";
  }

  get textareaRows() {
    return this.dense ? "2" : "4";
  }

  get viewFields() {
    return (this.fields || []).map((field) => {
      if (field && field.referenceObjectApiName === "User") {
        return {
          ...field,
          displayInfo: USER_DISPLAY_INFO,
          matchingInfo: USER_MATCHING_INFO
        };
      }
      return field;
    });
  }

  handleFieldChange(event) {
    if (this.disabled) {
      return;
    }
    const fieldApi = event.currentTarget.dataset.field;
    const fieldDef = this.fields.find((field) => field.apiName === fieldApi);
    if (!fieldDef) {
      return;
    }

    let value;
    if (fieldDef.fieldType === "BOOLEAN") {
      value = event.target.checked;
    } else if (fieldDef.fieldType === "REFERENCE") {
      value = event.detail?.recordId || "";
    } else if (
      event.detail &&
      Object.prototype.hasOwnProperty.call(event.detail, "value")
    ) {
      value = event.detail.value;
    } else {
      value = event.target.value;
    }

    this.dispatchEvent(
      new CustomEvent("customfieldchange", {
        bubbles: true,
        composed: true,
        detail: {
          fieldTarget: this.fieldTarget,
          fieldApi,
          value
        }
      })
    );
  }
}
