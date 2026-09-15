({
  /** 仕様: Core 第3.3.2節・第3.3.3節。Aura 上書きは New か Edit。View はレコードページ。関連リスト新規の defaultFieldValues と、見積／受注からの戻り先を LWC へ渡す。 */
  syncMode: function (component, event, helper) {
    helper.syncMode(component);
  }
});
