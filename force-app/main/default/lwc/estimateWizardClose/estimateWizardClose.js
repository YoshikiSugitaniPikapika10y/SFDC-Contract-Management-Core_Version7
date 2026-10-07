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

// 仕様: Core 第4.3.2節・第4.3.6節。保存成功後は確認せず閉じる。
// 開いたまま再読込すると Quick Action が作り直され、初期状態の Step 1 が残る。
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
    markEstimateRecordForRefresh(
      component,
      contractHistoryId || opportunityId || component.recordId
    );
    component.pendingRelatedRefresh = { opportunityId, contractHistoryId };
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
  if (host.pendingRelatedRefresh) {
    const related = host.pendingRelatedRefresh;
    host.pendingRelatedRefresh = null;
    host.pendingRecordRefresh = null;
    refreshEstimateRelatedRecords(host, related);
    return;
  }
  if (!host.pendingRecordRefresh) {
    return;
  }
  getRecordNotifyChange([{ recordId: host.pendingRecordRefresh }]);
  host.dispatchEvent(new RefreshEvent());
}
