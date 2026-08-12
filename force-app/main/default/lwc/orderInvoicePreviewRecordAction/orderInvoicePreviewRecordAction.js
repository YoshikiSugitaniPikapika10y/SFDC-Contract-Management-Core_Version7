import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'c/orderWizardNavigation';
import hasViewInvoicePreview from '@salesforce/customPermission/Contract_11_Can_View_Invoice_Preview';
import {
    closeOrderRecordAction,
    refreshOnRecordActionUnmount
} from 'c/orderWizardClose';
import { resizeQuickActionPanel } from 'c/quickActionPanelResize';

export default class OrderInvoicePreviewRecordAction extends NavigationMixin(
    LightningElement
) {
    @api recordId;

    pendingRecordRefresh;

    get hasPermission() {
        return hasViewInvoicePreview === true;
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
