import { LightningElement, api } from "lwc";

const VARIANT_ERROR = "error";
const VARIANT_CONFIRM = "confirm";

export default class EstimateValidationAlert extends LightningElement {
  @api title = "";
  @api messages = [];
  @api compact = false;
  @api variant = VARIANT_ERROR;
  @api showActions = false;

  get hasTitle() {
    return Boolean(this.title && String(this.title).trim());
  }

  get alertClass() {
    const tone =
      this.variant === VARIANT_CONFIRM
        ? "est-alert_confirm"
        : "est-alert_error";
    let css = `est-alert ${tone}`;
    if (this.compact) {
      css += " est-alert_compact";
    }
    return css;
  }

  /** 仕様: Core 第4.3.6節 */
  get isConfirmVariant() {
    return this.variant === VARIANT_CONFIRM && this.showActions;
  }

  get alertRole() {
    return this.variant === VARIANT_CONFIRM ? "status" : "alert";
  }

  get liveMode() {
    return this.variant === VARIANT_CONFIRM ? "polite" : "assertive";
  }

  handleProceed() {
    this.dispatchEvent(new CustomEvent("proceed"));
  }

  handleCancel() {
    this.dispatchEvent(new CustomEvent("cancel"));
  }
}
