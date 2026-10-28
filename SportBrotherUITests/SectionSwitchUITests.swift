import XCTest

/// Bascule Nourriture ⇄ Sport par l'onglet dédié : chaque section doit s'afficher avec son contenu, plusieurs fois de suite.
final class SectionSwitchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSwitchingBackAndForthShowsEachSection() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "-section", "food"]
        app.launch()

        for _ in 0..<3 {
            XCTAssertTrue(app.buttons["Préparer la semaine"].waitForExistence(timeout: 5) || app.navigationBars.element.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Semaine'")).firstMatch.exists,
                          "La section Nourriture doit afficher la semaine")
            app.tabBars.buttons["Sport"].tap()
            XCTAssertTrue(app.buttons["Démarrer une séance"].waitForExistence(timeout: 5), "La section Sport doit afficher l'accueil Séance")

            app.tabBars.buttons["Repas"].tap()
            XCTAssertTrue(app.tabBars.buttons["Semaine"].waitForExistence(timeout: 5), "La barre Nourriture doit revenir")
            XCTAssertTrue(app.tabBars.buttons["Semaine"].isSelected, "L'onglet Semaine doit être sélectionné, pas l'onglet de bascule")
        }
    }

    func testSectionKeepsItsLastTab() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampleData", "-section", "food"]
        app.launch()

        app.tabBars.buttons["Recettes"].tap()
        app.tabBars.buttons["Sport"].tap()
        app.tabBars.buttons["Stats"].tap()
        XCTAssertTrue(app.tabBars.buttons["Stats"].isSelected)

        app.tabBars.buttons["Repas"].tap()
        XCTAssertTrue(app.tabBars.buttons["Recettes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Recettes"].isSelected, "Nourriture revient sur Recettes")

        app.tabBars.buttons["Sport"].tap()
        XCTAssertTrue(app.tabBars.buttons["Stats"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Stats"].isSelected, "Sport revient sur Stats")
    }
}
