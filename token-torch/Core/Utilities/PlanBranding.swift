import Foundation

/// Maps raw provider plan codes to their official marketing brand names.
///
/// No provider API returns the brand name directly: ChatGPT's `/wham/usage` reports `plan_type`
/// codes (`go`, `plus`, `pro`, `prolite`, ...) and Claude exposes only `subscriptionType` /
/// `rateLimitTier` from local credentials. This is the same client-side mapping approach used by
/// Codex CLI and CodexBar, with a safe fallback for unrecognised codes.
public enum PlanBranding {
    /// ChatGPT `plan_type` code -> brand name (Go / Plus / Pro / Pro Lite / ...).
    public static func chatGPT(_ planType: String?) -> String? {
        guard let raw = planType?.lowercased(), !raw.isEmpty else { return planType }
        switch raw {
            case "free", "guest": return "Free"
            case "go": return "Go"
            case "plus": return "Plus"
            case "pro": return "Pro"
            case "prolite": return "Pro Lite"
            case "team", "free_workspace": return "Team"
            case "business", "self_serve_business_usage_based", "enterprise_cbp_usage_based": return "Business"
            case "enterprise": return "Enterprise"
            case "edu", "education", "k12": return "Education"
            default: return raw.capitalized
        }
    }

    /// Claude `subscriptionType` (+ optional `rateLimitTier`) -> brand name (Pro / Max 5x / Max 20x / ...).
    public static func claude(subscriptionType: String?, rateLimitTier: String?) -> String? {
        guard let raw = subscriptionType?.lowercased(), !raw.isEmpty else { return subscriptionType }
        switch raw {
            case "pro": return "Pro"
            case "max":
                if let multiplier = maxMultiplier(from: rateLimitTier) { return "Max \(multiplier)" }
                return "Max"
            case "team": return "Team"
            case "enterprise": return "Enterprise"
            default: return raw.capitalized
        }
    }

    /// ChatGPT `plan_type` code -> fixed monthly USD list price (or nil for free/per-seat/custom tiers).
    public static func chatGPTPrice(_ planType: String?) -> String? {
        switch planType?.lowercased() {
            case "go": return "$8/mo"
            case "plus": return "$20/mo"
            case "prolite": return "$100/mo"
            case "pro": return "$200/mo"
            default: return nil
        }
    }

    /// Claude `subscriptionType` (+ optional `rateLimitTier`) -> fixed monthly USD list price (or nil).
    public static func claudePrice(subscriptionType: String?, rateLimitTier: String?) -> String? {
        switch subscriptionType?.lowercased() {
            case "pro": return "$20/mo"
            case "max":
                switch maxMultiplier(from: rateLimitTier) {
                    case "5x": return "$100/mo"
                    case "20x": return "$200/mo"
                    default: return nil
                }
            default: return nil
        }
    }

    /// GitHub `copilot_plan` (+ optional `access_type_sku`) -> brand name (Free / Pro / Max / ...).
    public static func copilot(copilotPlan: String?, accessTypeSKU: String?) -> String? {
        let plan = copilotPlan?.lowercased()
        let sku = accessTypeSKU?.lowercased()
        if sku == "free_limited_copilot" { return "Free" }
        guard let plan, !plan.isEmpty else { return copilotPlan }
        switch plan {
            case "individual", "free": return "Free"
            case "student": return "Student"
            case "pro", "individual_pro": return "Pro"
            case "pro_plus", "individual_pro_plus", "pro+": return "Pro+"
            case "individual_max": return "Max"
            case "business": return "Business"
            case "enterprise": return "Enterprise"
            default: return plan.capitalized
        }
    }

    /// GitHub Copilot -> fixed monthly USD list price (or nil for Free / Student / unknown).
    public static func copilotPrice(copilotPlan: String?, accessTypeSKU: String?) -> String? {
        let plan = copilotPlan?.lowercased()
        let sku = accessTypeSKU?.lowercased()
        if sku == "free_limited_copilot" { return nil }
        switch plan {
            case "individual", "free", "student": return nil
            case "pro", "individual_pro": return "$10/mo"
            case "pro_plus", "individual_pro_plus", "pro+": return "$39/mo"
            case "individual_max": return "$100/mo"
            case "business": return "$19/mo"
            case "enterprise": return "$39/mo"
            default: return nil
        }
    }

    /// Extracts the Max usage multiplier (e.g. `5x` / `20x`) from a `rateLimitTier` like `default_claude_max_20x`.
    private static func maxMultiplier(from rateLimitTier: String?) -> String? {
        guard let tier = rateLimitTier?.lowercased() else { return nil }
        if tier.contains("20x") { return "20x" }
        if tier.contains("5x") { return "5x" }
        return nil
    }
}
