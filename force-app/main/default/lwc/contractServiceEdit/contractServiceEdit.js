import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import getContext from "@salesforce/apex/ContractServiceEditController.getContext";
import save from "@salesforce/apex/ContractServiceEditController.save";
import issueContractServiceOperationKey from "@salesforce/apex/ContractServiceEditController.issueContractServiceOperationKey";
import getContractServiceFieldDefinitions from "@salesforce/apex/ContractWizardFieldService.getContractServiceFieldDefinitions";
import hasEditService from "@salesforce/customPermission/Loop_08_Can_EditService";
import {
  buildCustomFieldInputs,
  validateCustomFieldMaps
} from "c/estimateWizardCustomFields";

const TAX_CHANGE_CONFIRM =
  "次に受注または再生成する請求の税率が変わります。すでに存在する請求は変わりません。分割・移動で増える請求も、元請求の税率を引き継ぎます。未受注の見積の税込と見積書だけ、すぐに新しい税率を見ます。";

const VERSION_CONFLICT_MESSAGE =
  "他のユーザーが先に更新しました。画面を開き直してから再度操作してください。";

// 仕様: Core 第3.4.1節
export default class ContractServiceEdit extends LightningElement {
  @api recordId;

  name = "";
  billingAccountId = "";
  accountId = "";
  relatedBillingAccounts = [];
  allowOtherAccountBilling = false;
  taxPercent = null;
  customerMemo = "";
  originalTaxPercent = null;
  customFields = {};
  fieldDefinitions = [];
  loading = true;
  saving = false;
  lastModifiedToken = "";
  _pendingOperationKey = "";

  connectedCallback() {
    if (this.canEditService !== true) {
      this.loading = false;
      return;
    }
    this.loadContext();
  }

  get canEditService() {
    return hasEditService === true;
  }

  get customFieldInputs() {
    return buildCustomFieldInputs(
      this.fieldDefinitions,
      this.customFields,
      "service",
      false,
      undefined,
      undefined
    );
  }

  get hasCustomFields() {
    return this.customFieldInputs.length > 0;
  }

  // 仕様: Core 第3.4.1節・第4.3.3節。OFF時は自取引先の請求アカウントだけ。
  get billingAccountFilter() {
    if (this.allowOtherAccountBilling || !this.accountId) {
      return undefined;
    }
    return {
      criteria: [
        {
          fieldPath: "Account__c",
          operator: "eq",
          value: this.accountId
        }
      ]
    };
  }

  loadContext() {
    this.loading = true;
    Promise.all([
      getContext({ recordId: this.recordId }),
      getContractServiceFieldDefinitions()
    ])
      .then(([dto, definitions]) => {
        this.name = dto.name || "";
        this.accountId = dto.accountId || "";
        this.relatedBillingAccounts = dto.relatedBillingAccounts || [];
        this.billingAccountId = dto.billingAccountId || "";
        this.taxPercent = dto.taxPercent;
        this.originalTaxPercent = dto.taxPercent;
        this.customerMemo = dto.customerMemo || "";
        this.customFields = dto.customFields || {};
        this.fieldDefinitions = definitions || [];
        this.lastModifiedToken = dto.lastModifiedToken || "";
        this.allowOtherAccountBilling = this.isBillingOutsideRelated(
          this.billingAccountId
        );
      })
      .catch((error) => {
        this.toast("エラー", this.messageOf(error), "error");
      })
      .finally(() => {
        this.loading = false;
      });
  }

  isBillingOutsideRelated(billingAccountId) {
    if (!billingAccountId) {
      return false;
    }
    return !this.relatedBillingAccounts.some(
      (row) => row.id === billingAccountId
    );
  }

  handleNameChange(event) {
    this.name = event.target.value;
  }

  handleBillingAccountChange(event) {
    this.billingAccountId = event.detail ? event.detail.recordId : "";
  }

  // 仕様: Core 第3.4.1節。OFFへ戻すと自取引先候補外ならクリアする。
  handleAllowOtherAccountBillingChange(event) {
    const allowOther = event.target.checked === true;
    this.allowOtherAccountBilling = allowOther;
    if (!allowOther && this.isBillingOutsideRelated(this.billingAccountId)) {
      this.billingAccountId = "";
    }
  }

  handleTaxChange(event) {
    const raw = event.target.value;
    this.taxPercent = raw === "" || raw == null ? null : Number(raw);
  }

  handleMemoChange(event) {
    this.customerMemo = event.target.value;
  }

  handleCustomFieldChange(event) {
    const { fieldApi, value } = event.detail || {};
    if (!fieldApi) {
      return;
    }
    this.customFields = {
      ...this.customFields,
      [fieldApi]: value
    };
  }

  handleCancel() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  taxChanged() {
    if (this.originalTaxPercent == null) {
      return this.taxPercent != null;
    }
    if (this.taxPercent == null) {
      return true;
    }
    return Number(this.originalTaxPercent) !== Number(this.taxPercent);
  }

  // 仕様: Core 第4.6節・第1.1.10節。空欄拒否は第3.4.1節。
  validateDisplayTaxPercent(taxPercent) {
    if (taxPercent === "" || taxPercent == null) {
      return null;
    }
    const numeric = Number(taxPercent);
    if (!Number.isFinite(numeric)) {
      return "消費税率が不正です。";
    }
    if (numeric < 0) {
      return "消費税率が不正です（負の値は指定できません）。";
    }
    if (numeric > 0 && numeric < 1) {
      return "消費税率は0〜100のパーセント値で入力してください。";
    }
    if (numeric > 100) {
      return "消費税率が不正です（100を超える値は指定できません）。";
    }
    return null;
  }

  // 仕様: Core 第3.4.1節・第1.1.10節。空欄は推測して埋めない。画面で止める。
  async handleSave() {
    if (this.saving) {
      return;
    }
    if (!this.name || String(this.name).trim() === "") {
      this.toast("エラー", "名前を入力してください。", "error");
      return;
    }
    if (!this.billingAccountId) {
      this.toast("エラー", "請求アカウントを入力してください。", "error");
      return;
    }
    if (this.taxPercent === "" || this.taxPercent == null) {
      this.toast("エラー", "税率を入力してください。", "error");
      return;
    }
    const customError = validateCustomFieldMaps(
      this.fieldDefinitions,
      this.customFields,
      "契約サービス"
    );
    if (customError) {
      this.toast("エラー", customError, "error");
      return;
    }
    const taxError = this.validateDisplayTaxPercent(this.taxPercent);
    if (taxError) {
      this.toast("エラー", taxError, "error");
      return;
    }
    if (this.taxChanged()) {
      if (!window.confirm(TAX_CHANGE_CONFIRM)) {
        return;
      }
    }
    this.saving = true;
    try {
      if (!this._pendingOperationKey) {
        this._pendingOperationKey = await issueContractServiceOperationKey();
      }
      const result = await save({
        recordId: this.recordId,
        name: this.name,
        billingAccountId: this.billingAccountId || null,
        taxPercent: this.taxPercent,
        customerMemo: this.customerMemo,
        customFieldsJson: JSON.stringify(this.customFields || {}),
        expectedLastModifiedToken: this.lastModifiedToken || null,
        businessOperationKey: this._pendingOperationKey
      });
      if (result?.businessOperationKey) {
        this._pendingOperationKey = result.businessOperationKey;
      }
      this._pendingOperationKey = "";
      this.toast("成功", "契約サービスを更新しました。", "success");
      this.dispatchEvent(new CloseActionScreenEvent());
    } catch (error) {
      const msg = this.messageOf(error);
      this.toast("エラー", msg, "error");
      // 仕様: Core 第3.4.1節・第4.3.12節。版比較失敗時は画面を読み直す。
      if (msg === VERSION_CONFLICT_MESSAGE) {
        this._pendingOperationKey = "";
        this.loadContext();
      }
    } finally {
      this.saving = false;
    }
  }

  messageOf(error) {
    return (
      (error && error.body && error.body.message) ||
      error.message ||
      "処理に失敗しました。"
    );
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
