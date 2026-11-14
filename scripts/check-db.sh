#!/usr/bin/env bash
# Supabase migrations + pgTAP tests against the LOCAL stack only. Skips until supabase/ exists.
set -euo pipefail
cd "$(dirname "$0")/.." 
[ -d supabase/migrations ] || { echo "supabase/ not present yet: skipped"; exit 0; }
supabase status >/dev/null 2>&1 || supabase start -x studio,imgproxy,vector,logflare,edge-runtime >/dev/null
supabase db reset --local >/dev/null
supabase test db --local 2>&1 | tail -40
exit "${PIPESTATUS[0]}"
