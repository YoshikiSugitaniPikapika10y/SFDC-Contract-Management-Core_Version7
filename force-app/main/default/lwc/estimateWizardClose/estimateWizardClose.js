import { CloseActionScreenEvent } from "lightning/actions";
import { RefreshEvent } from "lightning/refresh";
import { getRecordNotifyChange } from "lightning/uiRecordApi";
import { getLightningBase } from "c/estimateWizardNavigation";

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

// 仕様: Core 第4.3.2節・第4.3.6節
export function closeEstimateWizard(
  component,
  {
    refresh = true,
    opportunityId,
    contractHistoryId,
    navigateToContractHistoryId
  } = {}
) {
  if (refresh) {
    refreshEstimateRelatedRecords(component, {
      opportunityId,
      contractHistoryId
    });
  }
  component.dispatchEvent(new CloseActionScreenEvent());
  scheduleOpenSavedContractHistory(navigateToContractHistoryId);
}

function scheduleOpenSavedContractHistory(recordId) {
  if (!recordId || typeof window === "undefined") {
    return;
  }
  const href = `${getLightningBase()}/lightning/r/ContractHistory__c/${recordId}/view`;
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  window.setTimeout(() => {
    window.location.href = href;
  }, 0);
}

export function requestEstimateWizardClose(component, detail = {}) {
  component.dispatchEvent(
    new CustomEvent("requestclose", {
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
