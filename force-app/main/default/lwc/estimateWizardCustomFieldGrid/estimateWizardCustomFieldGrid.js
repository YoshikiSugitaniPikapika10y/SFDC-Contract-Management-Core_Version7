import { LightningElement, api } from "lwc";

export default class EstimateWizardCustomFieldGrid extends LightningElement {
  @api fields = [];
  @api fieldTarget = "";
  /** When true, use table-cell font size (matches Step3 請求設定). */
  @api dense = false;

  get gridClass() {
    return this.dense
      ? "est-custom-grid est-custom-grid_dense"
      : "est-custom-grid";
  }

  get textareaRows() {
    return this.dense ? "2" : "4";
  }

  handleFieldChange(event) {
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
