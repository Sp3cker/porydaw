import PorydawProject

// Task 18: proof.voicegroupsourcecatalog.txt retires with the dead catalog
// write/UI surface (R5) — zero catalog-proof rows are ported into the Swift
// projectstore suites, and the ported ledgers keep their audited row counts.
//
// Editing ledger (98 rows): 90 ported; 8 unported — A002 (retired Qt
// session-pointer guard), A086–A092 (retired createVoicegroup/include flow).
// Save-core ledger (81 rows): 1 exact bank-level row ported (A079);
// A051/A076 are PARTIAL (bank-level half only); 78 widget/SongDocument/Qt
// rows keep their GAP disposition.
internal func runVoicegroupCatalogAbsentSuite(_ report: CheckReport) {
    let cppID = "voicegroupsourcecatalog/retired"
    report.expectEqual(90, voicegroupEditingRowIDs.count, cppID: cppID,
                       what: "editing ledger ports 90 of 98 rows, audited retirements recorded")
    report.expectEqual(1, saveCoreRowIDs.count, cppID: cppID,
                       what: "save-core ledger ports 1 of 81 exact rows, audited retirements recorded")

    let portedNames = voicegroupEditingRowIDs.map { "voicegroupsourceediting/\($0)" }
        + saveCoreRowIDs.map { "savecore/\($0)" }
    report.expect(portedNames.allSatisfy { !$0.hasPrefix("voicegroupsourcecatalog/") },
                  cppID: cppID,
                  message: "no ported check name derives from the retired catalog proof")
}
