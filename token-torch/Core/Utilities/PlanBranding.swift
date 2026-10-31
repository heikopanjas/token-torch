import Foundation

/// Maps raw provider plan codes to their official marketing brand names.
///
/// No provider API returns the brand name directly: ChatGPT's `/wham/usage` reports `plan_type`
/// codes (`go`, `plus`, `pro`, `prolite`, ...) and Claude exposes only `subscriptionType` /
/// `rateLimitTier` from local credentials. This is the same client-side mapping approach used by
/// Codex CLI and CodexBar, with a safe fallback for unrecognised codes.
public enum PlanBranding {
    /// ChatGPT `plan_type` code -> brand name (Go / Plus / Pro 100 / Pro 200 / ...). The Pro tiers carry OpenAI's
    /// current price-based names, not the older usage-multiplier names (`prolite` was "Pro Lite").
    public static func chatGPT(_ planType: String?) -> String? {
        guard let raw = planType?.lowercased(), raw.isEmpty == false else { return planType }
        switch raw {
            case "free", "guest": return "Free"
            case "go": return "Go"
            case "plus": return "Plus"
            case "prolite": return "Pro 100"
            case "pro": return "Pro 200"
            case "promax": return "Pro 500"
            case "team", "free_workspace": return "Team"
            case "self_serve_business_prolite": return "Business Premium"
            case "business", "self_serve_business_usage_based", "enterprise_cbp_usage_based": return "Business"
            case "enterprise": return "Enterprise"
            case "edu", "education", "k12": return "Education"
            default: return raw.capitalized
        }
    }

    /// Claude `subscriptionType` (+ optional `rateLimitTier`) -> brand name (Pro / Max / Ultra / ...). Anthropic renamed
    /// Max 5x to Max and Max 20x to Ultra on 2026-10-30; the tier still carries the old multiplier.
    public static func claude(subscriptionType: String?, rateLimitTier: String?) -> String? {
        guard let raw = subscriptionType?.lowercased(), raw.isEmpty == false else { return subscriptionType }
        switch Self.claudeIndividualPlan(subscriptionType: raw, rateLimitTier: rateLimitTier) {
            case .max: return "Max"
            case .ultra: return "Ultra"
            case nil: break
        }
        switch raw {
            case "pro": return "Pro"
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
            case "promax": return "$500/mo"
            default: return nil
        }
    }

    /// Claude `subscriptionType` (+ optional `rateLimitTier`) -> fixed monthly USD list price (or nil). A `max` plan
    /// without a recognized tier has no price: it can't be told apart from a not yet migrated Ultra account.
    public static func claudePrice(subscriptionType: String?, rateLimitTier: String?) -> String? {
        let raw = subscriptionType?.lowercased()
        switch Self.claudeIndividualPlan(subscriptionType: raw, rateLimitTier: rateLimitTier) {
            case .ultra: return "$200/mo"
            case .max: return rateLimitTier?.lowercased().contains("5x") == true ? "$100/mo" : nil
            case nil: return raw == "pro" ? "$20/mo" : nil
        }
    }

    /// GitHub `copilot_plan` (+ optional `access_type_sku`) -> brand name (Free / Pro / Max / ...).
    public static func copilot(copilotPlan: String?, accessTypeSKU: String?) -> String? {
        let plan = copilotPlan?.lowercased()
        let sku = accessTypeSKU?.lowercased()
        if sku == "free_limited_copilot" { return "Free" }
        guard let plan, plan.isEmpty == false else { return copilotPlan }
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

    /// Claude's paid individual tiers above Pro.
    private enum ClaudeIndividualPlan {
        case max
        case ultra
    }

    /// Resolves Max vs Ultra from a lowercased `subscriptionType` and a `rateLimitTier` such as `default_claude_max_20x`.
    /// Credentials issued before the rename keep `max` with the `20x` tier, so that tier reads as Ultra.
    private static func claudeIndividualPlan(subscriptionType: String?, rateLimitTier: String?) -> ClaudeIndividualPlan? {
        switch subscriptionType {
            case "ultra": return .ultra
            case "max":
                let tier = rateLimitTier?.lowercased() ?? ""
                return (tier.contains("ultra") || tier.contains("20x")) == true ? .ultra : .max
            default: return nil
        }
    }
}
