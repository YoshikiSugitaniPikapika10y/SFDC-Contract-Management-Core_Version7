import { NavigationMixin } from 'lightning/navigation';

export function getLightningBase() {
    if (typeof window === 'undefined') {
        return '';
    }

    const href = resolveReferenceHref();
    if (!href) {
        return window.location.origin;
    }

    const lightningIndex = href.indexOf('/lightning/');
    if (lightningIndex >= 0) {
        return href.substring(0, lightningIndex);
    }

    try {
        return new URL(href).origin;
    } catch (e) {
        return window.location.origin;
    }
}

function resolveReferenceHref() {
    const candidates = [];

    if (typeof window.top !== 'undefined' && window.top?.location?.href) {
        candidates.push(window.top.location.href);
    }
    if (window.location?.href) {
        candidates.push(window.location.href);
    }
    if (typeof document !== 'undefined' && document.referrer) {
        candidates.push(document.referrer);
    }

    for (const href of candidates) {
        if (href && href.includes('/lightning/')) {
            return href;
        }
    }

    return candidates.find((href) => href && href.startsWith('http')) || '';
}

export function toAbsoluteLightningUrl(url) {
    if (!url) {
        return url;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
        return url;
    }
    const base = getLightningBase();
    return `${base}${url.startsWith('/') ? url : `/${url}`}`;
}

export function buildEstimateWizardUrl({ opportunityId, copyFromHistoryId }) {
    if (!opportunityId && !copyFromHistoryId) {
        return [];
    }

    const params = new URLSearchParams();
    if (opportunityId) {
        params.set('c__recordId', opportunityId);
    }
    if (copyFromHistoryId) {
        params.set('c__copyFromHistoryId', copyFromHistoryId);
    }

    const base = getLightningBase();
    const query = params.toString();

    return [
        `${base}/lightning/cmp/c__estimateCreateWizard?${query}`,
        `${base}/lightning/n/Estimate_Create?${query}`
    ];
}

export async function resolveEstimateWizardUrl(
    navigationComponent,
    { opportunityId, copyFromHistoryId }
) {
    const manualCandidates = buildEstimateWizardUrl({
        opportunityId,
        copyFromHistoryId
    }).filter(Boolean);

    if (manualCandidates.length > 0) {
        return manualCandidates[0];
    }

    if (navigationComponent) {
        const state = {};
        if (opportunityId) {
            state.c__recordId = opportunityId;
        }
        if (copyFromHistoryId) {
            state.c__copyFromHistoryId = copyFromHistoryId;
        }

        const pageRefs = [
            {
                type: 'standard__navItemPage',
                attributes: { apiName: 'Estimate_Create' },
                state
            },
            {
                type: 'standard__component',
                attributes: { componentName: 'c__estimateCreateWizard' },
                state
            }
        ];

        for (const pageRef of pageRefs) {
            try {
                const generated = await navigationComponent[
                    NavigationMixin.GenerateUrl
                ](pageRef);
                if (generated) {
                    return toAbsoluteLightningUrl(generated);
                }
            } catch (e) {
                // try next
            }
        }
    }

    return '';
}

export function openEstimateWizardTab(
    navigationComponent,
    { opportunityId, copyFromHistoryId }
) {
    const manualCandidates = buildEstimateWizardUrl({
        opportunityId,
        copyFromHistoryId
    }).filter(Boolean);

    if (manualCandidates.length > 0) {
        const url = manualCandidates[0];
        const popup = window.open(url, '_blank', 'noopener,noreferrer');
        if (!popup) {
            throw new Error('POPUP_BLOCKED');
        }
        return Promise.resolve(url);
    }

    return resolveEstimateWizardUrl(navigationComponent, {
        opportunityId,
        copyFromHistoryId
    }).then((url) => {
        if (!url) {
            throw new Error('見積ウィザード URL を生成できません。');
        }
        const popup = window.open(url, '_blank', 'noopener,noreferrer');
        if (!popup) {
            throw new Error('POPUP_BLOCKED');
        }
        return url;
    });
}