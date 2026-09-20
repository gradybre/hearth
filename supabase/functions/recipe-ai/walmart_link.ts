/**
 * Pure Walmart product link canonicalization and shaping
 * (D-WALMART-001, plan P-HEARTH-WALMART-001).
 *
 * Zero dependencies: no imports, no network access. This module only
 * validates and canonicalizes candidate strings and shapes the raw model
 * output into the strict envelope described by the contract. It must be
 * conservative: any malformed, uncertain, ambiguous or unrecognized
 * candidate suppresses the link rather than guessing at intent.
 */

export type WalmartLinkStatus = "found" | "not_found" | "ambiguous" | "unreadable";
export type WalmartLinkSource = "nutrition" | "package" | "both" | "screenshot" | null;

export interface WalmartLinkEnvelope {
  status: WalmartLinkStatus;
  url: string | null;
  source: WalmartLinkSource;
}

const ALLOWED_HOSTS = new Set(["walmart.com", "www.walmart.com", "m.walmart.com"]);
const ALLOWED_CANDIDATE_SOURCES = new Set(["nutrition", "package", "screenshot"]);
const DIGITS_RE = /^\d{3,20}$/;
const SCHEME_RE = /^([a-zA-Z]+):\/\//;

function hasForbiddenChars(s: string): boolean {
  for (let i = 0; i < s.length; i++) {
    const code = s.charCodeAt(i);
    if (code <= 0x1f || code === 0x7f) return true; // control characters
  }
  if (s.includes("\\")) return true;
  if (/\s/.test(s)) return true; // interior whitespace (outer already trimmed)
  return false;
}

/**
 * Canonicalizes a raw candidate value into `https://www.walmart.com/ip/<id>`
 * or returns null if it is not a strictly valid Walmart product link.
 * Must stay in sync with lib/domain/shopping/walmart_link_reading.dart and
 * the accept/reject corpus in context/contracts.json.
 */
export function canonicalWalmartUrl(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  if (raw.length > 2048) return null;

  const trimmed = raw.trim();
  if (trimmed.length === 0) return null;
  if (hasForbiddenChars(trimmed)) return null;
  if (trimmed.startsWith("//")) return null; // scheme-relative

  let rest = trimmed;
  let scheme = "https";
  const schemeMatch = SCHEME_RE.exec(trimmed);
  if (schemeMatch !== null) {
    scheme = schemeMatch[1].toLowerCase();
    if (scheme !== "http" && scheme !== "https") return null;
    rest = trimmed.slice(schemeMatch[0].length);
  }

  const qIdx = rest.indexOf("?");
  const fIdx = rest.indexOf("#");
  let cut = rest.length;
  if (qIdx >= 0 && qIdx < cut) cut = qIdx;
  if (fIdx >= 0 && fIdx < cut) cut = fIdx;
  const preQuery = rest.slice(0, cut);

  if (preQuery.includes("%") || preQuery.includes("...") || preQuery.includes("\u2026")) return null;

  const slashIdx = preQuery.indexOf("/");
  if (slashIdx < 0) return null; // numeric-only or path-less input
  const authority = preQuery.slice(0, slashIdx);
  let path = preQuery.slice(slashIdx);
  if (authority.length === 0) return null;

  const authParts = authority.split(":");
  if (authParts.length > 2) return null;
  const host = authParts[0].toLowerCase();
  if (authParts.length === 2) {
    const port = authParts[1];
    if (port !== (scheme === "http" ? "80" : "443")) return null;
  }
  if (!ALLOWED_HOSTS.has(host)) return null;

  if (path.length > 1 && path.endsWith("/")) {
    path = path.slice(0, -1);
  }
  if (!path.startsWith("/ip/")) return null;

  const afterIp = path.slice(4);
  if (afterIp.length === 0) return null;
  const segments = afterIp.split("/");
  if (segments.length > 2) return null;
  if (segments.some((s) => s.length === 0)) return null;

  let idCandidate: string;
  if (segments.length === 1) {
    idCandidate = segments[0];
  } else {
    const slug = segments[0];
    if (slug === "." || slug === "..") return null;
    idCandidate = segments[1];
  }
  if (!DIGITS_RE.test(idCandidate)) return null;

  return `https://www.walmart.com/ip/${idCandidate}`;
}

/**
 * Shapes the raw model output `{walmart_candidates, walmart_unreadable}`
 * into the strict `{status, url, source}` envelope.
 *
 * `allowedSources` is the set of candidate sources permitted for this
 * request, derived upstream from validated image roles (never trusted from
 * the model). A candidate whose source is not in `allowedSources`, is not
 * one of the model-emittable sources (`nutrition`, `package`, `screenshot`
 * -- never a model-supplied `both`), is uncertain, or fails canonicalization
 * makes the whole result `unreadable` rather than silently dropping just
 * that candidate. `source: "both"` is only ever computed here, from two
 * distinct accepted sources that share one canonical URL.
 */
export function shapeWalmartLink(
  input: unknown,
  allowedSources: readonly string[],
): WalmartLinkEnvelope {
  const notFound: WalmartLinkEnvelope = { status: "not_found", url: null, source: null };
  const unreadable: WalmartLinkEnvelope = { status: "unreadable", url: null, source: null };

  if (input === null || input === undefined) return notFound;
  if (typeof input !== "object" || Array.isArray(input)) return unreadable;

  const obj = input as Record<string, unknown>;
  const hasCandidates = Object.prototype.hasOwnProperty.call(obj, "walmart_candidates");
  const hasFlag = Object.prototype.hasOwnProperty.call(obj, "walmart_unreadable");
  if (!hasCandidates && !hasFlag) return notFound;

  let unreadableFlag = false;
  if (hasFlag) {
    const flag = obj["walmart_unreadable"];
    if (typeof flag !== "boolean") return unreadable;
    unreadableFlag = flag;
  }

  if (!hasCandidates) {
    return unreadableFlag ? unreadable : notFound;
  }

  const candidatesRaw = obj["walmart_candidates"];
  if (!Array.isArray(candidatesRaw)) return unreadable;
  if (unreadableFlag) return unreadable;
  if (candidatesRaw.length === 0) return notFound;
  if (candidatesRaw.length > 10) return unreadable;

  const allowed = new Set(allowedSources);
  const accepted: { url: string; source: string }[] = [];

  for (const c of candidatesRaw) {
    if (c === null || typeof c !== "object" || Array.isArray(c)) return unreadable;
    const cand = c as Record<string, unknown>;
    const urlRaw = cand["url"];
    const sourceRaw = cand["source"];
    const uncertainRaw = cand["uncertain"];

    if (typeof urlRaw !== "string") return unreadable;
    if (typeof sourceRaw !== "string") return unreadable;
    if (typeof uncertainRaw !== "boolean") return unreadable;
    if (uncertainRaw) return unreadable;

    if (!ALLOWED_CANDIDATE_SOURCES.has(sourceRaw)) return unreadable; // never accept model 'both'
    if (!allowed.has(sourceRaw)) return unreadable;

    const canonical = canonicalWalmartUrl(urlRaw);
    if (canonical === null) return unreadable;

    accepted.push({ url: canonical, source: sourceRaw });
  }

  const distinctUrls = new Set(accepted.map((a) => a.url));
  if (distinctUrls.size === 0) return notFound;
  if (distinctUrls.size > 1) return { status: "ambiguous", url: null, source: null };

  const url = accepted[0].url;
  const distinctSources = new Set(accepted.map((a) => a.source));
  const source: WalmartLinkSource = distinctSources.size > 1
    ? "both"
    : (accepted[0].source as WalmartLinkSource);

  return { status: "found", url, source };
}
