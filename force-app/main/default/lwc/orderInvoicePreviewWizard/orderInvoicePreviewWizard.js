import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { resolveSaveErrorAlert } from 'c/estimateValidationAlertUtils';
import {
    closeOrderWizardTab,
    initializeOrderWizardFromUrl,
    isOrderWizardTabView,
    NavigationMixin,
    readOrderWizardRecordId
} from 'c/orderWizardNavigation';
import {
    HISTORY_STATUS_ARCHIVE,
    isOrderActionBootstrapping,
    requestOrderWizardClose,
    scheduleRecordActionLoad,
    resetRecordActionLoadState
} from 'c/orderWizardClose';
import getOrderContext from '@salesforce/apex/OrderCreateController.getOrderContext';
import getInvoicePreview from '@salesforce/apex/OrderCreateController.getInvoicePreview';
import updateInvoiceLineAmounts from '@salesforce/apex/OrderCreateController.updateInvoiceLineAmounts';
import updateInvoiceDates from '@salesforce/apex/OrderCreateController.updateInvoiceDates';
import splitInvoiceByDate from '@salesforce/apex/OrderCreateController.splitInvoiceByDate';
import splitInvoiceByBillingAccount from '@salesforce/apex/OrderCreateController.splitInvoiceByBillingAccount';
import moveLinesToExistingInvoice from '@salesforce/apex/OrderCreateController.moveLinesToExistingInvoice';
import splitLinesInPlace from '@salesforce/apex/OrderCreateController.splitLinesInPlace';
import resetLatestVersionInvoicesToPostOrder from '@salesforce/apex/OrderCreateController.resetLatestVersionInvoicesToPostOrder';
import getBillingAccountOptionsForPreview from '@salesforce/apex/OrderCreateController.getBillingAccountOptionsForPreview';
import updateInvoiceHeaderAndDates from '@salesforce/apex/OrderCreateController.updateInvoiceHeaderAndDates';

export default class OrderInvoicePreviewWizard extends NavigationMixin(
    LightningElement
) {
    @api recordId;

    @track isTabView = false;
    @track isLoading = true;
    @track isSaving = false;
    @track errorMessage = '';
    @track invoicePreview;
    @track billingAccountOptions = [];

    connectedCallback() {
        initializeOrderWizardFromUrl(this);
        // 開くたびに請求プレビューをサーバ最新で取り直す
        resetRecordActionLoadState(this);
        scheduleRecordActionLoad(this, () => this.loadPreview());
    }

    renderedCallback() {
        scheduleRecordActionLoad(this, () => this.loadPreview());
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        const recordId = readOrderWizardRecordId(pageRef);
        if (recordId) {
            this.recordId = recordId;
        }
        this.isTabView = isOrderWizardTabView(pageRef, 'preview');
    }

    get pageClass() {
        return this.isTabView
            ? 'preview-page preview-page_tab'
            : 'preview-page preview-page_modal';
    }

    async loadPreview() {
        if (!this.recordId) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';
        this.invoicePreview = undefined;
        try {
            const context = await getOrderContext({
                contractHistoryId: this.recordId
            });

            if (context.historyStatus === HISTORY_STATUS_ARCHIVE) {
                this.errorMessage =
                    'アーカイブ済みの契約履歴では請求プレビューは利用できません。';
                return;
            }

            if (!context.isOrdered) {
                this.errorMessage =
                    'Estimate 状態の契約履歴です。「受注」ボタンをご利用ください。';
                return;
            }

            this.invoicePreview = await getInvoicePreview({
                contractHistoryId: this.recordId
            });
            this.billingAccountOptions =
                await getBillingAccountOptionsForPreview({
                    contractHistoryId: this.recordId
                });
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    get hasPreview() {
        return Boolean(this.invoicePreview);
    }

    get showBootstrapLoading() {
        return isOrderActionBootstrapping(this);
    }

    get previewContentVersion() {
        return this.invoicePreview?.contentVersion || null;
    }

    async handleSaveLineAmounts(event) {
        const { edits } = event.detail || {};
        if (!edits?.length) {
            return;
        }
        await this.runEdit(() =>
            updateInvoiceLineAmounts({
                contractHistoryId: this.recordId,
                edits,
                expectedContentVersion: this.previewContentVersion
            })
        );
    }

    async handleSaveInvoiceDates(event) {
        const { invoiceId, invoiceDate, paymentScheduledDate } =
            event.detail || {};
        if (!invoiceId) {
            return;
        }
        await this.runEdit(() =>
            updateInvoiceDates({
                contractHistoryId: this.recordId,
                invoiceId,
                invoiceDate: invoiceDate || null,
                paymentScheduledDate: paymentScheduledDate || null,
                expectedContentVersion: this.previewContentVersion
            })
        );
    }

    async handleSaveBillingHeader(event) {
        const {
            invoiceId,
            invoiceDate,
            paymentScheduledDate,
            billingAddressee,
            billingEmailTo,
            billingEmailCc,
            billingEmailBcc,
            taxPercent
        } = event.detail || {};
        if (!invoiceId) {
            return;
        }
        // 日付＋宛名／メール／税率は 1 Apex・1 DML。片側だけ成功してエラー表示、を防ぐ。
        const saved = await this.runEdit(() =>
            updateInvoiceHeaderAndDates({
                contractHistoryId: this.recordId,
                invoiceId,
                invoiceDate: invoiceDate || null,
                paymentScheduledDate: paymentScheduledDate || null,
                billingAddressee: billingAddressee ?? '',
                billingEmailTo: billingEmailTo ?? '',
                billingEmailCc: billingEmailCc ?? '',
                billingEmailBcc: billingEmailBcc ?? '',
                taxPercent:
                    taxPercent == null || taxPercent === ''
                        ? 0
                        : Number(taxPercent),
                expectedContentVersion: this.previewContentVersion
            })
        );
        if (saved) {
            const table = this.template.querySelector(
                'c-order-invoice-preview-table'
            );
            if (table && typeof table.clearBillingEditState === 'function') {
                table.clearBillingEditState();
            }
        }
    }

    async handleSplitInvoice(event) {
        const {
            mode,
            sourceInvoiceId,
            newInvoiceDate,
            newPaymentScheduledDate,
            newBillingAccountId,
            splitLines
        } = event.detail || {};
        if (!sourceInvoiceId || !(splitLines || []).length) {
            return;
        }
        if (mode === 'billingAccount') {
            if (!newBillingAccountId) {
                return;
            }
            await this.runEdit(() =>
                splitInvoiceByBillingAccount({
                    contractHistoryId: this.recordId,
                    sourceInvoiceId,
                    newBillingAccountId,
                    newInvoiceDate: newInvoiceDate || null,
                    newPaymentScheduledDate: newPaymentScheduledDate || null,
                    splitLines,
                    expectedContentVersion: this.previewContentVersion
                })
            );
            return;
        }
        await this.runEdit(() =>
            splitInvoiceByDate({
                contractHistoryId: this.recordId,
                sourceInvoiceId,
                newInvoiceDate: newInvoiceDate || null,
                newPaymentScheduledDate: newPaymentScheduledDate || null,
                splitLines,
                expectedContentVersion: this.previewContentVersion
            })
        );
    }

    async handleMoveLines(event) {
        const { sourceInvoiceId, targetInvoiceId, lineIds } = event.detail || {};
        if (
            !sourceInvoiceId ||
            !targetInvoiceId ||
            !(lineIds || []).length
        ) {
            return;
        }
        await this.runEdit(() =>
            moveLinesToExistingInvoice({
                contractHistoryId: this.recordId,
                sourceInvoiceId,
                targetInvoiceId,
                lineIds,
                expectedContentVersion: this.previewContentVersion
            })
        );
    }

    async handleSplitLinesInPlace(event) {
        const { invoiceId, splitLines } = event.detail || {};
        if (!invoiceId || !(splitLines || []).length) {
            return;
        }
        await this.runEdit(() =>
            splitLinesInPlace({
                contractHistoryId: this.recordId,
                invoiceId,
                splitLines,
                expectedContentVersion: this.previewContentVersion
            })
        );
    }

    async handleResetPostOrder(event) {
        const { versionValue } = event.detail || {};
        if (!versionValue) {
            return;
        }
        await this.runEdit(() =>
            resetLatestVersionInvoicesToPostOrder({
                contractHistoryId: this.recordId,
                versionValue: String(versionValue),
                expectedContentVersion: this.previewContentVersion
            })
        );
    }

    async runEdit(action) {
        if (this.isSaving) {
            return false;
        }
        this.isSaving = true;
        this.errorMessage = '';
        try {
            this.invoicePreview = await action();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: '保存しました',
                    message: '請求正本を更新しました。',
                    variant: 'success'
                })
            );
            return true;
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: '保存エラー',
                    message: this.errorMessage,
                    variant: 'error'
                })
            );
            return false;
        } finally {
            this.isSaving = false;
        }
    }

    handleClose() {
        this.closeAction({ refresh: false });
    }

    closeAction({ refresh = false } = {}) {
        if (this.isTabView) {
            closeOrderWizardTab(this, {
                recordId: this.recordId,
                refresh
            });
            return;
        }
        requestOrderWizardClose(this, { recordId: this.recordId, refresh });
    }

    reduceError(error) {
        const alert = resolveSaveErrorAlert(error);
        return alert.messages.map((entry) => entry.text).join('\n');
    }
}
