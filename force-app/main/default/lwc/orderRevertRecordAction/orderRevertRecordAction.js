import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'c/orderWizardNavigation';
import hasRevert from '@salesforce/customPermission/Contract_10_Can_Revert';
import {
    closeOrderRecordAction,
    markOrderRecordForRefresh,
    refreshOnRecordActionUnmount
} from 'c/orderWizardClose';
import { resizeQuickActionPanel } from 'c/quickActionPanelResize';

export default class OrderRevertRecordAction extends NavigationMixin(
    LightningElement
) {
    @api recordId;

    pendingRecordRefresh;

    get hasPermission() {
        return hasRevert === true;
    }

    connectedCallback() {
        resizeQuickActionPanel(this, 'confirm');
    }

    renderedCallback() {
        resizeQuickActionPanel(this, 'confirm');
    }

    handleRequestClose(event) {
        const detail = event.detail || {};
        closeOrderRecordAction(this, {
            refresh: detail.refresh !== false,
            recordId: detail.recordId || this.recordId
        });
    }

    handleOrderRecordStatusChanged(event) {
        markOrderRecordForRefresh(this, event.detail?.recordId);
    }

    disconnectedCallback() {
        refreshOnRecordActionUnmount(this);
    }
}
