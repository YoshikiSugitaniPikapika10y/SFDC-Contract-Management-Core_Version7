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

/** Lightning の record Edit は custom state を落とすことがあるため、開き直し用に控える。 */
const RETURN_STORAGE_KEY = "c.billingAccountFormalEdit.returnCaller";

export function rememberReturnCaller(
  returnTo,
  returnRecordId,
  billingAccountId = ""
) {
  if (typeof sessionStorage === "undefined") {
    return;
  }
  if (!returnTo || !returnRecordId) {
    sessionStorage.removeItem(RETURN_STORAGE_KEY);
    return;
  }
  sessionStorage.setItem(
    RETURN_STORAGE_KEY,
    JSON.stringify({ returnTo, returnRecordId, billingAccountId })
  );
}

function consumeRememberedReturnCaller() {
  if (typeof sessionStorage === "undefined") {
    return { returnTo: "", returnRecordId: "", billingAccountId: "" };
  }
  try {
    const raw = sessionStorage.getItem(RETURN_STORAGE_KEY);
    sessionStorage.removeItem(RETURN_STORAGE_KEY);
    if (!raw) {
      return { returnTo: "", returnRecordId: "", billingAccountId: "" };
    }
    const parsed = JSON.parse(raw);
    return {
      returnTo: parsed.returnTo || "",
      returnRecordId: parsed.returnRecordId || "",
      billingAccountId: parsed.billingAccountId || ""
    };
  } catch (e) {
    sessionStorage.removeItem(RETURN_STORAGE_KEY);
    return { returnTo: "", returnRecordId: "", billingAccountId: "" };
  }
}

export function consumeReturnCaller() {
  const remembered = consumeRememberedReturnCaller();
  return {
    returnTo: remembered.returnTo,
    returnRecordId: remembered.returnRecordId
  };
}

function clearRememberedReturnCaller() {
  if (typeof sessionStorage === "undefined") {
    return;
  }
  sessionStorage.removeItem(RETURN_STORAGE_KEY);
}

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
    // 仕様: Core 第3.3.3節。record Edit の state 欠落に備えて控えを残す。
    rememberReturnCaller(returnTo, returnRecordId, recordId);
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

/**
 * 仕様: Core 第3.3.3節。
 * @api → pageRef/URL → sessionStorage の順。pageRef で取れたら控えは捨てる。
 */
export function resolveReturnCaller({
  returnTo = "",
  returnRecordId = "",
  pageRef = null,
  billingAccountId = ""
} = {}) {
  const fromPage = readReturnCallerFromPageRef(pageRef);
  const resolvedTo = returnTo || fromPage.returnTo;
  const resolvedId = returnRecordId || fromPage.returnRecordId;
  if (resolvedTo && resolvedId) {
    clearRememberedReturnCaller();
    return { returnTo: resolvedTo, returnRecordId: resolvedId };
  }
  const remembered = consumeRememberedReturnCaller();
  // 仕様: Core 第3.3.3節。別の請求アカウントを標準経路でEditしたときは古い戻り控えを使わない。
  if (
    billingAccountId &&
    remembered.billingAccountId !== billingAccountId
  ) {
    return { returnTo: "", returnRecordId: "" };
  }
  return {
    returnTo: remembered.returnTo,
    returnRecordId: remembered.returnRecordId
  };
}
