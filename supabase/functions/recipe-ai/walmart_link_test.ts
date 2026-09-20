import assert from "node:assert/strict";
import { canonicalWalmartUrl, shapeWalmartLink } from "./walmart_link.ts";

// Regression tests for D-WALMART-001 (plan P-HEARTH-WALMART-001).
// Includes two Astra findings that the current canonicalWalmartUrl
// implementation is expected to fail until repaired:
//  1. Non-default scheme/port pairs (https on :80, http on :443, and an
//     omitted (https-default) scheme paired with :80) must be rejected.
//  2. Percent-escapes, ellipsis, and whitespace-lookalikes appearing only
//     after the query delimiter must NOT cause rejection, since only the
//     pre-query authority/path is validated.

Deno.test("canonicalWalmartUrl - corpus accept", () => {
  const accepted: Record<string, string> = {
    "https://www.walmart.com/ip/10450479": "https://www.walmart.com/ip/10450479",
    "walmart.com/ip/Goldfish-30/10450479": "https://www.walmart.com/ip/10450479",
    "http://m.walmart.com:80/ip/123/": "https://www.walmart.com/ip/123",
    "HTTPS://WWW.WALMART.COM:443/ip/000123?tracking=anything#x": "https://www.walmart.com/ip/000123",
    " www.walmart.com/ip/12345678901234567890 ": "https://www.walmart.com/ip/12345678901234567890",
  };
  for (const [input, expected] of Object.entries(accepted)) {
    assert.equal(canonicalWalmartUrl(input), expected, `expected accept: ${input}`);
  }
});

Deno.test("canonicalWalmartUrl - corpus reject", () => {
  const rejected: string[] = [
    "10450479",
    "https://evil.com/ip/10450479",
    "https://walmart.com.evil.com/ip/123",
    "https://user@walmart.com/ip/123",
    "https://walmart.com:444/ip/123",
    "//walmart.com/ip/123",
    "https://walmart.com/search/123",
    "https://walmart.com/ip/12",
    "https://walmart.com/ip/123456789012345678901",
    "https://walmart.com/ip/a/b/123",
    "https://walmart.com/ip/Slug\u2026/123",
    "https://walmart.com/ip/%31%32%33",
    "https://walmart.com/ip/abc/../123",
    "https://walmart.com/ip/123/more",
    "https://walmart.com/ip/12 3",
    "https://w\u0430lmart.com/ip/123",
    "https://walmrt.us/abc",
    "https://walmart.com/ip/\uff11\uff12\uff13",
  ];
  for (const input of rejected) {
    assert.equal(canonicalWalmartUrl(input), null, `expected reject: ${input}`);
  }
});

Deno.test("canonicalWalmartUrl - non-default scheme/port must reject (Astra finding)", () => {
  assert.equal(
    canonicalWalmartUrl("https://walmart.com:80/ip/123"),
    null,
    "port 80 is only valid for http, not https",
  );
  assert.equal(
    canonicalWalmartUrl("http://walmart.com:443/ip/123"),
    null,
    "port 443 is only valid for https, not http",
  );
  assert.equal(
    canonicalWalmartUrl("walmart.com:80/ip/123"),
    null,
    "omitted scheme defaults to https; port 80 does not match",
  );
});

Deno.test("canonicalWalmartUrl - matching scheme/port pairs still accepted", () => {
  assert.equal(canonicalWalmartUrl("https://walmart.com:443/ip/123"), "https://www.walmart.com/ip/123");
  assert.equal(canonicalWalmartUrl("http://walmart.com:80/ip/123"), "https://www.walmart.com/ip/123");
});

Deno.test("canonicalWalmartUrl - query/fragment must not be validated (Astra finding)", () => {
  assert.equal(
    canonicalWalmartUrl("walmart.com/ip/123?x=%2F...#encoded%20"),
    "https://www.walmart.com/ip/123",
    "only the pre-query authority/path is validated",
  );
  assert.equal(
    canonicalWalmartUrl("https://www.walmart.com/ip/999?a=%00...\u2026#frag"),
    "https://www.walmart.com/ip/999",
  );
});

Deno.test("canonicalWalmartUrl - forbidden characters in the pre-query part still reject", () => {
  assert.equal(canonicalWalmartUrl("walmart.com/ip/1%202?tracking=abc"), null);
  assert.equal(canonicalWalmartUrl("walmart .com/ip/123?tracking=abc"), null);
  assert.equal(canonicalWalmartUrl("walmart.com/ip\\/123?tracking=abc"), null);
});

Deno.test("canonicalWalmartUrl - type and length guards", () => {
  assert.equal(canonicalWalmartUrl(12345), null);
  assert.equal(canonicalWalmartUrl(null), null);
  assert.equal(canonicalWalmartUrl(undefined), null);
  const longInput = "https://walmart.com/ip/" + "1".repeat(3000);
  assert.equal(canonicalWalmartUrl(longInput), null);
});

Deno.test("shapeWalmartLink - absent input is not_found", () => {
  assert.deepEqual(shapeWalmartLink(null, ["nutrition", "package", "screenshot"]), {
    status: "not_found",
    url: null,
    source: null,
  });
  assert.deepEqual(shapeWalmartLink(undefined, ["nutrition"]), {
    status: "not_found",
    url: null,
    source: null,
  });
});

Deno.test("shapeWalmartLink - non-object input is unreadable", () => {
  assert.equal(shapeWalmartLink("nonsense", ["nutrition"]).status, "unreadable");
  assert.equal(shapeWalmartLink(42, ["nutrition"]).status, "unreadable");
  assert.equal(shapeWalmartLink(["array"], ["nutrition"]).status, "unreadable");
});

Deno.test("shapeWalmartLink - walmart_unreadable true forces unreadable", () => {
  const result = shapeWalmartLink(
    { walmart_candidates: [], walmart_unreadable: true },
    ["nutrition", "package", "screenshot"],
  );
  assert.deepEqual(result, { status: "unreadable", url: null, source: null });
});

Deno.test("shapeWalmartLink - only walmart_unreadable present, false, is not_found", () => {
  const result = shapeWalmartLink({ walmart_unreadable: false }, ["nutrition"]);
  assert.deepEqual(result, { status: "not_found", url: null, source: null });
});

Deno.test("shapeWalmartLink - walmart_unreadable of wrong type is unreadable", () => {
  const result = shapeWalmartLink({ walmart_unreadable: "true" }, ["nutrition"]);
  assert.equal(result.status, "unreadable");
});

Deno.test("shapeWalmartLink - empty candidate array is not_found", () => {
  const result = shapeWalmartLink({ walmart_candidates: [] }, ["nutrition", "package", "screenshot"]);
  assert.deepEqual(result, { status: "not_found", url: null, source: null });
});

Deno.test("shapeWalmartLink - non-array walmart_candidates is unreadable", () => {
  const result = shapeWalmartLink({ walmart_candidates: "oops" }, ["nutrition"]);
  assert.equal(result.status, "unreadable");
});

Deno.test("shapeWalmartLink - more than 10 candidates is unreadable", () => {
  const candidates = Array.from({ length: 11 }, () => ({
    url: "https://www.walmart.com/ip/123",
    source: "nutrition",
    uncertain: false,
  }));
  const result = shapeWalmartLink({ walmart_candidates: candidates }, ["nutrition"]);
  assert.equal(result.status, "unreadable");
});

Deno.test("shapeWalmartLink - a single valid candidate is found with its source", () => {
  const result = shapeWalmartLink(
    {
      walmart_candidates: [
        { url: "https://www.walmart.com/ip/123", source: "package", uncertain: false },
      ],
    },
    ["package"],
  );
  assert.deepEqual(result, {
    status: "found",
    url: "https://www.walmart.com/ip/123",
    source: "package",
  });
});

Deno.test("shapeWalmartLink - candidate with uncertain true is unreadable", () => {
  const result = shapeWalmartLink(
    {
      walmart_candidates: [
        { url: "https://www.walmart.com/ip/123", source: "package", uncertain: true },
      ],
    },
    ["package"],
  );
  assert.equal(result.status, "unreadable");
});

Deno.test("shapeWalmartLink - candidate whose source is not in allowedSources is unreadable", () => {
  const result = shapeWalmartLink(
    {
      walmart_candidates: [
        { url: "https://www.walmart.com/ip/123", source: "screenshot", uncertain: false },
      ],
    },
    ["nutrition", "package"],
  );
  assert.equal(result.status, "unreadable");
});

Deno.test("shapeWalmartLink - model-supplied source 'both' is never accepted", () => {
  const result = shapeWalmartLink(
    {
      walmart_candidates: [
        { url: "https://www.walmart.com/ip/123", source: "both", uncertain: false },
      ],
    },
    ["nutrition", "package", "both"],
  );
  assert.equal(result.status, "unreadable");
});

Deno.test("shapeWalmartLink - candidate with an invalid URL is unreadable", () => {
  const result = shapeWalmartLink(
    {
      walmart_candidates: [
        { url: "https://evil.com/ip/123", source: "package", uncertain: false },
      ],
    },
    ["package"],
  );
  assert.equal(result.status, "unreadable");
});

Deno.test("shapeWalmartLink - malformed candidate fields are unreadable", () => {
  assert.equal(
    shapeWalmartLink(
      { walmart_candidates: [{ url: 5, source: "package", uncertain: false }] },
      ["package"],
    ).status,
    "unreadable",
  );
  assert.equal(
    shapeWalmartLink(
      { walmart_candidates: [{ url: "https://www.walmart.com/ip/123", source: 5, uncertain: false }] },
      ["package"],
    ).status,
    "unreadable",
  );
  assert.equal(
    shapeWalmartLink(
      { walmart_candidates: [{ url: "https://www.walmart.com/ip/123", source: "package" }] },
      ["package"],
    ).status,
    "unreadable",
  );
  assert.equal(
    shapeWalmartLink({ walmart_candidates: ["not an object"] }, ["package"]).status,
    "unreadable",
  );
  assert.equal(
    shapeWalmartLink({ walmart_candidates: [null] }, ["package"]).status,
    "unreadable",
  );
});

Deno.test("shapeWalmartLink - two distinct accepted URLs is ambiguous", () => {
  const result = shapeWalmartLink(
    {
      walmart_candidates: [
        { url: "https://www.walmart.com/ip/111", source: "nutrition", uncertain: false },
        { url: "https://www.walmart.com/ip/222", source: "package", uncertain: false },
      ],
    },
    ["nutrition", "package"],
  );
  assert.deepEqual(result, { status: "ambiguous", url: null, source: null });
});

Deno.test("shapeWalmartLink - identical URL from nutrition and package merges to 'both'", () => {
  const result = shapeWalmartLink(
    {
      walmart_candidates: [
        { url: "https://www.walmart.com/ip/123", source: "nutrition", uncertain: false },
        { url: "https://www.walmart.com/ip/123", source: "package", uncertain: false },
      ],
    },
    ["nutrition", "package"],
  );
  assert.deepEqual(result, {
    status: "found",
    url: "https://www.walmart.com/ip/123",
    source: "both",
  });
});

Deno.test("shapeWalmartLink - identical URL from the same source twice stays that source", () => {
  const result = shapeWalmartLink(
    {
      walmart_candidates: [
        { url: "https://www.walmart.com/ip/123", source: "screenshot", uncertain: false },
        { url: "https://www.walmart.com/ip/123", source: "screenshot", uncertain: false },
      ],
    },
    ["screenshot"],
  );
  assert.deepEqual(result, {
    status: "found",
    url: "https://www.walmart.com/ip/123",
    source: "screenshot",
  });
});
