import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from 'lightning/refresh';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';

export function refreshEstimateRelatedRecords(
    component,
    { opportunityId, contractHistoryId } = {}
) {
    const records = [];
    if (opportunityId) {
        records.push({ recordId: opportunityId });
    }
    if (contractHistoryId) {
        records.push({ recordId: contractHistoryId });
    }
    if (records.length) {
        getRecordNotifyChange(records);
    }
    component.dispatchEvent(new RefreshEvent());
}

export function closeEstimateWizard(
    component,
    { refresh = true, opportunityId, contractHistoryId } = {}
) {
    if (refresh) {
        refreshEstimateRelatedRecords(component, {
            opportunityId,
            contractHistoryId
        });
    }
    component.dispatchEvent(new CloseActionScreenEvent());
}

export function requestEstimateWizardClose(component, detail = {}) {
    component.dispatchEvent(
        new CustomEvent('requestclose', {
            bubbles: true,
            composed: true,
            detail
        })
    );
}

export function markEstimateRecordForRefresh(host, recordId) {
    host.pendingRecordRefresh = recordId || host.recordId;
}

export function refreshOnEstimateRecordActionUnmount(host) {
    if (!host.pendingRecordRefresh) {
        return;
    }
    getRecordNotifyChange([{ recordId: host.pendingRecordRefresh }]);
    host.dispatchEvent(new RefreshEvent());
}