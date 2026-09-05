({
  /** 仕様: Core 第3.3.2節。Aura 上書きは New か Edit。View はレコードページ。 */
  syncMode: function (component) {
    component.set(
      "v.formMode",
      component.get("v.recordId") ? "edit" : "new"
    );
  }
});
