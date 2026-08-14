import { CloseActionScreenEvent } from "lightning/actions";
import { RefreshEvent } from "lightning/refresh";
import { getRecordNotifyChange } from "lightning/uiRecordApi";
import { navigateToContractHistoryRecord } from "c/orderWizardNavigation";

export const HISTORY_STATUS_ARCHIVE = "Archive";

export function refreshOrderRecordPage(component, recordId) {
  if (!recordId) {
    return;
  }
  getRecordNotifyChange([{ recordId }]);
  component.dispatchEvent(new RefreshEvent());
  scheduleOrderRecordPageRefresh(recordId);
}

export function scheduleOrderRecordPageRefresh(recordId) {
  if (!recordId || typeof window === "undefined") {
    return;
  }
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  window.setTimeout(() => {
    getRecordNotifyChange([{ recordId }]);
  }, 300);
}

export function closeOrderWizard(
  component,
  { refresh = true, recordId = null } = {}
) {
  const resolvedRecordId = recordId || component.recordId;
  if (refresh && resolvedRecordId) {
    refreshOrderRecordPage(component, resolvedRecordId);
  } else if (refresh) {
    component.dispatchEvent(new RefreshEvent());
  }
  component.dispatchEvent(new CloseActionScreenEvent());
}

export function requestOrderWizardClose(
  component,
  { refresh = true, recordId = null } = {}
) {
  component.dispatchEvent(
    new CustomEvent("requestclose", {
      bubbles: true,
      composed: true,
      detail: {
        refresh,
        recordId: recordId || component.recordId
      }
    })
  );
}

export function handleOrderModalRequestClose(modal, event) {
  const detail = event.detail || {};
  const recordId = detail.recordId || modal.recordId;
  if (detail.refresh !== false && recordId) {
    refreshOrderRecordPage(modal, recordId);
  }
  modal.close();
}

export function isOrderActionBootstrapping(component) {
  return (
    component.isLoading ||
    (!component.recordId && !component._recordActionMissingHandled)
  );
}

export function notifyOrderRecordStatusChanged(component, recordId) {
  component.dispatchEvent(
    new CustomEvent("orderrecordstatuschanged", {
      bubbles: true,
      composed: true,
      detail: { recordId: recordId || component.recordId }
    })
  );
}

export function markOrderRecordForRefresh(host, recordId) {
  host.pendingRecordRefresh = recordId || host.recordId;
}

export function refreshOnRecordActionUnmount(host) {
  if (!host.pendingRecordRefresh) {
    return;
  }
  const recordId = host.pendingRecordRefresh;
  getRecordNotifyChange([{ recordId }]);
  host.dispatchEvent(new RefreshEvent());
  scheduleOrderRecordPageRefresh(recordId);
  navigateToContractHistoryRecord(host, recordId);
}

export function closeOrderRecordAction(
  host,
  { refresh = true, recordId = null } = {}
) {
  const resolvedRecordId = recordId || host.recordId;
  closeOrderWizard(host, { refresh, recordId: resolvedRecordId });
  if (resolvedRecordId) {
    navigateToContractHistoryRecord(host, resolvedRecordId);
  }
}

/**
 * オープン／再マウント時に一度きりロード制御をリセットする。
 * 同じ recordId でも接続のたびにサーバ最新を取り直す。
 */
export function resetRecordActionLoadState(component) {
  component._loadedOrderActionRecordId = null;
  component._recordActionMissingHandled = false;
  component._recordActionLoadScheduled = false;
}

export function ensureRecordActionDataLoad(component, loadFn) {
  const recordId = component.recordId;
  if (!recordId) {
    return false;
  }
  if (component._loadedOrderActionRecordId === recordId) {
    return false;
  }
  component._loadedOrderActionRecordId = recordId;
  if (typeof loadFn === "function") {
    loadFn();
  }
  return true;
}

export function handleMissingRecordActionId(component) {
  if (component.recordId || component._loadedOrderActionRecordId) {
    return;
  }
  if (component._recordActionMissingHandled) {
    return;
  }
  component._recordActionMissingHandled = true;
  component.isLoading = false;
  if (Object.prototype.hasOwnProperty.call(component, "errorMessage")) {
    component.errorMessage = "契約履歴IDが取得できません。";
  }
}

export function scheduleRecordActionLoad(component, loadFn) {
  if (ensureRecordActionDataLoad(component, loadFn)) {
    return;
  }
  if (component._recordActionLoadScheduled) {
    return;
  }
  component._recordActionLoadScheduled = true;
  Promise.resolve()
    .then(() => {
      if (ensureRecordActionDataLoad(component, loadFn)) {
        return null;
      }
      return Promise.resolve();
    })
    .then(() => {
      component._recordActionLoadScheduled = false;
      if (ensureRecordActionDataLoad(component, loadFn)) {
        return;
      }
      handleMissingRecordActionId(component);
    });
}
