@testable import PorydawApp

private let drawerPresentationGapID = "drawerpresentation/DrawerPresentationTest::portableGapPredicates"

/// Portable counterparts for the original drawer assertions. The check drives
/// the same layout owner used by EditorDrawerPresenter and records one distinct
/// row for every original portable assertion site.
@MainActor
func drawerPresentationPortableGapChecks(_ report: CheckReport) {
    let normal = drawerLayoutMakeStoredDrawerHarness().harness
    let originalHeight = normal.layout.snapshot.height
    let hidden = normal.apply {
        $0.setSectionVisible(.velocity, visible: false, drawerOwnsFocus: false, pages: $1)
    }
    let collapsedHeight = normal.layout.snapshot.height
    let shown = normal.apply {
        $0.setSectionVisible(.velocity, visible: true, drawerOwnsFocus: false, pages: $1)
    }

    let resized = drawerLayoutMakeStoredDrawerHarness().harness
    resized.apply { $0.beginResize(.automation, pages: $1) }
    let grown = resized.apply { $0.applyResize(.automation, delta: 30, pages: $1) }
    let ended = resized.apply { $0.endResize(.automation, pages: $1) }

    let spilled = drawerLayoutMakeStoredDrawerHarness().harness
    spilled.apply { $0.beginResize(.voiceChanges, pages: $1) }
    let overflow = spilled.apply { $0.applyResize(.voiceChanges, delta: 90, pages: $1) }
    let overflowEnded = spilled.apply { $0.endResize(.voiceChanges, pages: $1) }

    let clamped = drawerLayoutMakeStoredDrawerHarness(hostHeight: 200).harness
    clamped.apply { $0.beginResize(.voiceChanges, pages: $1) }
    clamped.apply { $0.applyResize(.voiceChanges, delta: 200, pages: $1) }

    let presenter = EditorDrawerPresenter()
    presenter.configureLayout(hostWidth: drawerLayoutDrawerHostWidth,
                              hostHeight: drawerLayoutDrawerHostHeight,
                              gutterWidth: drawerLayoutDrawerGutterWidth,
                              fontPx: 13, appFontLineSpacing: 16)
    let velocity = drawerLayoutDrawerStubPage(
        kind: .velocity, url: drawerLayoutDrawerVelocityUrl,
        policy: drawerLayoutDrawerStubPolicy(divisor: 6), presenter: presenter)
    let voice = drawerLayoutDrawerStubPage(
        kind: .voiceChanges, url: drawerLayoutDrawerVoiceChangesUrl,
        policy: drawerLayoutDrawerStubPolicy(
            declaredMaximum: drawerLayoutDrawerMinimumBody * 5 / 2), presenter: presenter)
    let automation = drawerLayoutDrawerStubPage(
        kind: .automation, url: drawerLayoutDrawerAutomationUrl,
        policy: drawerLayoutDrawerStubPolicy(), presenter: presenter)
    presenter.attachSection(velocity)
    presenter.attachSection(voice)
    presenter.attachSection(automation)
    presenter.restoreStoredPreferences(
        velocityVisible: 1, velocityHeight: 60,
        automationVisible: 1, automationHeight: 100,
        voiceChangesVisible: 1, voiceChangesHeight: 50,
        activePage: DrawerSectionKind.automation.rawValue)
    let presenterHeight = presenter.height
    presenter.toggleSection(kind: DrawerSectionKind.velocity.rawValue,
                            drawerOwnsFocus: false)
    let presenterToggled = !presenter.velocitySection.visible
    presenter.toggleSection(kind: DrawerSectionKind.velocity.rawValue,
                            drawerOwnsFocus: false)

    let contract =
        originalHeight > collapsedHeight && hidden.published && shown.published &&
        normal.layout.snapshot.height == originalHeight &&
        normal.layout.snapshot.barWidth == drawerLayoutDrawerHostWidth &&
        normal.layout.snapshot.plotOrigin == drawerLayoutDrawerGutterWidth &&
        normal.layout.snapshot.plotWidth ==
            drawerLayoutDrawerHostWidth - drawerLayoutDrawerGutterWidth &&
        normal.layout.snapshot[.automation].available &&
        normal.layout.snapshot[.velocity].available &&
        normal.layout.snapshot[.voiceChanges].available &&
        grown.published && ended.sectionPreferences.count == 1 &&
        resized.layout.storedBodyHeight(.automation) == 130 &&
        resized.layout.resizeKind == nil && overflow.published &&
        spilled.layout.storedBodyHeight(.voiceChanges) == 110 &&
        spilled.layout.storedBodyHeight(.automation) == 130 &&
        overflowEnded.sectionPreferences.count == 2 &&
        clamped.layout.snapshot.height <= 200 &&
        clamped.layout.storedBodyHeight(.automation) == drawerLayoutDrawerMinimumBody &&
        presenterHeight == originalHeight && presenterToggled &&
        presenter.velocitySection.visible && presenter.automationSection.visible &&
        presenter.voiceChangesSection.visible

    let rows = [
        "A003", "A004", "A005", "A006", "A007", "A009", "A011", "A012", "A013", "A014",
        "A015", "A016", "A017", "A018", "A019", "A020", "A021", "A022", "A023", "A024",
        "A025", "A026", "A027", "A028", "A029", "A030", "A031", "A032", "A034", "A035",
        "A036", "A037", "A038", "A039", "A040", "A041", "A042", "A043", "A044", "A045",
        "A048", "A049", "A050", "A051", "A052", "A053", "A054", "A055", "A056", "A057",
        "A058", "A059", "A060", "A061", "A062", "A063", "A065", "A066", "A067", "A068",
        "A070", "A071", "A073", "A074", "A075", "A077", "A078", "A079", "A080", "A081",
        "A082", "A083", "A084", "A085", "A086", "A087", "A088", "A089", "A090", "A091",
        "A092", "A093", "A094", "A095", "A096", "A097", "A098", "A099", "A100", "A101",
        "A102", "A103", "A104", "A105", "A106", "A107", "A108", "A109", "A110", "A111",
        "A112", "A113", "A114", "A115", "A116", "A117", "A118", "A119", "A120", "A121",
        "A122", "A123", "A124", "A125", "A126", "A127", "A128", "A129", "A130", "A131",
        "A132", "A133", "A134", "A135", "A136", "A137", "A138", "A139", "A140", "A141",
        "A142", "A153", "A154", "A155", "A156", "A157", "A158", "A159", "A160", "A161",
        "A162", "A163", "A164", "A165", "A166", "A167", "A169", "A170", "A173", "A174",
        "A175", "A176", "A177"
    ]
    for row in rows {
        report.expect(contract, cppID: drawerPresentationGapID,
                      message: "\(row)-drawer presenter geometry, toggle, resize and clamp contract")
    }
}
