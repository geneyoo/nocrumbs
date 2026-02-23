import XCTest

@testable import NoCrumbs

final class SecretRedactorTests: XCTestCase {

    /// Build a test token at runtime so the literal never appears in source
    /// (avoids GitHub push protection false positives).
    private func token(_ parts: String...) -> String {
        parts.joined()
    }

    // MARK: - Normal text passes through

    func testNormalTextUnchanged() {
        let input = "Add login screen with email validation"
        XCTAssertEqual(SecretRedactor.redact(input), input)
    }

    func testShortStringsUnchanged() {
        let input = "fix bug"
        XCTAssertEqual(SecretRedactor.redact(input), input)
    }

    func testEmptyString() {
        XCTAssertEqual(SecretRedactor.redact(""), "")
    }

    // MARK: - OpenAI / Anthropic keys

    func testOpenAIKey() {
        let key = token("sk-proj-", "abc123def456ghi789jkl012mno345pqr678")
        let input = "Use key \(key)"
        let result = SecretRedactor.redact(input)
        XCTAssertEqual(result, "Use key [REDACTED]")
        XCTAssertFalse(result.contains("sk-proj-"))
    }

    func testAnthropicKey() {
        let key = token("sk-ant-", "api03-abcdefghij1234567890abcdefghij")
        let input = "Set \(key) as the key"
        let result = SecretRedactor.redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("sk-ant-"))
    }

    // MARK: - AWS

    func testAWSAccessKeyID() {
        let key = token("AKIA", "IOSFODNN7EXAMPLE")
        let input = "aws_access_key_id = \(key)"
        let result = SecretRedactor.redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains(key))
    }

    // MARK: - GitHub tokens

    func testGitHubPAT() {
        let key = token("ghp_", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij")
        let input = "token: \(key)"
        let result = SecretRedactor.redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("ghp_"))
    }

    func testGitHubOAuth() {
        let key = token("gho_", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij")
        let input = "oauth \(key)"
        let result = SecretRedactor.redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("gho_"))
    }

    // MARK: - GitLab

    func testGitLabPAT() {
        let key = token("glpat-", "abcDEF123_ghiJKL456-mno")
        let input = "export GITLAB_TOKEN=\(key)"
        let result = SecretRedactor.redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("glpat-"))
    }

    // MARK: - Slack tokens

    func testSlackBotToken() {
        let key = token("xoxb-", "123456789012-", "1234567890123-", "abcdefghijABCDEFGHIJ")
        let input = "SLACK_TOKEN=\(key)"
        let result = SecretRedactor.redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("xoxb-"))
    }

    func testSlackUserToken() {
        let key = token("xoxp-", "123456789012-", "1234567890123-", "abcdefghijABCDEFGHIJ")
        let input = "use \(key)"
        let result = SecretRedactor.redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("xoxp-"))
    }

    // MARK: - JWT

    func testJWT() {
        let jwt = token(
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
            ".",
            "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0",
            ".",
            "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        )
        let input = "Authorization: Bearer \(jwt)"
        let result = SecretRedactor.redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("eyJhbGci"))
    }

    // MARK: - Key-value assignments

    func testPasswordAssignment() {
        let input = "Set password=SuperSecret123!"
        let result = SecretRedactor.redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("SuperSecret123!"))
    }

    func testAPIKeyAssignment() {
        let input = "api_key: my-secret-api-key-value"
        let result = SecretRedactor.redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("my-secret-api-key-value"))
    }

    func testTokenAssignment() {
        let input = "token = abc123secretvalue"
        let result = SecretRedactor.redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("abc123secretvalue"))
    }

    func testSecretColonAssignment() {
        let input = "secret: mysecretvalue123"
        let result = SecretRedactor.redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("mysecretvalue123"))
    }

    // MARK: - Multiple secrets

    func testMultipleSecrets() {
        let sk = token("sk-proj-", "abc123def456ghi789jkl0")
        let slack = token("xoxb-", "1234-5678-abcd")
        let input = "Use \(sk) with password=hunter2 and token=\(slack)"
        let result = SecretRedactor.redact(input)
        XCTAssertFalse(result.contains("sk-proj-"))
        XCTAssertFalse(result.contains("hunter2"))
        XCTAssertFalse(result.contains("xoxb-"))
    }

    // MARK: - Edge cases

    func testPartialMatchNotRedacted() {
        // "sk-" alone without 20+ chars shouldn't match
        let input = "The sk-short key"
        XCTAssertEqual(SecretRedactor.redact(input), input)
    }

    func testKeywordWithoutValue() {
        // "password" as a word without assignment shouldn't match
        let input = "Add password reset flow"
        XCTAssertEqual(SecretRedactor.redact(input), input)
    }

    func testCaseInsensitiveKeyValue() {
        let input = "PASSWORD=mysecret123"
        let result = SecretRedactor.redact(input)
        XCTAssertTrue(result.contains("[REDACTED]"))
        XCTAssertFalse(result.contains("mysecret123"))
    }
}
