# Caller authorization repair — D009

Release verification identified a pre-existing mismatch between the gateway assumption and the approved signed-in caller requirement. The handler now resolves current_household_id using the caller token before body processing, budget reservation or model calls. Missing/invalid credentials and absent membership are denied; unavailable or malformed authorization responses fail closed. Existing gateway verification, monthly ceiling, model and client response contract are preserved.

Independent Claude Opus reviewer session390cb296-567f-498a-b098-e09394165d9a accepted the repair after author session89e17bec-0900-4fe2-a4c8-4342d451d5f7 supplied the tests and implementation. All seven new boundary steps were observed failing before the fix. The repaired full server suites, type checks and changed-file lint pass. Existing unrelated visual and native evidence remains valid. Full reviews and live diagnostics remain in the release task records.

Live authenticated positive, unauthenticated negative and reservation/accounting checks remain release gates. No live positive result is claimed here. Both dependent server candidates must retain caller_auth.ts and the awaited guard above all body/budget handling.
