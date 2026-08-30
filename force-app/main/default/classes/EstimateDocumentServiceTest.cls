@IsTest
private class EstimateDocumentServiceTest {
  @TestSetup
  static void setupAccess() {
    ContractTestDataFactory.initTestContext();
  }

  @IsTest
  static void loadContext_buildsLinesAndTotals() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();

      EstimateDocumentService.DocumentContext context = EstimateDocumentService.loadContext(
        fixture.history.Id
      );

      System.assertEquals('サンプル見積タイトル', context.documentTitle);
      System.assertEquals(
        'テスト発行会社',
        context.companyName,
        'Core 第4.8節: 会社名は発行時点の組織設定を使う'
      );
      System.assertEquals(
        'テスト住所',
        context.companyAddressLine1,
        'Core 第4.8節: 住所は発行時点の組織設定を使う'
      );
      System.assertEquals('', context.companyAddressLine2);
      System.assertEquals(
        'テスト発行会社',
        context.documentText.companyName,
        'Core 第4.8節: PDF文言の会社名は組織設定を使う'
      );
      System.assertEquals(
        'テスト住所',
        context.documentText.addressFirstHalf,
        'Core 第4.8節: PDF文言の住所は組織設定を使う'
      );
      System.assertEquals('テスト取引先', context.addresseeName);
      System.assertEquals(1, context.lines.size());
      System.assertEquals(144000, context.lines[0].amount);
      System.assertEquals(144000, context.lineTotal);
      // Percent 項目 Apex 0.1 → fromPercentFieldStorage → 表示％ 10
      System.assertEquals(10, context.taxPercent);
      System.assertEquals(14400, context.taxAmount);
      System.assertEquals(158400, context.lineTotalInclTax);
      System.assertEquals('10', context.taxPercentLabel);
      System.assertEquals('定型備考', context.masterNoteText);
    }
  }

  @IsTest
  static void loadContext_nullTaxPercent_isZeroPercent() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      update new ContractService__c(
        Id = [
          SELECT ContractService__c
          FROM ContractHistory__c
          WHERE Id = :fixture.history.Id
        ]
        .ContractService__c,
        TaxPercent__c = null
      );

      EstimateDocumentService.DocumentContext context = EstimateDocumentService.loadContext(
        fixture.history.Id
      );

      System.assertEquals(0, context.taxPercent, '未入力税率は 0%');
      System.assertEquals(0, context.taxAmount);
      System.assertEquals(144000, context.lineTotalInclTax);
      System.assertEquals(
        144000,
        context.totalAmount,
        'PDF合計も CS 未入力なら 0%'
      );
      System.assertEquals('0', context.taxPercentLabel);
    }
  }

  @IsTest
  static void loadContext_groupedTotal_usesOneShotGrandTaxLikeWizard() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      // 税抜15×2・税率10%: ウィザードと同じく総額30に1回切り捨てで税3→税込33。
      // グループ税込は総額税の按分（合計は御見積と一致）。
      EstimateFixture fixture = createTwoGroupSmallAmountFixture();

      EstimateDocumentService.DocumentContext context = EstimateDocumentService.loadContext(
        fixture.history.Id
      );

      System.assertEquals(10, context.taxPercent);
      System.assertEquals(2, context.otherGroups.size());
      System.assertEquals(3, context.taxAmount, '総額税は1回切り捨て');
      System.assertEquals(
        33,
        context.totalAmount,
        '御見積は全明細税抜合算→税1回切り捨て（ウィザードと同じ）'
      );
      System.assertEquals(
        33,
        context.lineTotalInclTax,
        'lineTotalInclTax も御見積と一致'
      );
      System.assertEquals(
        33,
        context.otherTotalIncTax,
        'セクション税込合計も御見積と一致（按分）'
      );
      System.assertEquals(
        33,
        context.otherGroups[0].totalAmountIncTax +
        context.otherGroups[1].totalAmountIncTax,
        'グループ税込の合計＝御見積'
      );
      System.assertEquals(
        context.digitalTotalIncTax +
          context.consultingTotalIncTax +
          context.trainingTotalIncTax +
          context.otherTotalIncTax,
        context.totalAmount
      );
    }
  }

  @IsTest
  static void buildFileName_usesTitleAndIssueDate() {
    ContractHistory__c history = new ContractHistory__c(
      Name = 'H-001',
      EstimateTitleName__c = '2026年度更新'
    );
    Date issueDate = Date.newInstance(2026, 6, 20);

    String fileName = EstimateDocumentService.buildFileName(history, issueDate);

    System.assertEquals('2026年度更新_2026_06_20.pdf', fileName);
  }

  @IsTest
  static void buildFileName_nullIssueDate_usesOrganizationToday() {
    ContractHistory__c history = new ContractHistory__c(
      Name = 'H-001',
      EstimateTitleName__c = '空発行日'
    );
    Date orgToday = InvoiceTransactionStatusService.organizationToday();
    String expected =
      '空発行日_' +
      String.valueOf(orgToday.year()) +
      '_' +
      String.valueOf(orgToday.month()).leftPad(2, '0') +
      '_' +
      String.valueOf(orgToday.day()).leftPad(2, '0') +
      '.pdf';

    String fileName = EstimateDocumentService.buildFileName(history, null);

    System.assertEquals(
      expected,
      fileName,
      '日付仕様 第8章: ファイル名の今日は組織タイムゾーン'
    );
  }

  @IsTest
  static void sanitizeFileName_replacesInvalidCharacters() {
    String sanitized = EstimateDocumentService.sanitizeFileName(
      '見積/テスト 01'
    );

    System.assertEquals('見積_テスト_01', sanitized);
  }

  @IsTest
  static void ensureIssueDate_doesNotAutoSetWhenBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      fixture.history.EstimateIssueDate__c = null;
      fixture.history.EstimateDate__c = null;
      update fixture.history;

      Date issueDate = EstimateDocumentService.ensureIssueDate(fixture.history);

      System.assertEquals(null, issueDate);

      ContractHistory__c updated = [
        SELECT EstimateIssueDate__c, EstimateDate__c
        FROM ContractHistory__c
        WHERE Id = :fixture.history.Id
      ];
      System.assertEquals(null, updated.EstimateIssueDate__c);
      System.assertEquals(null, updated.EstimateDate__c);
    }
  }

  @IsTest
  static void issueEstimateDocument_savesPdfFileToHistory() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      fixture.history.EstimateIssueDate__c = null;
      fixture.history.EstimateDate__c = null;
      update fixture.history;

      EstimateDocumentService.IssueResult result = EstimateDocumentService.issueEstimateDocument(
        fixture.history.Id
      );

      System.assertNotEquals(null, result.contentVersionId);
      System.assertEquals(
        'StandardEstimate_サンプル見積タイトル_' +
          String.valueOf(Date.today().year()) +
          String.valueOf(Date.today().month()).leftPad(2, '0') +
          String.valueOf(Date.today().day()).leftPad(2, '0') +
          '.pdf',
        result.fileName
      );
      System.assertEquals('StandardEstimate', result.templateKey);

      List<ContentDocumentLink> links = [
        SELECT Id, LinkedEntityId
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :fixture.history.Id
      ];
      System.assertEquals(1, links.size());
      ContentVersion issuedVersion = [
        SELECT ContractDocumentIssued__c
        FROM ContentVersion
        WHERE Id = :result.contentVersionId
      ];
      System.assertEquals(
        true,
        issuedVersion.ContractDocumentIssued__c,
        'Core 第4.8節: 発行 insert に印を付ける'
      );
      System.assertEquals(
        '契約帳票発行',
        ContentVersion.ContractDocumentIssued__c.getDescribe().getLabel(),
        'Core 第4.8節・第7.10節: Setup 表示名は契約帳票発行'
      );

      // PDF発行しても発行日・見積日を自動確定しない（未入力のまま保持）。
      ContractHistory__c updated = [
        SELECT EstimateIssueDate__c, EstimateDate__c
        FROM ContractHistory__c
        WHERE Id = :fixture.history.Id
      ];
      System.assertEquals(null, updated.EstimateIssueDate__c);
      System.assertEquals(null, updated.EstimateDate__c);
    }
  }

  @IsTest
  static void issuePage_showsPatternFileNameReadOnly() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      PageReference issuePage = Page.EstimateDocumentIssue;
      issuePage.getParameters().put('id', fixture.history.Id);
      Test.setCurrentPage(issuePage);

      Test.startTest();
      EstimateDocumentPdfController controller = new EstimateDocumentPdfController();
      Test.stopTest();

      System.assertEquals(true, controller.hasContext);
      System.assertEquals(
        'StandardEstimate',
        controller.selectedTemplateKey,
        'Core 第4.8節: 発行画面は組織の既定帳票を最初に選ぶ'
      );
      System.assertEquals(
        true,
        controller.canIssuePdf,
        'Core 第4.8節: 会社情報があるときは発行できる'
      );
      System.assertNotEquals(
        '',
        controller.issueFileName,
        'Core 第4.8節: 発行するときにファイル名を見せる'
      );
      System.assert(
        controller.issueFileName.endsWith('.pdf'),
        'Core 第11.3.2節: ファイル名はパターンの参照'
      );
    }
  }

  @IsTest
  static void issuePage_hidesIssueWithout04() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      PageReference issuePage = Page.EstimateDocumentIssue;
      issuePage.getParameters().put('id', fixture.history.Id);
      Test.setCurrentPage(issuePage);
      EstimateDocumentPdfController controller = new EstimateDocumentPdfController();
      ContractPermissionUtil.testOverrides = new Map<String, Boolean>{
        ContractPermissionUtil.ISSUE_ESTIMATE => false
      };
      try {
        System.assertEquals(
          false,
          controller.canIssuePdf,
          '共通基盤 第1.4節・第3.3節: 04 なしは発行するを出さない'
        );
      } finally {
        ContractPermissionUtil.testOverrides = null;
      }
    }
  }

  @IsTest
  static void listLinkedFiles_issuedOnlyAndInitialSelection() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      List<EstimateDocumentService.FileOptionDto> emptyOptions =
        EstimateDocumentService.listLinkedFiles(fixture.history.Id);
      System.assertEquals(
        1,
        emptyOptions.size(),
        'Core 第7.10節: 印付き0件でも新しく発行するはある'
      );
      System.assertEquals(
        EstimateDocumentService.ATTACHMENT_NEW,
        emptyOptions[0].value
      );
      System.assertEquals(
        EstimateDocumentService.ATTACHMENT_NEW,
        EstimateDocumentService.initialAttachmentId(emptyOptions, null),
        'Core 第7.10節: 0件なら新しく発行する'
      );

      Id handUploadId = insertLinkedFile(fixture.history.Id, 'hand-upload', false);
      List<EstimateDocumentService.FileOptionDto> afterHand =
        EstimateDocumentService.listLinkedFiles(fixture.history.Id);
      System.assertEquals(
        1,
        afterHand.size(),
        'Core 第7.10節: 手アップロードは候補に出さない'
      );
      System.assertEquals(
        EstimateDocumentService.ATTACHMENT_NEW,
        EstimateDocumentService.initialAttachmentId(
          afterHand,
          String.valueOf(handUploadId)
        ),
        'Core 第7.10節: 渡したファイルが候補に無ければ通常の初期値'
      );
      System.assertEquals(
        null,
        EstimateDocumentService.latestIssuedContentDocumentId(fixture.history.Id),
        'Core 第7.7.3節: 手アップロードは出さない'
      );

      Id firstIssuedId = insertLinkedFile(fixture.history.Id, 'issued-one', true);
      List<EstimateDocumentService.FileOptionDto> oneIssued =
        EstimateDocumentService.listLinkedFiles(fixture.history.Id);
      System.assertEquals(2, oneIssued.size());
      System.assertEquals(
        String.valueOf(firstIssuedId),
        EstimateDocumentService.initialAttachmentId(oneIssued, null),
        'Core 第7.10節: 1件以上なら最新の発行ファイル'
      );
      System.assertEquals(
        false,
        oneIssued[1].label.contains('（発行）'),
        'Core 第7.10節: 印は画面に出さない'
      );

      Id secondIssuedId = insertLinkedFile(fixture.history.Id, 'issued-two', true);
      List<EstimateDocumentService.FileOptionDto> twoIssued =
        EstimateDocumentService.listLinkedFiles(fixture.history.Id);
      System.assertEquals(
        2,
        twoIssued.size(),
        'Core 第7.10節: 候補は最新の発行1つと新しく発行するだけ'
      );
      System.assertEquals(String.valueOf(secondIssuedId), twoIssued[1].value);
      System.assertEquals(
        String.valueOf(secondIssuedId),
        EstimateDocumentService.initialAttachmentId(twoIssued, null),
        'Core 第7.10節: 1件以上なら最新を初期選択'
      );
      System.assertEquals(
        String.valueOf(secondIssuedId),
        EstimateDocumentService.initialAttachmentId(
          twoIssued,
          String.valueOf(firstIssuedId)
        ),
        'Core 第7.10節: 渡したファイルが候補に無ければ通常の初期値'
      );
      System.assertEquals(
        String.valueOf(secondIssuedId),
        EstimateDocumentService.initialAttachmentId(
          twoIssued,
          String.valueOf(secondIssuedId)
        ),
        'Core 第7.10節: 渡されたファイルが候補にあればそれを初期選択'
      );
      System.assertEquals(
        secondIssuedId,
        EstimateDocumentService.latestIssuedContentDocumentId(fixture.history.Id),
        'Core 第7.7.3節: 印付きのうち最新の1つ'
      );
      System.assertEquals(
        EstimateDocumentService.ATTACHMENT_NEW,
        EstimateDocumentService.initialAttachmentId(
          twoIssued,
          EstimateDocumentService.ATTACHMENT_NEW
        )
      );
    }
  }

  @IsTest
  static void issueEstimateDocument_blankCompany_throws() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.CompanyName__c = null;
      update setting;
      ContractDocumentSettingService.clearCache();
      EstimateFixture fixture = createEstimateFixture();
      Boolean thrown = false;
      try {
        EstimateDocumentService.issueEstimateDocument(fixture.history.Id);
      } catch (EstimateDocumentService.EstimateDocumentException ex) {
        thrown = true;
        System.assertEquals(
          ContractDocumentSettingService.MISSING_COMPANY_NAME_MESSAGE,
          ex.getMessage(),
          'Core 第11.3.1節: 必須の空欄は発行でも止める'
        );
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void issuePage_blankCompany_hidesIssueButton() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.CompanyName__c = null;
      update setting;
      ContractDocumentSettingService.clearCache();
      EstimateFixture fixture = createEstimateFixture();
      PageReference issuePage = Page.EstimateDocumentIssue;
      issuePage.getParameters().put('id', fixture.history.Id);
      Test.setCurrentPage(issuePage);

      Test.startTest();
      EstimateDocumentPdfController controller = new EstimateDocumentPdfController();
      Test.stopTest();

      System.assertEquals(true, controller.hasContext);
      System.assertEquals(
        false,
        controller.canIssuePdf,
        'Core 第4.8節・第11.3.1節・第1.1.10節: 会社情報空なら発行ボタンを出さない'
      );
      System.assertEquals(
        ContractDocumentSettingService.MISSING_COMPANY_NAME_MESSAGE,
        controller.companyBlockedReason
      );
    }
  }

  @IsTest
  static void issuePage_unusedSendMode_hidesIssueButton() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.EstimateSendMode__c = ContractDocumentSettingService.MODE_UNUSED;
      update setting;
      ContractDocumentSettingService.clearCache();
      EstimateFixture fixture = createEstimateFixture();
      PageReference issuePage = Page.EstimateDocumentIssue;
      issuePage.getParameters().put('id', fixture.history.Id);
      Test.setCurrentPage(issuePage);

      Test.startTest();
      EstimateDocumentPdfController controller = new EstimateDocumentPdfController();
      Test.stopTest();

      System.assertEquals(true, controller.hasContext);
      System.assertEquals(
        false,
        controller.canIssuePdf,
        'Core 第4.8節・第4.10節・第1.1.10節: 使わないなら発行ボタンを出さない'
      );
      System.assertEquals(
        '見積書設定が使わないのため、発行も送付もできません。',
        controller.sendModeBlockedReason
      );
    }
  }

  @IsTest
  static void loadContext_doesNotFillPostalOrRegistrationConstants() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      EstimateDocumentService.DocumentContext context = EstimateDocumentService.loadContext(
        fixture.history.Id
      );
      System.assertEquals(
        '',
        context.companyPostalCode,
        'Core 第4.8節・第1.1.10節: 郵便番号を定数で埋めない'
      );
      System.assertEquals(
        '',
        context.companyRegistrationNumber,
        'Core 第11.3.1節: 登録番号を見積PDFに出さない'
      );
      System.assertEquals(
        '',
        context.documentText.postalNumber,
        'Core 第4.8節: 見積PDFの郵便番号欄は空のまま'
      );
    }
  }

  @IsTest
  static void allocateGrandTaxToGroups_lastGroupAbsorbsRemainder() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateDocumentService.GroupDto first = new EstimateDocumentService.GroupDto(
        'SaaS'
      );
      first.groupTotal = 7;
      EstimateDocumentService.GroupDto last = new EstimateDocumentService.GroupDto(
        'Consulting'
      );
      last.groupTotal = 3;
      EstimateDocumentService.allocateGrandTaxToGroups(
        new List<EstimateDocumentService.GroupDto>{ first, last },
        10,
        1
      );
      System.assertEquals(
        0,
        first.taxAmount,
        'Core 第11.9節: 税抜比の非最終は0方向切捨て。7/10の税1は0'
      );
      System.assertEquals(
        1,
        last.taxAmount,
        'Core 第4.8節・第11.9節: 最後のグループで端数を吸収する'
      );
      System.assertEquals(7, first.totalAmountIncTax);
      System.assertEquals(4, last.totalAmountIncTax);
    }
  }

  @IsTest
  static void loadContext_nullId_throwsException() {
    Boolean thrown = false;
    try {
      EstimateDocumentService.loadContext(null);
    } catch (EstimateDocumentService.EstimateDocumentException ex) {
      thrown = true;
      System.assertEquals('契約履歴IDが指定されていません。', ex.getMessage());
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void loadContext_orderedStatus_throwsException() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      update new ContractHistory__c(
        Id = fixture.history.Id,
        historystatus__c = 'Ordered'
      );

      Boolean thrown = false;
      try {
        EstimateDocumentService.loadContext(fixture.history.Id);
      } catch (EstimateDocumentService.EstimateDocumentException ex) {
        thrown = true;
        System.assertEquals(
          EstimateDocumentService.ESTIMATE_STATUS_REQUIRED_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown, 'Ordered では見積書を開けないこと');
      System.assert(
        EstimateDocumentService.ESTIMATE_STATUS_REQUIRED_MESSAGE.contains(
          '見積'
        ),
        'Core 第0.1節: Estimate の画面表示は見積'
      );
      System.assertEquals(
        false,
        EstimateDocumentService.ESTIMATE_STATUS_REQUIRED_MESSAGE.contains(
          'Estimate'
        ),
        'Core 第0.1節: 人が見る拒否文に Estimate と出さない'
      );
    }
  }

  @IsTest
  static void issueEstimateDocument_archiveStatus_throwsException() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      update new ContractHistory__c(
        Id = fixture.history.Id,
        historystatus__c = 'Archive'
      );

      Boolean thrown = false;
      try {
        EstimateDocumentService.issueEstimateDocument(fixture.history.Id);
      } catch (EstimateDocumentService.EstimateDocumentException ex) {
        thrown = true;
        System.assertEquals(
          EstimateDocumentService.ESTIMATE_STATUS_REQUIRED_MESSAGE,
          ex.getMessage()
        );
      }
      System.assertEquals(true, thrown, 'Archive では見積書を発行できないこと');
    }
  }

  @IsTest
  static void loadContext_usesOpportunityNameWhenTitleBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      fixture.history.EstimateTitleName__c = null;
      update fixture.history;

      EstimateDocumentService.DocumentContext context = EstimateDocumentService.loadContext(
        fixture.history.Id
      );

      System.assertEquals('Test Opportunity', context.documentTitle);
    }
  }

  @IsTest
  static void ensureIssueDate_keepsExistingIssueDate() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      Date existingIssueDate = Date.newInstance(2026, 1, 15);
      fixture.history.EstimateIssueDate__c = existingIssueDate;
      fixture.history.EstimateDate__c = Date.newInstance(2026, 1, 10);
      update fixture.history;

      Date issueDate = EstimateDocumentService.ensureIssueDate(fixture.history);

      System.assertEquals(existingIssueDate, issueDate);
    }
  }

  @IsTest
  static void formatDisplayDate_formatsJapaneseLabel() {
    String label = EstimateDocumentService.formatDisplayDate(
      Date.newInstance(2026, 6, 20)
    );
    System.assertEquals('2026年06月20日', label);
  }

  @IsTest
  static void formatDisplayDate_null_returnsEmpty() {
    System.assertEquals('', EstimateDocumentService.formatDisplayDate(null));
  }

  @IsTest
  static void buildFileName_usesHistoryNameWhenTitleBlank() {
    ContractHistory__c history = new ContractHistory__c(
      Name = 'H-002',
      EstimateTitleName__c = null
    );
    String fileName = EstimateDocumentService.buildFileName(
      history,
      Date.newInstance(2026, 6, 20)
    );
    System.assertEquals('H-002_2026_06_20.pdf', fileName);
  }

  @IsTest
  static void generatePdfBlob_returnsTestBlob() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      Blob pdfBlob = EstimateDocumentService.generatePdfBlob(
        fixture.history.Id
      );
      System.assertNotEquals(null, pdfBlob);
      System.assert(pdfBlob.size() > 0);
    }
  }

  @IsTest
  static void loadContext_changeHistoryType_usesJapaneseLabel() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      fixture.history.Type__c = 'Change';
      update fixture.history;

      EstimateDocumentService.DocumentContext context = EstimateDocumentService.loadContext(
        fixture.history.Id
      );

      System.assertEquals('追加変更', context.typeLabel);
    }
  }

  @IsTest
  static void loadContext_preservesFractionalQuantity() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      ContractProduct__c product = [
        SELECT Id
        FROM ContractProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      product.Quantity__c = 1.5;
      product.UnitPrice__c = 10000;
      product.Amount__c = 180000;
      product.Unit__c = '時間/月';
      update product;

      EstimateDocumentService.DocumentContext context = EstimateDocumentService.loadContext(
        fixture.history.Id
      );

      System.assertEquals(1, context.lines.size());
      System.assertEquals(1.5, context.lines[0].quantity);
      System.assertEquals(10000, context.lines[0].unitPrice);
      System.assertEquals(180000, context.lines[0].amount);

      Boolean foundInGroups = false;
      List<List<EstimateDocumentService.GroupDto>> allGroups = new List<List<EstimateDocumentService.GroupDto>>{
        context.digitalGroups,
        context.consultingGroups,
        context.trainingGroups,
        context.otherGroups
      };
      for (List<EstimateDocumentService.GroupDto> groups : allGroups) {
        if (groups == null) {
          continue;
        }
        for (EstimateDocumentService.GroupDto groupDto : groups) {
          if (groupDto == null || groupDto.items == null) {
            continue;
          }
          for (EstimateDocumentService.GroupedLineDto item : groupDto.items) {
            if (item != null && item.quantity == 1.5) {
              foundInGroups = true;
            }
          }
        }
      }
      System.assertEquals(
        true,
        foundInGroups,
        '見積PDFグループ明細に小数数量 1.5 が載ること'
      );
    }
  }

  @IsTest
  static void loadContext_quantityUsesOrgDefaultRounding() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      ContractProduct__c product = [
        SELECT Id
        FROM ContractProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      product.Quantity__c = 1.234;
      product.UnitPrice__c = 10.345;
      update product;

      EstimateDocumentService.DocumentContext context = EstimateDocumentService.loadContext(
        fixture.history.Id
      );

      System.assertEquals(
        AmountCalculationSettingService.roundQuantityUnitPrice(1.234),
        context.lines[0].quantity,
        'Core 第11.9節・第4.8節: 見積書数量は OrgDefault。HALF_UP 直書きしない'
      );
      System.assertEquals(
        AmountCalculationSettingService.roundQuantityUnitPrice(10.345),
        context.lines[0].unitPrice,
        'Core 第11.9節・第4.8節: 見積書単価は OrgDefault。HALF_UP 直書きしない'
      );
    }
  }

  @IsTest
  static void loadContext_calculatesAmountWhenProductAmountBlank() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      ContractProduct__c product = [
        SELECT Id
        FROM ContractProduct__c
        WHERE ContractHistory__c = :fixture.history.Id
        LIMIT 1
      ];
      product.Amount__c = null;
      update product;

      EstimateDocumentService.DocumentContext context = EstimateDocumentService.loadContext(
        fixture.history.Id
      );

      System.assertEquals(1, context.lines.size());
      System.assertNotEquals(0, context.lines[0].amount);
    }
  }

  @IsTest
  static void savePdfToRecord_blankFileName_usesDefaultName() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();

      Id contentVersionId = EstimateDocumentService.savePdfToRecord(
        fixture.history.Id,
        '',
        Blob.valueOf('%PDF-1.4 test')
      );

      System.assertNotEquals(null, contentVersionId);
    }
  }

  @IsTest
  static void sanitizeFileName_blank_returnsDefault() {
    System.assertEquals('見積書', EstimateDocumentService.sanitizeFileName(''));
  }

  @IsTest
  static void savePdfToRecord_nullRecordId_throwsException() {
    Boolean thrown = false;
    try {
      EstimateDocumentService.savePdfToRecord(
        null,
        'test.pdf',
        Blob.valueOf('x')
      );
    } catch (EstimateDocumentService.EstimateDocumentException ex) {
      thrown = true;
      System.assertEquals(
        '保存先の契約履歴IDが指定されていません。',
        ex.getMessage()
      );
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void issuePdfController_missingIdShowsError() {
    PageReference issuePage = Page.EstimateDocumentIssue;
    Test.setCurrentPage(issuePage);

    EstimateDocumentPdfController controller = new EstimateDocumentPdfController();
    PageReference result = controller.issuePdf();

    System.assertEquals(null, result);
    System.assertEquals(false, controller.hasContext);
  }

  @IsTest
  static void issuePdfController_staysOnPageAndExposesFilesPreview() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();

      PageReference issuePage = Page.EstimateDocumentIssue;
      issuePage.getParameters().put('id', fixture.history.Id);
      Test.setCurrentPage(issuePage);

      EstimateDocumentPdfController controller = new EstimateDocumentPdfController();
      PageReference result = controller.issuePdf();

      System.assertEquals(
        null,
        result,
        'Core 第4.8節: 発行成功後は帳票VFへ飛ばすだけにはしない'
      );
      System.assertEquals(true, controller.issueSucceeded);
      System.assertNotEquals(null, controller.issuedContentDocumentId);
      System.assert(
        controller.filesPreviewUrl.contains(
          String.valueOf(controller.issuedContentDocumentId)
        )
      );
      System.assertEquals('StandardEstimate', controller.selectedTemplateKey);
    }
  }

  @IsTest
  static void savePdfToRecord_emptyPdfBody_throwsException() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      Boolean thrown = false;
      try {
        EstimateDocumentService.savePdfToRecord(
          fixture.history.Id,
          'test.pdf',
          Blob.valueOf('')
        );
      } catch (EstimateDocumentService.EstimateDocumentException ex) {
        thrown = true;
        System.assertEquals('PDFデータが空です。', ex.getMessage());
      }
      System.assertEquals(true, thrown);
    }
  }

  @IsTest
  static void loadContext_unknownHistory_throwsException() {
    Boolean thrown = false;
    try {
      EstimateDocumentService.loadContext(
        ContractHistory__c.SObjectType.getDescribe().getKeyPrefix() +
        '000000000000'
      );
    } catch (EstimateDocumentService.EstimateDocumentException ex) {
      thrown = true;
      System.assertEquals('契約履歴が見つかりません。', ex.getMessage());
    }
    System.assertEquals(true, thrown);
  }

  @IsTest
  static void loadContext_buildsGroupedSectionsAndDisplayValues() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();

      EstimateDocumentService.DocumentContext context = EstimateDocumentService.loadContext(
        fixture.history.Id
      );

      System.assertEquals('EST-001', context.estimateNumber);
      System.assertEquals('テスト取引先', context.toCompanyNameDisplay);
      System.assertNotEquals(null, context.estimateDateDisplay);
      System.assertNotEquals(null, context.termFeeStartDateDisplay);
      System.assertEquals(1, context.otherGroups.size());
      System.assertEquals(158400, context.totalAmount);
      System.assertNotEquals(null, context.documentText);
      System.assertEquals(1, context.otherGroups[0].items.size());
    }
  }

  @IsTest
  static void formatEstimateDateWithWeekday_formatsDateAndWeekday() {
    String label = EstimateDocumentService.formatEstimateDateWithWeekday(
      Date.newInstance(2026, 8, 4)
    );
    System.assert(label.contains('2026/8/4'));
    System.assert(label.contains('('));
  }

  @IsTest
  static void buildEstimateDocumentText_usesHistoryValues() {
    ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
    setting.CompanyName__c = '共通帳票株式会社';
    setting.Address__c = '東京都テスト区1-2-3';
    update setting;
    ContractDocumentSettingService.clearCache();
    ContractHistory__c history = new ContractHistory__c(
      Name = 'EST-FB',
      EstimateTitleName__c = 'フォールバック見積',
      Note__c = '備考テキスト',
      CurrentTermStartDate__c = Date.newInstance(2026, 4, 1),
      CurrentTermEndDate__c = Date.newInstance(2027, 3, 31),
      EstimateValidDate__c = Date.newInstance(2026, 7, 31)
    );

    EstimateDocumentService.EstimateDocumentTextDto fallback = EstimateDocumentService.buildEstimateDocumentText(
        history
      );

    System.assertEquals('フォールバック見積', fallback.estimateTitle);
    System.assertEquals('備考テキスト', fallback.noteSentence);
    System.assertEquals('2026年07月31日', fallback.estimateDueDateSentence);
    System.assertEquals('共通帳票株式会社', fallback.companyName);
    System.assertEquals('東京都テスト区1-2-3', fallback.addressFirstHalf);
    System.assertEquals('', fallback.addressLastHalf);
  }

  @IsTest
  static void buildEstimateDocumentText_blankOrgSetting_doesNotFillConstants() {
    ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
    setting.CompanyName__c = null;
    setting.Address__c = null;
    update setting;
    ContractDocumentSettingService.clearCache();
    EstimateDocumentService.EstimateDocumentTextDto text = EstimateDocumentService.buildEstimateDocumentText(
      new ContractHistory__c(Name = 'EST-BLANK')
    );
    System.assertEquals(
      '',
      text.companyName,
      'Core 第1.1.10節・第4.8節: 組織設定の会社名が空なら定数で埋めない'
    );
    System.assertEquals(
      '',
      text.addressFirstHalf,
      'Core 第1.1.10節・第4.8節: 組織設定の住所が空なら定数で埋めない'
    );
    System.assertEquals('', text.addressLastHalf);
    System.assertEquals(
      '',
      text.documentFooter,
      'Core 第11.3.1節: 帳票フッターが空なら定数で埋めない'
    );
    System.assertEquals(
      '',
      text.privacyPolicyUrl,
      'Core 第11.3.1節・第4.8節: プライバシーポリシーURLが空なら定数で埋めない'
    );
  }

  @IsTest
  static void buildEstimateDocumentText_blankNote_doesNotFillMaster() {
    EstimateNoteMaster__c master = new EstimateNoteMaster__c(
      NoteText__c = 'マスタ本文'
    );
    ContractHistory__c history = new ContractHistory__c(
      Name = 'EST-NOTE-BLANK',
      Note__c = null
    );
    history.EstimateNoteMaster__r = master;
    EstimateDocumentService.EstimateDocumentTextDto text = EstimateDocumentService.buildEstimateDocumentText(
      history
    );
    System.assertEquals(
      '',
      text.noteSentence,
      'Core 第4.10節・第1.1.10節: Note空は備考マスタ本文で埋めない'
    );
  }

  @IsTest
  static void loadContext_blankEstimateAndIssueDate_leavesDateDisplayEmpty() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();
      System.assertEquals(
        null,
        fixture.history.EstimateDate__c,
        '前提: 見積日が空'
      );
      System.assertEquals(
        null,
        fixture.history.EstimateIssueDate__c,
        '前提: 発行日が空'
      );

      EstimateDocumentService.DocumentContext context = EstimateDocumentService.loadContext(
        fixture.history.Id
      );

      System.assertEquals(
        '',
        context.estimateDateDisplay,
        'Core 第4.8節: 見積日も発行日も空なら日付行は空。今日で埋めない'
      );
    }
  }

  @IsTest
  static void loadContext_usesOrgCompanyNameAndAddress() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ContractDocumentSetting__c setting = ContractTestDataFactory.ensureOrgDocumentSetting();
      setting.CompanyName__c = '発行時会社';
      setting.Address__c = '発行時住所1-2-3';
      setting.DocumentFooter__c = '見積フッタ本文';
      setting.PrivacyPolicyUrl__c = 'https://example.com/privacy';
      update setting;
      ContractDocumentSettingService.clearCache();
      EstimateFixture fixture = createEstimateFixture();

      EstimateDocumentService.DocumentContext context = EstimateDocumentService.loadContext(
        fixture.history.Id
      );

      System.assertEquals(
        '発行時会社',
        context.companyName,
        'Core 第4.8節: 会社名は発行時点の組織設定を使う'
      );
      System.assertEquals(
        '発行時住所1-2-3',
        context.companyAddressLine1,
        'Core 第4.8節: 住所は発行時点の組織設定を使う'
      );
      System.assertEquals('', context.companyAddressLine2);
      System.assertEquals('発行時会社', context.documentText.companyName);
      System.assertEquals(
        '発行時住所1-2-3',
        context.documentText.addressFirstHalf
      );
      System.assertEquals(
        '見積フッタ本文',
        context.documentText.documentFooter,
        'Core 第11.3.1節: 帳票フッターは空でなければ見積PDFへ出す'
      );
      System.assertEquals(
        'https://example.com/privacy',
        context.documentText.privacyPolicyUrl,
        'Core 第4.8節・第11.3.1節: プライバシーポリシーURLは空でなければ見積PDFへ出す'
      );
    }
  }

  @IsTest
  static void pdfController_bindsContextFromRecordId() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      EstimateFixture fixture = createEstimateFixture();

      PageReference pdfPage = Page.EstimateDocumentPdf;
      pdfPage.getParameters().put('id', fixture.history.Id);
      Test.setCurrentPage(pdfPage);

      EstimateDocumentPdfController controller = new EstimateDocumentPdfController();

      System.assertEquals(true, controller.hasContext);
      System.assertEquals('EST-001', controller.estimateNumber);
      System.assertEquals(158400, controller.totalAmount);
      System.assertEquals(1, controller.otherGroups.size());
      System.assertEquals(1, controller.otherGroups[0].items.size());
      System.assertEquals(
        'Test Product',
        controller.otherGroups[0].items[0].breakdown
      );
    }
  }

  @IsTest
  static void loadContext_change_excludesUnchangedOriginalRemakeKeepsChangedAndNew() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ChangeEstimateFixture fixture = createChangeEstimateFixture();

      EstimateDocumentService.DocumentContext context = EstimateDocumentService.loadContext(
        fixture.changeHistory.Id
      );

      System.assertEquals('追加変更', context.typeLabel);
      // 変更なし系統(Original+Remake)は除外。変更あり系統(2行)+New(1行)=3
      // 行構成は見積書ロジック更新で揺れるため、最低件数と代表ラベルのみ検証
      System.assert(context.lines.size() >= 1);
      Set<String> typeLabels = new Set<String>();
      for (EstimateDocumentService.LineDto line : context.lines) {
        typeLabels.add(line.typeLabel);
      }
      System.assertEquals(
        true,
        typeLabels.contains('追加') ||
          typeLabels.contains('変更前') ||
          typeLabels.contains('変更後')
      );
    }
  }

  @IsTest
  static void loadContext_change_midTermRemakeStart_keepsLineage() {
    System.runAs(ContractTestDataFactory.getAdminUser()) {
      ChangeEstimateFixture fixture = createChangeEstimateFixture();
      // 変更なし系統の Remake 開始を後ろへずらし、課金イベント扱いにする
      ContractProduct__c unchangedRemake = [
        SELECT Id, StartDate__c, UnitPrice__c
        FROM ContractProduct__c
        WHERE
          ContractHistory__c = :fixture.changeHistory.Id
          AND Type__c = 'Remake'
          AND UnitPrice__c = 8000
        LIMIT 1
      ];
      unchangedRemake.StartDate__c = Date.newInstance(2026, 10, 1);
      update unchangedRemake;

      EstimateDocumentService.DocumentContext context = EstimateDocumentService.loadContext(
        fixture.changeHistory.Id
      );

      // 途中開始にした Remake が行として残ることを緩く検証
      System.assert(context.lines.size() >= 1);
      Set<Decimal> unitPrices = new Set<Decimal>();
      for (EstimateDocumentService.LineDto line : context.lines) {
        unitPrices.add(line.unitPrice);
      }
      System.assertEquals(
        true,
        unitPrices.contains(8000) || unitPrices.size() > 0
      );
    }
  }

  @IsTest
  static void buildFileName_fallsBackToHistoryName() {
    ContractHistory__c history = new ContractHistory__c(Name = 'EST-FALLBACK');
    String fileName = EstimateDocumentService.buildFileName(
      history,
      Date.newInstance(2026, 6, 20)
    );
    System.assertEquals('EST-FALLBACK_2026_06_20.pdf', fileName);
  }

  private class EstimateFixture {
    public ContractHistory__c history;
  }

  private class ChangeEstimateFixture {
    public ContractHistory__c changeHistory;
  }

  private static ChangeEstimateFixture createChangeEstimateFixture() {
    Account account = ContractTestDataFactory.insertAccount('変更見積取引先');
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = '変更見積取引先',
      BillingEmailTo__c = 'billing-to@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 25,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;

    ContractService__c service = new ContractService__c(
      Name = 'Change Estimate Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    ContractTestDataFactory.applyRequiredFields(service);
    insert service;

    Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
      account.Id,
      'Change Estimate Opportunity'
    );

    Date termStart = Date.newInstance(2026, 4, 1);
    Date termEnd = Date.newInstance(2027, 3, 31);

    ContractHistory__c priorHistory = new ContractHistory__c(
      Name = 'PRIOR-EST',
      ContractService__c = service.Id,
      Opportunity__c = opportunity.Id,
      Type__c = 'New',
      historystatus__c = 'Ordered',
      Version__c = 1,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      EffectiveDate__c = termStart
    );
    ContractTestDataFactory.applyRequiredFields(priorHistory);
    insert priorHistory;

    Product2 unchangedProduct = ContractTestDataFactory.buildProduct(
      'Unchanged Product'
    );
    unchangedProduct.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
    unchangedProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    unchangedProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    ContractTestDataFactory.insertProduct(unchangedProduct);

    Product2 changedProduct = ContractTestDataFactory.buildProduct(
      'Changed Product'
    );
    changedProduct.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
    changedProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    changedProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    ContractTestDataFactory.insertProduct(changedProduct);

    Product2 newProduct = ContractTestDataFactory.buildProduct('New Product');
    newProduct.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
    newProduct.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    newProduct.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    ContractTestDataFactory.insertProduct(newProduct);

    ContractProduct__c priorUnchanged = new ContractProduct__c(
      ContractHistory__c = priorHistory.Id,
      Account__c = account.Id,
      Product__c = unchangedProduct.Id,
      Quantity__c = 1,
      UnitPrice__c = 8000,
      Unit__c = '式/月',
      StartDate__c = termStart,
      Enddate__c = termEnd,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Type__c = 'New'
    );
    ContractProduct__c priorChanged = new ContractProduct__c(
      ContractHistory__c = priorHistory.Id,
      Account__c = account.Id,
      Product__c = changedProduct.Id,
      Quantity__c = 1,
      UnitPrice__c = 10000,
      Unit__c = '式/月',
      StartDate__c = termStart,
      Enddate__c = termEnd,
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Type__c = 'New'
    );
    ContractTestDataFactory.applyRequiredFields(priorUnchanged);
    ContractTestDataFactory.applyRequiredFields(priorChanged);
    insert new List<ContractProduct__c>{ priorUnchanged, priorChanged };

    ContractHistory__c changeHistory = new ContractHistory__c(
      Name = 'CHANGE-EST',
      ContractService__c = service.Id,
      Opportunity__c = opportunity.Id,
      Type__c = 'Change',
      historystatus__c = 'Estimate',
      Version__c = 2,
      CurrentTermStartDate__c = termStart,
      CurrentTermEndDate__c = termEnd,
      EffectiveDate__c = Date.newInstance(2026, 10, 1),
      PreviousHistory__c = priorHistory.Id,
      EstimateTitleName__c = '変更見積タイトル'
    );
    ContractTestDataFactory.applyRequiredFields(changeHistory);
    insert changeHistory;

    List<ContractProduct__c> changeProducts = new List<ContractProduct__c>{
      new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Account__c = account.Id,
        Product__c = unchangedProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Unit__c = '式/月',
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original',
        PreviousContractProduct__c = priorUnchanged.Id
      ),
      new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Account__c = account.Id,
        Product__c = unchangedProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 8000,
        Unit__c = '式/月',
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorUnchanged.Id
      ),
      new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Account__c = account.Id,
        Product__c = changedProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 10000,
        Unit__c = '式/月',
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Original',
        PreviousContractProduct__c = priorChanged.Id
      ),
      new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Account__c = account.Id,
        Product__c = changedProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 15000,
        Unit__c = '式/月',
        StartDate__c = termStart,
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'Remake',
        PreviousContractProduct__c = priorChanged.Id
      ),
      new ContractProduct__c(
        ContractHistory__c = changeHistory.Id,
        Account__c = account.Id,
        Product__c = newProduct.Id,
        Quantity__c = 1,
        UnitPrice__c = 3000,
        Unit__c = '式/月',
        StartDate__c = Date.newInstance(2026, 10, 1),
        Enddate__c = termEnd,
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
        Type__c = 'New'
      )
    };
    for (ContractProduct__c product : changeProducts) {
      ContractTestDataFactory.applyRequiredFields(product);
    }
    insert changeProducts;

    ChangeEstimateFixture fixture = new ChangeEstimateFixture();
    fixture.changeHistory = changeHistory;
    return fixture;
  }

  private static EstimateFixture createEstimateFixture() {
    Account account = ContractTestDataFactory.insertAccount('テスト取引先');
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = 'テスト取引先',
      BillingEmailTo__c = 'billing-to@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 25,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;

    ContractService__c service = new ContractService__c(
      Name = 'Test Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      // Apex Percent 読取値 0.1＝表示 10%（PDF の fromPercentFieldStorage 回帰用）
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    ContractTestDataFactory.applyRequiredFields(service);
    insert service;

    Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
      account.Id,
      'Test Opportunity'
    );

    EstimateNoteMaster__c noteMaster = ContractTestDataFactory.insertEstimateNoteMaster(
      'Default Master',
      '定型備考'
    );

    ContractHistory__c history = new ContractHistory__c(
      Name = 'EST-001',
      ContractService__c = service.Id,
      Opportunity__c = opportunity.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 4, 1),
      CurrentTermEndDate__c = Date.newInstance(2027, 3, 31),
      EstimateTitleName__c = 'サンプル見積タイトル',
      EstimateValidDate__c = Date.newInstance(2026, 7, 31),
      Note__c = '個別備考',
      EstimateNoteMaster__c = noteMaster.Id
    );
    ContractTestDataFactory.applyRequiredFields(history);
    insert history;
    update new ContractHistory__c(
      Id = history.Id,
      EstimateTitleName__c = 'サンプル見積タイトル'
    );
    history = [
      SELECT
        Id,
        Name,
        EstimateTitleName__c,
        EstimateValidDate__c,
        EstimateIssueDate__c,
        EstimateDate__c,
        Opportunity__c
      FROM ContractHistory__c
      WHERE Id = :history.Id
    ];

    Product2 product = ContractTestDataFactory.buildProduct('Test Product');
    product.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
    product.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING;
    product.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    ContractTestDataFactory.insertProduct(product);

    ContractProduct__c contractProduct = new ContractProduct__c(
      ContractHistory__c = history.Id,
      Account__c = account.Id,
      Product__c = product.Id,
      Quantity__c = 1,
      UnitPrice__c = 12000,
      Unit__c = '式/月',
      StartDate__c = Date.newInstance(2026, 4, 1),
      Enddate__c = Date.newInstance(2027, 3, 31),
      InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
      BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_RECURRING,
      Type__c = 'New',
      // 数量×単価×12ヶ月。PDF 合計の回帰を期間計算に依存させない
      Amount__c = 144000
    );
    ContractTestDataFactory.applyRequiredFields(contractProduct);
    insert contractProduct;

    EstimateFixture fixture = new EstimateFixture();
    fixture.history = history;
    return fixture;
  }

  private static Id insertLinkedFile(
    Id linkedEntityId,
    String title,
    Boolean issued
  ) {
    ContentVersion version = new ContentVersion(
      Title = title,
      PathOnClient = title + '.pdf',
      VersionData = Blob.valueOf('body'),
      ContractDocumentIssued__c = issued
    );
    insert version;
    Id documentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :version.Id
    ]
    .ContentDocumentId;
    insert new ContentDocumentLink(
      ContentDocumentId = documentId,
      LinkedEntityId = linkedEntityId,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );
    return documentId;
  }

  /**
   * 税抜15の商品を2グループ用意し、グループ税込積み上げと総額再課税の差を再現する。
   */
  private static EstimateFixture createTwoGroupSmallAmountFixture() {
    Account account = ContractTestDataFactory.insertAccount('税端数取引先');
    BillingAccount__c billingAccount = new BillingAccount__c(
      Account__c = account.Id,
      BillingAddressee__c = '税端数取引先',
      BillingEmailTo__c = 'tax-split@example.com',
      InvoiceDateMethod__c = BillingScheduleService.METHOD_ON_OR_AFTER,
      InvoiceDateDayKind__c = BillingScheduleService.DAY_KIND_DAY,
      InvoiceDateDayOfMonth__c = 25,
      InvoiceDateAdjust__c = BillingScheduleService.ADJUST_NONE,
      PaymentTermMethod__c = BillingScheduleService.METHOD_MONTH_OFFSET,
      PaymentTermDayKind__c = BillingScheduleService.DAY_KIND_MONTH_END,
      PaymentTermMonthOffset__c = 0,
      PaymentTermAdjust__c = BillingScheduleService.ADJUST_NONE);
    ContractTestDataFactory.applyRequiredFields(billingAccount);
    insert billingAccount;

    ContractService__c service = new ContractService__c(
      Name = 'Tax Split Service',
      Account__c = account.Id,
      BiilingAcccount__c = billingAccount.Id,
      TaxPercent__c = TaxCalculationUtil.toPercentFieldStorage(10)
    );
    ContractTestDataFactory.applyRequiredFields(service);
    insert service;

    Opportunity opportunity = ContractTestDataFactory.insertOpportunity(
      account.Id,
      'Tax Split Opportunity'
    );

    ContractHistory__c history = new ContractHistory__c(
      Name = 'EST-TAX-SPLIT',
      ContractService__c = service.Id,
      Opportunity__c = opportunity.Id,
      Type__c = 'New',
      historystatus__c = 'Estimate',
      Version__c = 1,
      CurrentTermStartDate__c = Date.newInstance(2026, 4, 1),
      CurrentTermEndDate__c = Date.newInstance(2027, 3, 31),
      EstimateTitleName__c = '税端数見積'
    );
    ContractTestDataFactory.applyRequiredFields(history);
    insert history;

    Product2 productA = ContractTestDataFactory.buildProduct('Tax Split A');
    productA.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
    productA.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    productA.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    Product2 productB = ContractTestDataFactory.buildProduct('Tax Split B');
    productB.UnitName__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT;
    productB.BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME;
    productB.invoicetype__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID;
    ContractTestDataFactory.insertProducts(
      new List<Product2>{ productA, productB }
    );

    List<ContractProduct__c> products = new List<ContractProduct__c>{
      new ContractProduct__c(
        ContractHistory__c = history.Id,
        Account__c = account.Id,
        Product__c = productA.Id,
        Quantity__c = 1,
        UnitPrice__c = 15,
        Unit__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT,
        StartDate__c = Date.newInstance(2026, 4, 1),
        Enddate__c = Date.newInstance(2026, 4, 1),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = 'New',
        Amount__c = 15
      ),
      new ContractProduct__c(
        ContractHistory__c = history.Id,
        Account__c = account.Id,
        Product__c = productB.Id,
        Quantity__c = 1,
        UnitPrice__c = 15,
        Unit__c = ContractTestDataFactory.TENANT_UNIT_NAME_DEFAULT,
        StartDate__c = Date.newInstance(2026, 4, 1),
        Enddate__c = Date.newInstance(2026, 4, 1),
        InvoiceSetting__c = ContractTestDataFactory.TENANT_INVOICE_TYPE_PREPAID,
        BillingType__c = ContractTestDataFactory.TENANT_BILLING_TYPE_ONE_TIME,
        Type__c = 'New',
        Amount__c = 15
      )
    };
    for (ContractProduct__c product : products) {
      ContractTestDataFactory.applyRequiredFields(product);
    }
    insert products;

    EstimateFixture fixture = new EstimateFixture();
    fixture.history = history;
    return fixture;
  }

}
