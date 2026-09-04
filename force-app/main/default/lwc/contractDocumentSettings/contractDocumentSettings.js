import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSettings from '@salesforce/apex/ContractDocumentSettingsController.getSettings';
import saveSettings from '@salesforce/apex/ContractDocumentSettingsController.saveSettings';
import issueOrgSettingsOperationKey from '@salesforce/apex/ContractDocumentSettingsController.issueOrgSettingsOperationKey';
import validateFieldCopyDefinitions from '@salesforce/apex/ContractDocumentSettingsController.validateFieldCopyDefinitions';
import hasOrgSettings from '@salesforce/customPermission/Loop_20_Can_OrgSettings';

const EMPTY_OPTION = { label: '（未設定）', value: '' };
// 仕様: Core 第11.6節・第4.3.12節。ContractOptimisticLockUtil.CONFLICT_MESSAGE と同一。
const VERSION_CONFLICT_MESSAGE =
  '他のユーザーが先に更新しました。画面を開き直してから再度操作してください。';
const SEND_MODE_OPTIONS = [
  { label: '使わない', value: 'Unused' },
  { label: 'PDFのみ', value: 'PdfOnly' },
  { label: 'PDFとメール送付', value: 'PdfAndEmail' }
];
const REVENUE_RECOGNITION_BASIS_OPTIONS = [
  { label: '請求基準', value: 'BillingBasis' },
  { label: '入金連動前受基準', value: 'CashBasis' }
];
const TAX_RECOGNITION_TIMING_OPTIONS = [
  { label: '請求時', value: 'AtInvoice' },
  { label: '売上計上時', value: 'AtRecognition' }
];
const MONTHLY_BUCKET_METHOD_OPTIONS = [
  { label: '自動', value: 'Auto' },
  { label: '契約日アンカー', value: 'ContractAnchor' },
  { label: '暦月', value: 'CalendarMonth' }
];
const MONTHLY_RECOGNITION_DATE_POSITION_OPTIONS = [
  { label: 'バケット開始日', value: 'BucketStart' },
  { label: 'バケット終了日', value: 'BucketEnd' },
  { label: '終了日所属月の末日', value: 'MonthEnd' }
];
const ROUNDING_TARGET_BUCKET_OPTIONS = [
  { label: '最終バケット', value: 'Last' },
  { label: '初回バケット', value: 'First' }
];
const TAX_ROUNDING_MODE_OPTIONS = [
  { label: '0方向切捨て', value: 'DOWN' },
  { label: '四捨五入', value: 'HALF_UP' },
  { label: '0から離れる切上げ', value: 'UP' }
];
const QUANTITY_UNIT_PRICE_ROUNDING_MODE_OPTIONS = [
  { label: '小数第2位の四捨五入', value: 'Scale2HalfUp' }
];
const AMOUNT_ROUNDING_MODE_OPTIONS = [
  { label: '整数円の四捨五入', value: 'Scale0HalfUp' }
];
const TAX_LINE_ALLOCATION_METHOD_OPTIONS = [
  { label: '符号付き最大剰余', value: 'SignedLargestRemainder' }
];
const ALLOCATION_TIE_BREAK_OPTIONS = [
  { label: '請求明細の安定順', value: 'InvoiceLineStableOrder' }
];
const MONTHLY_BUCKET_AMOUNT_METHOD_OPTIONS = [
  { label: '均等割り', value: 'EqualSplit' }
];
const TAX_SCHEDULE_ALLOCATION_METHOD_OPTIONS = [
  { label: '符号付き売上比', value: 'SignedRevenueRatio' }
];
const PAYMENT_LINE_ALLOCATION_METHOD_OPTIONS = [
  { label: '未処理税込の比例', value: 'OpenInclusiveRatio' }
];
const ACCOUNT_BALANCE_ALLOCATION_METHOD_OPTIONS = [
  { label: '同じ率', value: 'SameRate' }
];
const DOCUMENT_GROUP_TAX_ALLOCATION_METHOD_OPTIONS = [
  { label: '税抜比、最後のグループで吸収', value: 'ExclusiveRatioLastAbsorbs' }
];

export default class ContractDocumentSettings extends LightningElement {
  settings = {};
  sendModeOptions = SEND_MODE_OPTIONS;
  revenueRecognitionBasisOptions = REVENUE_RECOGNITION_BASIS_OPTIONS;
  taxRecognitionTimingOptions = TAX_RECOGNITION_TIMING_OPTIONS;
  monthlyBucketMethodOptions = MONTHLY_BUCKET_METHOD_OPTIONS;
  monthlyRecognitionDatePositionOptions = MONTHLY_RECOGNITION_DATE_POSITION_OPTIONS;
  roundingTargetBucketOptions = ROUNDING_TARGET_BUCKET_OPTIONS;
  taxRoundingModeOptions = TAX_ROUNDING_MODE_OPTIONS;
  quantityUnitPriceRoundingModeOptions = QUANTITY_UNIT_PRICE_ROUNDING_MODE_OPTIONS;
  amountRoundingModeOptions = AMOUNT_ROUNDING_MODE_OPTIONS;
  taxLineAllocationMethodOptions = TAX_LINE_ALLOCATION_METHOD_OPTIONS;
  allocationTieBreakOptions = ALLOCATION_TIE_BREAK_OPTIONS;
  monthlyBucketAmountMethodOptions = MONTHLY_BUCKET_AMOUNT_METHOD_OPTIONS;
  taxScheduleAllocationMethodOptions = TAX_SCHEDULE_ALLOCATION_METHOD_OPTIONS;
  paymentLineAllocationMethodOptions = PAYMENT_LINE_ALLOCATION_METHOD_OPTIONS;
  accountBalanceAllocationMethodOptions = ACCOUNT_BALANCE_ALLOCATION_METHOD_OPTIONS;
  documentGroupTaxAllocationMethodOptions = DOCUMENT_GROUP_TAX_ALLOCATION_METHOD_OPTIONS;
  estimateDocumentTemplates = [EMPTY_OPTION];
  invoiceDocumentTemplates = [EMPTY_OPTION];
  estimateEmailTemplates = [EMPTY_OPTION];
  invoiceEmailTemplates = [EMPTY_OPTION];
  orgWideEmailAddresses = [EMPTY_OPTION];
  diagnoses = [];
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

  /** 仕様: Core 第11.3.2節。PDF利用時は既定帳票必須。 */
  get estimateDefaultDocumentRequired() {
    return this.usesPdfSendMode(this.settings?.estimateSendMode);
  }

  get invoiceDefaultDocumentRequired() {
    return this.usesPdfSendMode(this.settings?.invoiceSendMode);
  }

  /** 仕様: Core 第11.3.2節。PDFとメール送付のとき既定メール必須。 */
  get estimateDefaultEmailRequired() {
    return this.settings?.estimateSendMode === "PdfAndEmail";
  }

  get invoiceDefaultEmailRequired() {
    return this.settings?.invoiceSendMode === "PdfAndEmail";
  }

  /** 仕様: Core 第11.3.2節。請求がPDFとメール送付なら請求用組織送信元必須。 */
  get invoiceOrgWideRequired() {
    return this.settings?.invoiceSendMode === "PdfAndEmail";
  }

  get documentDiagnoses() {
    return this.diagnosesFor("帳票・送付");
  }

  get contractDiagnoses() {
    return this.diagnosesFor("契約");
  }

  get amountDiagnoses() {
    return this.diagnosesFor("金額計算");
  }

  get policyDiagnoses() {
    return this.diagnosesFor("Accounting方針");
  }

  get inputDiagnoses() {
    return this.diagnosesFor("入力");
  }

  get systemDiagnoses() {
    return this.diagnosesFor("システム");
  }

  diagnosesFor(heading) {
    return (this.diagnoses || []).filter((row) => row.heading === heading);
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

  // 仕様: Core 第11.9節
  get amountCalculationWarning() {
    return "会社設定を後から変えても、保存済みの見積金額、請求税額、AllocatedTaxAmount__c、入出金割当、仕訳金額は再計算しません。これから行う計算だけが新しい設定を見ます。";
  }

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      const result = await getSettings();
      this.settings = { ...result.settings };
      this.estimateDocumentTemplates = [
        EMPTY_OPTION,
        ...(result.estimateDocumentTemplates || [])
      ];
      this.invoiceDocumentTemplates = [
        EMPTY_OPTION,
        ...(result.invoiceDocumentTemplates || [])
      ];
      this.estimateEmailTemplates = [
        EMPTY_OPTION,
        ...(result.estimateEmailTemplates || [])
      ];
      this.invoiceEmailTemplates = [
        EMPTY_OPTION,
        ...(result.invoiceEmailTemplates || [])
      ];
      this.orgWideEmailAddresses = [
        EMPTY_OPTION,
        ...(result.orgWideEmailAddresses || [])
      ];
      this.diagnoses = result.diagnoses || [];
    } catch (error) {
      this.toast('読込エラー', this.message(error), 'error');
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
    if (type === 'checkbox') {
      nextValue = event.target.checked;
    } else if (type === 'number') {
      const raw = detailValue !== undefined ? detailValue : event.target.value;
      nextValue = raw === '' || raw == null ? null : Number(raw);
    } else {
      nextValue = detailValue !== undefined ? detailValue : event.target.value;
    }
    this.settings = {
      ...this.settings,
      [name]: nextValue
    };
  }

  async handleValidateFieldCopy() {
    this.loading = true;
    try {
      const message = await validateFieldCopyDefinitions();
      this.toast('検証完了', message, 'success');
    } catch (error) {
      this.toast('検証エラー', this.message(error), 'error');
    } finally {
      this.loading = false;
    }
  }

  async handleSave() {
    this.applyNamedFieldValues();
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
      this.toast('保存完了', this.saveSuccessMessage, 'success');
    } catch (error) {
      const msg = this.message(error);
      this.toast('保存エラー', msg, 'error');
      // 仕様: Core 第11.6節・第4.3.12節。版比較失敗時は画面を読み直す。
      if (msg === VERSION_CONFLICT_MESSAGE) {
        this._pendingOperationKey = "";
        await this.load();
      }
    } finally {
      this.loading = false;
    }
  }

  /** 仕様: Core 第11.6節。画面に出ている値を保存対象にする。 */
  applyNamedFieldValues() {
    const next = { ...this.settings };
    this.template
      .querySelectorAll(
        'lightning-input, lightning-textarea, lightning-combobox'
      )
      .forEach((element) => {
        const name = element.name;
        if (!name) {
          return;
        }
        if (element.type === 'checkbox') {
          next[name] = element.checked;
          return;
        }
        const raw = element.value;
        if (element.type === 'number') {
          next[name] = raw === '' || raw == null ? null : Number(raw);
          return;
        }
        next[name] = raw;
      });
    this.settings = next;
  }

  /** 仕様: Core 第11.3.1節、第11.3.2節、第1.1.10節。必須空は画面で止める。空白のみは空。 */
  reportValidity() {
    this.applyRequiredFieldValidity();
    return [...this.template.querySelectorAll('lightning-input, lightning-textarea, lightning-combobox')]
      .reduce((valid, component) => {
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
      "estimateDefaultDocumentTemplateKey",
      this.estimateDefaultDocumentRequired,
      "PDFのみ／PDFとメール送付のとき、既定帳票を選んでください。"
    );
    this.setRequiredBlankValidity(
      "invoiceDefaultDocumentTemplateKey",
      this.invoiceDefaultDocumentRequired,
      "PDFのみ／PDFとメール送付のとき、既定帳票を選んでください。"
    );
    this.setRequiredBlankValidity(
      "estimateDefaultEmailTemplateApiName",
      this.estimateDefaultEmailRequired,
      "PDFとメール送付のとき、既定メールをカタログから選んでください。"
    );
    this.setRequiredBlankValidity(
      "invoiceDefaultEmailTemplateApiName",
      this.invoiceDefaultEmailRequired,
      "PDFとメール送付のとき、既定メールをカタログから選んでください。"
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
    return error?.body?.message || error?.message || '予期しないエラーが発生しました。';
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
