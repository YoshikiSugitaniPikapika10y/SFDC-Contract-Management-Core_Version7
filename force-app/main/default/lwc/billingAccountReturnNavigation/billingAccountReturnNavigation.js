/** 仕様: Core 第3.3.3節。見積／受注からの正規Edit戻り先。 */
export const RETURN_TO_ORDER = "order";
export const RETURN_TO_ESTIMATE_CREATE = "estimateCreate";
export const RETURN_TO_ESTIMATE_EDIT = "estimateEdit";
export const RETURN_TO_ESTIMATE_COPY = "estimateCopy";

export const RETURN_CALLER_TARGETS = {
  [RETURN_TO_ORDER]: {
    apiName: "ContractHistory__c.Order_Process",
    objectApiName: "ContractHistory__c"
  },
  [RETURN_TO_ESTIMATE_CREATE]: {
    apiName: "Opportunity.EstimateCreate",
    objectApiName: "Opportunity"
  },
  [RETURN_TO_ESTIMATE_EDIT]: {
    apiName: "ContractHistory__c.EstimateEdit",
    objectApiName: "ContractHistory__c"
  },
  [RETURN_TO_ESTIMATE_COPY]: {
    apiName: "ContractHistory__c.EstimateCopy",
    objectApiName: "ContractHistory__c"
  }
};

/** 仕様: Core 第3.3.3節・第4.3.3節・第5.2節。呼び出し元へ戻すための Edit 遷移。 */
export function buildBillingAccountFormalEditPageRef(
  recordId,
  returnTo,
  returnRecordId
) {
  const pageRef = {
    type: "standard__recordPage",
    attributes: {
      recordId,
      objectApiName: "BillingAccount__c",
      actionName: "edit"
    }
  };
  if (returnTo && returnRecordId) {
    pageRef.state = {
      c__returnTo: returnTo,
      c__returnRecordId: returnRecordId
    };
  }
  return pageRef;
}

export function readReturnCallerFromPageRef(pageRef) {
  const state = pageRef?.state || {};
  let returnTo = state.c__returnTo || "";
  let returnRecordId = state.c__returnRecordId || "";
  if ((!returnTo || !returnRecordId) && typeof window !== "undefined") {
    try {
      const params = new URLSearchParams(window.location.search || "");
      returnTo = returnTo || params.get("c__returnTo") || "";
      returnRecordId = returnRecordId || params.get("c__returnRecordId") || "";
    } catch (e) {
      // ignore malformed URL
    }
  }
  return { returnTo, returnRecordId };
}
