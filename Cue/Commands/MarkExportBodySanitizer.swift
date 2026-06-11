import Foundation

enum MarkExportBodySanitizer {
    static func hasSubstantiveContent(_ body: String) -> Bool {
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            if trimmed.range(of: #"^#{1,6}\s"#, options: .regularExpression) != nil {
                continue
            }

            return true
        }

        return false
    }
}
