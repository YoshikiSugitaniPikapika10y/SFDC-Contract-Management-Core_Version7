import { NavigationMixin } from 'lightning/navigation';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { getLightningBase } from 'c/estimateWizardNavigation';

const ORDER_WIZARD_TARGETS = {
    order: {
        navItemApiName: 'Order_Process',
        componentName: 'c__orderCreateWizard'
    },
    revert: {
        navItemApiName: 'Order_Revert',
        componentName: 'c__orderRevertWizard'
    },
    preview: {
        navItemApiName: 'Order_Invoice_Preview',
        componentName: 'c__orderInvoicePreviewWizard'
    }
};

export function isOrderWizardTabView(pageRef, componentToken) {
    if (!pageRef) {
        return false;
    }

    const apiName = pageRef.attributes?.apiName || '';
    const componentName = pageRef.attributes?.componentName || '';
    const target = ORDER_WIZARD_TARGETS[componentToken];

    if (target && apiName === target.navItemApiName) {
        return true;
    }
    if (
        pageRef.type === 'standard__navItemPage' &&
        target &&
        apiName === target.navItemApiName
    ) {
        return true;
    }
    if (
        pageRef.type === 'standard__component' &&
        target &&
        componentName.includes(target.componentName.replace('c__', ''))
    ) {
        return true;
    }

    if (typeof window !== 'undefined') {
        const href = window.location.href;
        if (target?.navItemApiName && href.includes(`/n/${target.navItemApiName}`)) {
            return true;
        }
        if (
            target?.componentName &&
            href.includes(`/cmp/${target.componentName}`)
        ) {
            return true;
        }
    }

    return false;
}

export function readOrderWizardRecordId(pageRef) {
    return pageRef?.state?.c__recordId || '';
}

export function initializeOrderWizardFromUrl(component) {
    if (typeof window === 'undefined') {
        return;
    }

    try {
        const url = new URL(window.location.href);
        const recordId = url.searchParams.get('c__recordId');
        if (recordId) {
            component.recordId = recordId;
        }
    } catch (e) {
        // ignore malformed URLs
    }
}

export function buildOrderWizardUrls({ wizardKey, recordId }) {
    const target = ORDER_WIZARD_TARGETS[wizardKey];
    if (!target || !recordId) {
        return [];
    }

    const params = new URLSearchParams({ c__recordId: recordId });
    const query = params.toString();
    const base = getLightningBase();

    return [
        `${base}/lightning/cmp/${target.componentName}?${query}`,
        `${base}/lightning/n/${target.navItemApiName}?${query}`
    ];
}

export function navigateToOrderWizard(component, { wizardKey, recordId }) {
    const target = ORDER_WIZARD_TARGETS[wizardKey];
    if (!target || !recordId) {
        throw new Error('ORDER_WIZARD_TARGET_MISSING');
    }

    const state = { c__recordId: recordId };

    component[NavigationMixin.Navigate]({
        type: 'standard__component',
        attributes: {
            componentName: target.componentName
        },
        state
    });
}

export function navigateToContractHistoryRecord(component, recordId) {
    const resolvedRecordId = recordId || component?.recordId;
    if (
        !resolvedRecordId ||
        typeof component?.[NavigationMixin.Navigate] !== 'function'
    ) {
        return;
    }

    component[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: {
            recordId: resolvedRecordId,
            objectApiName: 'ContractHistory__c',
            actionName: 'view'
        }
    });
}

export function closeOrderWizardTab(component, { recordId, refresh = true } = {}) {
    const resolvedRecordId = recordId || component.recordId;
    if (refresh && resolvedRecordId) {
        getRecordNotifyChange([{ recordId: resolvedRecordId }]);
    }

    if (resolvedRecordId) {
        navigateToContractHistoryRecord(component, resolvedRecordId);
        return;
    }

    if (typeof window !== 'undefined') {
        window.close();
        setTimeout(() => {
            if (!window.closed && resolvedRecordId) {
                window.location.href = `${getLightningBase()}/lightning/r/ContractHistory__c/${resolvedRecordId}/view`;
            }
        }, 150);
    }
}

export { NavigationMixin };