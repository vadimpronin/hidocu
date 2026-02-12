import XCTest
@testable import LLMService

final class GeminiModelCatalogTests: XCTestCase {

    func testParseSingleModel() {
        let markdown = """
        ### Gemini 2.5 Pro

        | Property | Description |
        |---|---|
        | id_cardModel code | `gemini-2.5-pro` |
        | saveSupported data types | **Inputs** Text, Image, Video, Audio, and PDF **Output** Text |
        | token_autoToken limits^[\\[\\*\\]](https://ai.google.dev/gemini-api/docs/tokens)^ | **Input token limit** 1,048,576 **Output token limit** 65,536 |
        | handymanCapabilities | **Function calling** Supported **Thinking** Supported |
        """

        let catalog = GeminiModelCatalog.parse(markdown: markdown)

        XCTAssertEqual(catalog.count, 1)
        let model = catalog["gemini-2.5-pro"]
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.displayName, "Gemini 2.5 Pro")
        XCTAssertTrue(model?.supportsText ?? false)
        XCTAssertTrue(model?.supportsImage ?? false)
        XCTAssertTrue(model?.supportsAudio ?? false)
        XCTAssertTrue(model?.supportsVideo ?? false)
        XCTAssertTrue(model?.supportsThinking ?? false)
        XCTAssertTrue(model?.supportsTools ?? false)
        XCTAssertEqual(model?.maxInputTokens, 1_048_576)
        XCTAssertEqual(model?.maxOutputTokens, 65_536)
    }

    func testParseMultipleModels() {
        let markdown = """
        ### Gemini 2.5 Pro

        | Property | Description |
        |---|---|
        | id_cardModel code | `gemini-2.5-pro` |
        | saveSupported data types | **Inputs** Text, Image **Output** Text |
        | token_autoToken limits | **Input token limit** 1,048,576 **Output token limit** 65,536 |
        | handymanCapabilities | **Thinking** Supported **Function calling** Supported |

        ### Gemini 2.0 Flash

        | Property | Description |
        |---|---|
        | id_cardModel code | `gemini-2.0-flash` |
        | saveSupported data types | **Inputs** Audio, images, video, and text **Output** Text |
        | token_autoToken limits | **Input token limit** 1,048,576 **Output token limit** 8,192 |
        | handymanCapabilities | **Function calling** Supported **Thinking** Experimental |
        """

        let catalog = GeminiModelCatalog.parse(markdown: markdown)

        XCTAssertEqual(catalog.count, 2)
        XCTAssertNotNil(catalog["gemini-2.5-pro"])
        XCTAssertNotNil(catalog["gemini-2.0-flash"])

        // Gemini 2.0 Flash: Thinking is "Experimental", not "Supported"
        XCTAssertFalse(catalog["gemini-2.0-flash"]?.supportsThinking ?? true)
        XCTAssertTrue(catalog["gemini-2.0-flash"]?.supportsTools ?? false)
        XCTAssertEqual(catalog["gemini-2.0-flash"]?.maxOutputTokens, 8_192)

        // Supports audio/video from "Audio, images, video, and text"
        XCTAssertTrue(catalog["gemini-2.0-flash"]?.supportsAudio ?? false)
        XCTAssertTrue(catalog["gemini-2.0-flash"]?.supportsVideo ?? false)
        XCTAssertTrue(catalog["gemini-2.0-flash"]?.supportsImage ?? false)
    }

    func testParseSkipsExpandHeadings() {
        let markdown = """
        ### Expand to learn more

        ### Gemini 3 Pro Preview

        | Property | Description |
        |---|---|
        | id_cardModel code | `gemini-3-pro-preview` |
        | saveSupported data types | **Inputs** Text, Image, Video, Audio, and PDF **Output** Text |
        | token_autoToken limits | **Input token limit** 1,048,576 **Output token limit** 65,536 |
        | handymanCapabilities | **Function calling** Supported **Thinking** Supported |
        """

        let catalog = GeminiModelCatalog.parse(markdown: markdown)
        XCTAssertEqual(catalog.count, 1)
        XCTAssertNotNil(catalog["gemini-3-pro-preview"])
    }

    func testParseEmptyMarkdown() {
        let catalog = GeminiModelCatalog.parse(markdown: "")
        XCTAssertTrue(catalog.isEmpty)
    }

    func testParseNoTableRows() {
        let markdown = """
        ### Some Model
        This is just text, no table rows.
        """

        let catalog = GeminiModelCatalog.parse(markdown: markdown)
        // Has a heading but no model code, so nothing should be emitted
        XCTAssertTrue(catalog.isEmpty)
    }

    func testFallbackCatalogContainsKnownModels() {
        let fallback = GeminiModelCatalog.fallbackCatalog
        XCTAssertFalse(fallback.isEmpty)
        XCTAssertNotNil(fallback["gemini-2.5-pro"])
        XCTAssertNotNil(fallback["gemini-2.5-flash"])
        XCTAssertNotNil(fallback["gemini-2.0-flash"])
        XCTAssertNotNil(fallback["gemini-3-pro-preview"])
        XCTAssertNotNil(fallback["gemini-3-flash-preview"])
    }

    func testParseTokenLimitsWithCommas() {
        let markdown = """
        ### Test Model

        | Property | Description |
        |---|---|
        | id_cardModel code | `test-model` |
        | saveSupported data types | **Inputs** Text **Output** Text |
        | token_autoToken limits | **Input token limit** 131,072 **Output token limit** 8,192 |
        | handymanCapabilities | **Function calling** Not supported **Thinking** Not supported |
        """

        let catalog = GeminiModelCatalog.parse(markdown: markdown)
        let model = catalog["test-model"]
        XCTAssertEqual(model?.maxInputTokens, 131_072)
        XCTAssertEqual(model?.maxOutputTokens, 8_192)
        XCTAssertFalse(model?.supportsThinking ?? true)
        XCTAssertFalse(model?.supportsTools ?? true)
    }
}
