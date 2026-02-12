import Foundation

/// Cleans JSON schemas for Antigravity API compatibility.
/// Matches the Go reference implementation `util.CleanJSONSchemaForAntigravity` / `CleanJSONSchemaForGemini`.
/// Handles unsupported keywords, type flattening, and adds placeholders for Claude VALIDATED mode.
enum AntigravitySchemaCleaner {

    private static let placeholderDescription = "Brief explanation of why you are calling this tool"

    /// Maximum recursion depth to guard against malformed circular schemas.
    private static let maxDepth = 50

    /// Keywords that are unsupported constraints — moved to description hints before removal.
    private static let unsupportedConstraints: Set<String> = [
        "minLength", "maxLength", "exclusiveMinimum", "exclusiveMaximum",
        "pattern", "minItems", "maxItems", "format", "default", "examples",
    ]

    /// All keywords to remove from schemas.
    private static let allUnsupportedKeywords: Set<String> = unsupportedConstraints.union([
        "$schema", "$defs", "definitions", "const", "$ref", "additionalProperties",
        "propertyNames",
    ])

    // MARK: - Public API

    /// Clean an array of function declarations for Antigravity API (Claude VALIDATED mode).
    /// Applies full schema cleaning + empty schema placeholders.
    static func cleanFunctionDeclarations(_ declarations: [[String: Any]]) -> [[String: Any]] {
        declarations.map { decl in
            var result = decl
            if let params = result["parameters"] as? [String: Any] {
                var cleaned = cleanSchema(params)
                cleaned = addEmptySchemaPlaceholders(cleaned, isTopLevel: true)
                result["parameters"] = cleaned
            }
            return result
        }
    }

    /// Clean an array of function declarations for Gemini API (non-Claude models via Antigravity).
    /// Applies schema cleaning + removes nullable/title. No empty schema placeholders.
    static func cleanFunctionDeclarationsForGemini(_ declarations: [[String: Any]]) -> [[String: Any]] {
        declarations.map { decl in
            var result = decl
            if let params = result["parameters"] as? [String: Any] {
                var cleaned = cleanSchema(params)
                cleaned = removeKeywordsRecursively(cleaned, keys: ["nullable", "title"])
                result["parameters"] = cleaned
            }
            return result
        }
    }

    // MARK: - Core Cleaning

    /// Recursively clean a JSON schema dictionary for API compatibility.
    static func cleanSchema(_ schema: [String: Any], depth: Int = 0) -> [String: Any] {
        guard depth < maxDepth else { return schema }

        var result = schema

        // Phase 1: Convert $ref to description hints (before $ref is removed)
        convertRefsToHints(&result)

        // Phase 2: Convert const to enum (before removing const)
        if let constVal = result["const"], result["enum"] == nil {
            result["enum"] = [constVal]
        }

        // Phase 3: Convert enum values to strings (Gemini requires string enums)
        if let enumVals = result["enum"] as? [Any] {
            result["enum"] = enumVals.map { "\($0)" }
            result["type"] = "string"
        }

        // Phase 4: Add enum hints to description (for enums with 2-10 values)
        addEnumHints(&result)

        // Phase 5: Add additionalProperties hints before removal
        addAdditionalPropertiesHints(&result)

        // Phase 6: Move constraint values into description before removing
        moveConstraintsToDescription(&result)

        // Phase 7: Merge allOf into parent
        mergeAllOf(&result)

        // Phase 8: Flatten anyOf/oneOf — pick the most structured schema
        flattenComposites(&result)

        // Phase 9: Flatten type arrays — take first non-null type, add hints.
        // Matches Go `flattenTypeArrays`: nullable hint + multi-type hint.
        if let typeArr = result["type"] as? [Any] {
            let types = typeArr.compactMap { $0 as? String }
            let hasNull = types.contains("null")
            let nonNull = types.filter { $0 != "null" }
            result["type"] = nonNull.first ?? "string"

            if nonNull.count > 1 {
                appendHint(&result, "Accepts: \(nonNull.joined(separator: " | "))")
            }
            if hasNull {
                appendHint(&result, "(nullable)")
                result["_isNullable"] = true // marker for parent to remove from required
            }
        }

        // Phase 10: Remove unsupported keywords
        for key in allUnsupportedKeywords {
            result.removeValue(forKey: key)
        }

        // Phase 11: Remove x-* extension fields
        let extensionKeys = result.keys.filter { $0.hasPrefix("x-") }
        for key in extensionKeys {
            result.removeValue(forKey: key)
        }

        // Phase 12: Recurse into properties and collect nullable field names
        var nullableFields: [String] = []
        if var props = result["properties"] as? [String: Any] {
            for (key, value) in props {
                if var propSchema = value as? [String: Any] {
                    propSchema = cleanSchema(propSchema, depth: depth + 1)
                    // Check and consume nullable marker from Phase 9
                    if propSchema["_isNullable"] as? Bool == true {
                        nullableFields.append(key)
                        propSchema.removeValue(forKey: "_isNullable")
                    }
                    props[key] = propSchema
                }
            }
            result["properties"] = props
        }

        // Remove nullable fields from required array (matches Go flattenTypeArrays lines 406-425)
        if !nullableFields.isEmpty, let required = result["required"] as? [String] {
            let filtered = required.filter { !nullableFields.contains($0) }
            if filtered.isEmpty {
                result.removeValue(forKey: "required")
            } else {
                result["required"] = filtered
            }
        }

        // Phase 13: Recurse into items
        if let items = result["items"] as? [String: Any] {
            result["items"] = cleanSchema(items, depth: depth + 1)
        }

        // Phase 14: Cleanup required fields — remove entries referencing missing properties
        cleanupRequired(&result)

        return result
    }

    // MARK: - Empty Schema Placeholders

    /// Add placeholder properties to empty object schemas.
    /// Claude VALIDATED mode requires at least one required property in tool schemas.
    /// - Parameter isTopLevel: When true, skips the "_" placeholder for objects with properties but no required.
    ///   Matches Go reference behavior at `addEmptySchemaPlaceholder` lines 573-578.
    static func addEmptySchemaPlaceholders(_ schema: [String: Any], isTopLevel: Bool = false, depth: Int = 0) -> [String: Any] {
        guard depth < maxDepth else { return schema }

        var result = schema

        // Recurse into properties first (deepest first)
        if var props = result["properties"] as? [String: Any] {
            for (key, value) in props {
                if let propSchema = value as? [String: Any] {
                    props[key] = addEmptySchemaPlaceholders(propSchema, isTopLevel: false, depth: depth + 1)
                }
            }
            result["properties"] = props
        }

        // Recurse into items
        if let items = result["items"] as? [String: Any] {
            result["items"] = addEmptySchemaPlaceholders(items, isTopLevel: false, depth: depth + 1)
        }

        guard (result["type"] as? String) == "object" else { return result }

        let props = result["properties"] as? [String: Any]
        let required = result["required"] as? [String] ?? []
        let hasProperties = props != nil && !(props?.isEmpty ?? true)

        if !hasProperties {
            // Empty object: add "reason" placeholder
            var newProps = props ?? [:]
            newProps["reason"] = [
                "type": "string",
                "description": placeholderDescription,
            ] as [String: Any]
            result["properties"] = newProps
            result["required"] = ["reason"]
        } else if required.isEmpty && !isTopLevel {
            // Has properties but none required (non-top-level only): add "_" placeholder
            var newProps = props!
            if newProps["_"] == nil {
                newProps["_"] = ["type": "boolean"] as [String: Any]
            }
            result["properties"] = newProps
            result["required"] = ["_"]
        }

        return result
    }

    // MARK: - Phase Helpers

    /// Convert `$ref` values to description hints before `$ref` is removed.
    /// Matches Go `convertRefsToHints`: replaces entire parent schema with `{"type":"object","description":"See: TypeName"}`.
    private static func convertRefsToHints(_ schema: inout [String: Any]) {
        guard let ref = schema["$ref"] as? String else { return }

        let defName: String
        if let lastSlash = ref.lastIndex(of: "/") {
            defName = String(ref[ref.index(after: lastSlash)...])
        } else {
            defName = ref
        }

        let hint = "See: \(defName)"
        let existing = schema["description"] as? String ?? ""
        let desc = existing.isEmpty ? hint : "\(existing) (\(hint))"

        // Replace entire schema to match Go reference (discards all sibling keys)
        schema = ["type": "object", "description": desc]
    }

    /// Add "Allowed: val1, val2" hint for enums with 2-10 values.
    /// Matches Go `addEnumHints`.
    private static func addEnumHints(_ schema: inout [String: Any]) {
        guard let enumVals = schema["enum"] as? [Any] else { return }
        let stringVals = enumVals.compactMap { $0 as? String }
        guard stringVals.count >= 2, stringVals.count <= 10 else { return }

        let hint = "Allowed: \(stringVals.joined(separator: ", "))"
        appendHint(&schema, hint)
    }

    /// Add "No extra properties allowed" hint when additionalProperties is false.
    /// Matches Go `addAdditionalPropertiesHints`.
    private static func addAdditionalPropertiesHints(_ schema: inout [String: Any]) {
        if let addProps = schema["additionalProperties"] as? Bool, addProps == false {
            appendHint(&schema, "No extra properties allowed")
        }
    }

    /// Move unsupported constraint values into description before they are removed.
    /// Matches Go `moveConstraintsToDescription`.
    private static func moveConstraintsToDescription(_ schema: inout [String: Any]) {
        var hints: [String] = []

        for constraint in unsupportedConstraints {
            if let val = schema[constraint] {
                if val is [Any] || val is [String: Any] { continue }
                hints.append("\(constraint): \(val)")
            }
        }

        if !hints.isEmpty {
            appendHint(&schema, hints.joined(separator: ", "))
        }
    }

    /// Merge allOf items into parent schema.
    /// Matches Go `mergeAllOf`.
    private static func mergeAllOf(_ schema: inout [String: Any]) {
        guard let allOf = schema["allOf"] as? [[String: Any]] else { return }

        var mergedProps = (schema["properties"] as? [String: Any]) ?? [:]
        var mergedRequired = (schema["required"] as? [String]) ?? []

        for item in allOf {
            if let itemProps = item["properties"] as? [String: Any] {
                for (key, value) in itemProps {
                    mergedProps[key] = value
                }
            }
            if let itemReq = item["required"] as? [String] {
                for r in itemReq where !mergedRequired.contains(r) {
                    mergedRequired.append(r)
                }
            }
        }

        if !mergedProps.isEmpty { schema["properties"] = mergedProps }
        if !mergedRequired.isEmpty { schema["required"] = mergedRequired }
        schema.removeValue(forKey: "allOf")
    }

    /// Flatten anyOf/oneOf — pick the most structured schema, add "Accepts:" hints, merge parent description.
    /// Matches Go `flattenAnyOfOneOf` + `selectBest`.
    private static func flattenComposites(_ schema: inout [String: Any]) {
        for compositeKey in ["anyOf", "oneOf"] {
            guard let items = schema[compositeKey] as? [[String: Any]], !items.isEmpty else { continue }

            // Find the best (most complex) schema and collect all type names
            var bestIdx = 0
            var bestScore = -1
            var allTypes: [String] = []

            for (i, item) in items.enumerated() {
                let (score, typeName) = schemaComplexityWithType(item)
                if !typeName.isEmpty { allTypes.append(typeName) }
                if score > bestScore {
                    bestScore = score
                    bestIdx = i
                }
            }

            var selected = items[bestIdx]

            // Merge parent description into selected schema
            if let parentDesc = schema["description"] as? String, !parentDesc.isEmpty {
                let childDesc = selected["description"] as? String ?? ""
                if childDesc.isEmpty {
                    selected["description"] = parentDesc
                } else if childDesc != parentDesc {
                    selected["description"] = "\(parentDesc) (\(childDesc))"
                }
            }

            // Add "Accepts:" hint for multi-type unions
            if allTypes.count > 1 {
                appendHint(&selected, "Accepts: \(allTypes.joined(separator: " | "))")
            }

            // Merge selected schema into parent (without overwriting existing keys)
            for (k, v) in selected where schema[k] == nil {
                schema[k] = v
            }
            schema.removeValue(forKey: compositeKey)
        }
    }

    // MARK: - Utility Helpers

    /// Score schema complexity and infer type name for anyOf/oneOf selection.
    /// Returns (score, typeName) where object=3 > array=2 > primitive=1 > null=0.
    /// Matches Go `selectBest`.
    private static func schemaComplexityWithType(_ schema: [String: Any]) -> (score: Int, typeName: String) {
        let type = schema["type"] as? String ?? ""
        if type == "object" || schema["properties"] != nil {
            return (3, type.isEmpty ? "object" : type)
        }
        if type == "array" || schema["items"] != nil {
            return (2, type.isEmpty ? "array" : type)
        }
        if !type.isEmpty && type != "null" {
            return (1, type)
        }
        return (0, type.isEmpty ? "null" : type)
    }

    /// Append a hint to the description field.
    private static func appendHint(_ schema: inout [String: Any], _ hint: String) {
        let existing = (schema["description"] as? String) ?? ""
        schema["description"] = existing.isEmpty ? hint : "\(existing) (\(hint))"
    }

    /// Remove required entries that reference properties not present in the schema.
    private static func cleanupRequired(_ schema: inout [String: Any]) {
        guard let required = schema["required"] as? [String],
              let props = schema["properties"] as? [String: Any]
        else { return }

        let valid = required.filter { props[$0] != nil }
        if valid.isEmpty {
            schema.removeValue(forKey: "required")
        } else if valid.count != required.count {
            schema["required"] = valid
        }
    }

    /// Recursively remove specific keywords from a schema (used for Gemini mode to remove nullable/title).
    private static func removeKeywordsRecursively(_ schema: [String: Any], keys: [String], depth: Int = 0) -> [String: Any] {
        guard depth < maxDepth else { return schema }

        var result = schema
        for key in keys {
            result.removeValue(forKey: key)
        }

        if var props = result["properties"] as? [String: Any] {
            for (key, value) in props {
                if let propSchema = value as? [String: Any] {
                    props[key] = removeKeywordsRecursively(propSchema, keys: keys, depth: depth + 1)
                }
            }
            result["properties"] = props
        }

        if let items = result["items"] as? [String: Any] {
            result["items"] = removeKeywordsRecursively(items, keys: keys, depth: depth + 1)
        }

        return result
    }
}
