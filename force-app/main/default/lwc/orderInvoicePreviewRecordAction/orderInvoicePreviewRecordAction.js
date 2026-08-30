// 仕様: Core 第7.7.0節
import { LightningElement, api } from "lwc";
import { NavigationMixin } from "c/orderWizardNavigation";
import hasViewInvoice from "@salesforce/customPermission/Loop_09_Can_ViewInvoice";
import hasEditDraftInvoice from "@salesforce/customPermission/Loop_10_Can_EditDraftInvoice";
import hasConfirmInvoice from "@salesforce/customPermission/Loop_11_Can_ConfirmInvoice";
import hasSendInvoice from "@salesforce/customPermission/Loop_12_Can_SendInvoice";
import hasInvoicePayment from "@salesforce/customPermission/Loop_13_Can_InvoicePayment";
import hasManualJournal from "@salesforce/customPermission/Loop_14_Can_ManualJournal";
import hasCancelInvoice from "@salesforce/customPermission/Loop_15_Can_CancelInvoice";
import hasLockJournalBoard from "@salesforce/customPermission/Loop_16_Can_LockJournal";
import hasUnlockJournalBoard from "@salesforce/customPermission/Loop_17_Can_UnlockJournal";
import {
  closeOrderRecordAction,
  refreshOnRecordActionUnmount
} from "c/orderWizardClose";
import { resizeQuickActionPanel } from "c/quickActionPanelResize";

export default class OrderInvoicePreviewRecordAction extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  pendingRecordRefresh;

  get hasPermission() {
    return (
      hasViewInvoice === true ||
      hasEditDraftInvoice === true ||
      hasConfirmInvoice === true ||
      hasSendInvoice === true ||
      hasInvoicePayment === true ||
      hasManualJournal === true ||
      hasCancelInvoice === true ||
      hasLockJournalBoard === true ||
      hasUnlockJournalBoard === true
    );
  }

  connectedCallback() {
    resizeQuickActionPanel(this);
  }

  renderedCallback() {
    resizeQuickActionPanel(this);
  }

  handleRequestClose(event) {
    const detail = event.detail || {};
    closeOrderRecordAction(this, {
      refresh: detail.refresh !== false,
      recordId: detail.recordId || this.recordId
    });
  }

  disconnectedCallback() {
    refreshOnRecordActionUnmount(this);
  }
}
