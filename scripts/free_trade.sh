#!/usr/bin/env bash
# ============================================================================
# free_trade.sh — zero-cost crypto research + swap-quote stack
# ----------------------------------------------------------------------------
# Every data source below is FREE and needs NO API key / NO subscription:
#
#   GMGN openapi (public demo key)  token info, security, pool, top holders,
#                                   top traders, kline
#   DexScreener                    DEX pairs, liquidity, volume, price change
#   GeckoTerminal                  trending pools, pool detail
#   ParaSwap                       EVM swap quotes (best-price routing)
#   Li.Fi                          EVM swap + cross-chain bridge quotes
#   Binance public                 CEX reference price + klines
#   Public RPC                     on-chain reads, gas estimate
#
# Execution layer (separate, needs your own wallet):
#   baw market-order quote/swap    Binance Agentic Wallet, 7 chains
#   evm_tx.py                      raw EVM signing for any chain
#
# NO CLAWBY. NO SUBSCRIPTION. NO KEY. NO ACCOUNT.
#
# Verified 2026-11-08 against live endpoints.
# ============================================================================
set -uo pipefail

VERSION="1.1.0"
UA="free-trade/${VERSION} (+https://github.com/BOZAGENTIC/free-trade-stack)"
TMP="${TMPDIR:-/tmp}/free_trade.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

# ---- colours (auto-off when not a tty) --------------------------------------
if [ -t 1 ]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; M=$'\e[35m'; C=$'\e[36m'
  DIM=$'\e[2m'; BOLD=$'\e[1m'; N=$'\e[0m'
else
  R=""; G=""; Y=""; B=""; M=""; C=""; DIM=""; BOLD=""; N=""
fi

# ---- defaults ---------------------------------------------------------------
GMGN_BASE="https://openapi.gmgn.ai"
GMGN_KEY="${GMGN_API_KEY:-gmgn_solbscbaseethmonadtron}"   # public demo key
CHAIN_DEFAULT="56"
TIMEOUT="${FT_TIMEOUT:-25}"

# ---- helpers ----------------------------------------------------------------
hr()  { printf '%s\n' "${DIM}$(printf '%.0s─' {1..66})${N}"; }
hdr() { printf '\n%s%s %s %s\n' "${BOLD}${C}" "$1" "${N}" "${DIM}$2${N}"; hr; }
ok()  { printf '  %s✓%s %s\n' "$G" "$N" "$1"; }
warn(){ printf '  %s⚠%s %s\n' "$Y" "$N" "$1"; }
bad() { printf '  %s✗%s %s\n' "$R" "$N" "$1"; }
kv()  { printf '  %s%-22s%s %s\n' "${DIM}" "$1" "$N" "$2"; }

get() { # get <url> <outfile> [extra curl args...]
  local url="$1" out="$2"; shift 2
  curl -sSL --compressed -A "$UA" --max-time "$TIMEOUT" "$@" "$url" -o "$out" 2>/dev/null
  [ -s "$out" ]
}

# GMGN auth: X-APIKEY header + timestamp + client_id query params.
# timestamp must be within ±5s of server time; client_id is a UUID (replay-safe).
gmgn() { # gmgn <path> <outfile>
  local path="$1" out="$2"
  local ts cid
  ts=$(date +%s)
  cid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c 'import uuid;print(uuid.uuid4())')
  local sep="?"
  case "$path" in *\?*) sep="&";; esac
  curl -sSL --compressed -A "$UA" --max-time "$TIMEOUT" \
       -H "X-APIKEY: ${GMGN_KEY}" \
       "${GMGN_BASE}${path}${sep}timestamp=${ts}&client_id=${cid}" -o "$out" 2>/dev/null
  [ -s "$out" ]
}

# humanise a raw integer with decimals -> "1,234.56"
fmt() {
  python3 - "$@" <<'PY' 2>/dev/null || echo "$1"
import sys
try:
    v = float(sys.argv[1]); d = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    print(f"{v:,.{d}f}")
except Exception:
    print(sys.argv[1])
PY
}

pct() { # pct <ratio-string> -> "12.3%"
  python3 -c "print(f'{float('$1')*100:.1f}%')" 2>/dev/null || echo "-"
}

usage() {
cat <<EOF
${BOLD}free_trade.sh${N} v${VERSION} — zero-cost crypto research + swap quotes

${BOLD}USAGE${N}
  free_trade.sh <command> [args]

${BOLD}COMMANDS${N}
  ${G}audit${N} <token> [chain]      Token security (GMGN): tax, honeypot,
                                  blacklist, renounced, lock, concentration, flags
  ${G}info${N} <token> [chain]       Token fundamentals: supply, holders, liquidity, price
  ${G}pool${N} <token> [chain]       Biggest pool: reserves, liquidity, quote token
  ${G}holders${N} <token> [chain]    Top holders + top traders
  ${G}kline${N} <token> [res] [chain] [days]
                                  OHLCV candles (GMGN). res: 30s/1m/5m/15m/1h/4h/1d
  ${G}liquidity${N} <token> [chain]  DEX liquidity + volume (DexScreener + GeckoTerminal)
  ${G}quote${N} <from> <to> <amt> [chain]
                                  Swap quote: ParaSwap + Li.Fi + baw cross-check
  ${G}scan${N} <token> [chain]       All-in-one: info + audit + pool + liquidity + CEX ref
  ${G}price${N} <symbol>             CEX reference price (Binance public API)
  ${G}ckline${N} <symbol> [iv] [n]   CEX OHLCV candles (Binance public API)
  ${G}trending${N}                    Trending pools (GeckoTerminal)
  ${G}balance${N} [chain]            Wallet balances via baw (needs baw login)
  ${G}chains${N}                      List chains baw supports
  ${G}doctor${N}                      Check which free endpoints are reachable
  ${G}help${N}                        This help

${BOLD}CHAIN IDS${N}
  56=BSC  1=Ethereum  137=Polygon  8453=Base  42161=Arbitrum  501=Solana
  GMGN chain names: bsc / eth / base / sol

${BOLD}EXAMPLES${N}
  free_trade.sh scan 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82 bsc
  free_trade.sh audit 0xe071F5AA90F211A0824e717f1569060193679Ce6 bsc
  free_trade.sh kline 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82 1h bsc 2
  free_trade.sh holders 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82 bsc
  free_trade.sh quote 0xbb4CdB9Cbd36B01bD1cBaEBF2De08d9173bc095c \\
                     0x55d398326f99059fF775485246999027B3197955 1 56
  free_trade.sh price BNBUSDT
  free_trade.sh doctor

${BOLD}ENV${N}
  GMGN_API_KEY    override the public demo key with your own (free at gmgn.ai/ai)
  FT_TIMEOUT      per-request timeout seconds (default 25)

${DIM}All data sources are free and keyless. Execution needs your own wallet.${N}
EOF
}

# chain id -> gmgn chain name
gchain() {
  case "${1:-56}" in
    56|bsc) echo bsc;; 1|eth) echo eth;; 137|polygon) echo polygon;;
    8453|base) echo base;; 42161|arbitrum) echo arbitrum;; 501|sol) echo sol;;
    *) echo "${1:-bsc}";;
  esac
}

# ============================================================================
# doctor — which free endpoints are alive
# ============================================================================
cmd_doctor() {
  hdr "ENDPOINT HEALTH" "all should be free + keyless"
  local -a checks=(
    "GMGN openapi|GMGN"
    "DexScreener|https://api.dexscreener.com/latest/dex/search?q=BNB"
    "GeckoTerminal|https://api.geckoterminal.com/api/v2/networks/trending_pools"
    "ParaSwap|https://api.paraswap.io/chains/56"
    "Li.Fi|https://li.quest/v1/chains"
    "Binance public|https://api.binance.com/api/v3/ping"
    "BSC public RPC|https://bsc-rpc.publicnode.com"
  )
  local entry name url code
  for entry in "${checks[@]}"; do
    name="${entry%%|*}"; url="${entry#*|}"
    if [ "$url" = "GMGN" ]; then
      # GMGN needs X-APIKEY + timestamp + client_id, so probe a real endpoint
      local ts cid probe
      ts=$(date +%s); cid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "00000000-0000-0000-0000-000000000000")
      probe="$TMP/probe.json"
      gmgn "/v1/token/info?chain=bsc&address=0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82" "$probe"
      code=$(jq -r '.code // "err"' "$probe" 2>/dev/null)
      if [ "$code" = "0" ]; then ok "$(printf '%-18s %s' "$name" "code=0 (auth OK)")"
      else bad "$(printf '%-18s %s' "$name" "code=$code")"; fi
      continue
    fi
    code=$(curl -sL -o /dev/null -w '%{http_code}' -A "$UA" --max-time 15 "$url" 2>/dev/null)
    if [ "$code" = "200" ]; then ok "$(printf '%-18s %s' "$name" "HTTP $code")"
    else bad "$(printf '%-18s %s' "$name" "HTTP $code")"; fi
  done
  echo
  kv "GMGN key in use" "${GMGN_KEY:0:14}…"
  command -v baw >/dev/null 2>&1 && ok "baw CLI present ($(baw --version 2>/dev/null | head -1))" \
                                     || warn "baw CLI not on PATH (balance/quote cross-check off)"
  [ -f "${HOME}/.hermes/scripts/evm_tx.py" ] && ok "evm_tx.py present (custom-chain signing)" \
                                                || warn "evm_tx.py not found"
  echo
}

# ============================================================================
# info — GMGN token fundamentals
# ============================================================================
cmd_info() {
  local token="${1:?token address required}" cid; cid=$(gchain "${2:-56}")
  hdr "TOKEN INFO" "$token  (chain $cid)"
  local out="$TMP/info.json"
  if ! gmgn "/v1/token/info?chain=${cid}&address=${token}" "$out"; then
    bad "GMGN request failed"; return 1
  fi
  if ! jq -e '.code == 0' "$out" >/dev/null 2>&1; then
    bad "GMGN error: $(jq -r '.message // .error // "unknown"' "$out" 2>/dev/null)"
    return 1
  fi
  local d; d=$(jq -c '.data' "$out")
  printf '  %s%s%s %s(%s)%s\n' "${BOLD}" "$(jq -r '.symbol // "?"' <<<"$d")" "$N" \
         "${DIM}" "$(jq -r '.name // "-"' <<<"$d")" "$N"
  kv "decimals"        "$(jq -r '.decimals // "-"' <<<"$d")"
  kv "standard"        "$(jq -r '.standard // "-"' <<<"$d")"
  kv "price USD"       "$(jq -r '.price.price // "-"' <<<"$d")"
  kv "total supply"    "$(fmt "$(jq -r '.total_supply // 0' <<<"$d")" 0)"
  kv "circulating"     "$(fmt "$(jq -r '.circulating_supply // 0' <<<"$d")" 0)"
  kv "max supply"      "$(fmt "$(jq -r '.max_supply // 0' <<<"$d")" 0)"
  kv "holders"         "$(jq -r '.holder_count // "-"' <<<"$d")"
  kv "liquidity"       "$(fmt "$(jq -r '.liquidity // 0' <<<"$d")" 0)"
  kv "created"         "$(python3 -c "import datetime;print(datetime.datetime.utcfromtimestamp($(jq -r '.creation_timestamp // 0' <<<"$d")).strftime('%Y-%m-%d %H:%M UTC'))" 2>/dev/null || echo '-')"
  kv "launchpad"       "$(jq -r 'if (.launchpad // "") == "" then "-" else .launchpad end' <<<"$d")"

  echo
  printf '  %sPRICE / ACTIVITY%s\n' "${BOLD}${Y}" "$N"
  local p; p=$(jq -c '.price // {}' <<<"$d")
  kv "price 1m/5m/1h"  "$(jq -r '"\(.price_1m // "-") / \(.price_5m // "-") / \(.price_1h // "-")"' <<<"$p")"
  kv "price 6h/24h"    "$(jq -r '"\(.price_6h // "-") / \(.price_24h // "-")"' <<<"$p")"
  kv "buys 1h/6h/24h"  "$(jq -r '"\(.buys_1h // 0) / \(.buys_6h // 0) / \(.buys_24h // 0)"' <<<"$p")"
  kv "sells 1h/6h/24h" "$(jq -r '"\(.sells_1h // 0) / \(.sells_6h // 0) / \(.sells_24h // 0)"' <<<"$p")"
  kv "volume 1h/24h"   "$(jq -r '"\(.volume_1h // 0) / \(.volume_24h // 0)"' <<<"$p")"
  kv "total fee paid"  "$(fmt "$(jq -r '.total_fee // 0' <<<"$d")" 2) USD"
  echo
}

# ============================================================================
# audit — GMGN token security
# ============================================================================
cmd_audit() {
  local token="${1:?token address required}" cid; cid=$(gchain "${2:-56}")
  hdr "SECURITY AUDIT" "$token  (chain $cid)"
  local out="$TMP/sec.json"
  if ! gmgn "/v1/token/security?chain=${cid}&address=${token}" "$out"; then
    bad "GMGN request failed"; return 1
  fi
  if ! jq -e '.code == 0' "$out" >/dev/null 2>&1; then
    bad "GMGN error: $(jq -r '.message // .error // "unknown"' "$out" 2>/dev/null)"
    return 1
  fi
  local d; d=$(jq -c '.data' "$out")

  printf '  %sFLAGS%s\n' "${BOLD}${Y}" "$N"
  local hp; hp=$(jq -r '.honeypot // -1' <<<"$d")
  if [ "$hp" = "1" ]; then bad "HONEYPOT — cannot sell"
  elif [ "$hp" = "0" ]; then ok "not a honeypot"; else warn "honeypot status unknown ($hp)"; fi

  local bl; bl=$(jq -r '.blacklist // -1' <<<"$d")
  if [ "$bl" = "1" ]; then bad "has blacklist function"
  elif [ "$bl" = "0" ]; then ok "no blacklist"; else warn "blacklist status unknown"; fi

  local os; os=$(jq -r '.open_source // 0' <<<"$d")
  [ "$os" = "1" ] && ok "contract open source" || warn "contract NOT open source"

  local rn; rn=$(jq -r '.renounced // 0' <<<"$d")
  [ "$rn" = "1" ] && ok "ownership renounced" || warn "ownership NOT renounced"

  local rf; rf=$(jq -r '.renounced_freeze_account // false' <<<"$d")
  [ "$rf" = "true" ] && warn "freeze-account privilege renounced" || true
  local rm; rm=$(jq -r '.renounced_mint // false' <<<"$d")
  [ "$rm" = "true" ] && warn "mint privilege renounced" || true

  echo
  printf '  %sTAX%s\n' "${BOLD}${Y}" "$N"
  kv "buy tax"    "$(jq -r '.buy_tax // "-"' <<<"$d")%"
  kv "sell tax"   "$(jq -r '.sell_tax // "-"' <<<"$d")%"
  kv "avg / high" "$(jq -r '"\(.average_tax // "-")% / \(.high_tax // "-")%"' <<<"$d")"
  kv "can sell"   "$(jq -r '.can_sell // "-"' <<<"$d")"

  echo
  printf '  %sCONCENTRATION%s\n' "${BOLD}${Y}" "$N"
  kv "top10 holder rate" "$(pct "$(jq -r '.top_10_holder_rate // 0' <<<"$d")")"
  kv "burn ratio"        "$(pct "$(jq -r '.burn_ratio // 0' <<<"$d")")"
  kv "dev burn ratio"    "$(pct "$(jq -r '.dev_token_burn_ratio // 0' <<<"$d")")"

  echo
  printf '  %sLIQUIDITY LOCK%s\n' "${BOLD}${Y}" "$N"
  local ls; ls=$(jq -c '.lock_summary // {}' <<<"$d")
  kv "locked"        "$(jq -r 'if .is_locked then "yes" else "NO" end' <<<"$ls")"
  kv "lock percent"  "$(pct "$(jq -r '.lock_percent // 0' <<<"$ls")")"
  kv "left unlocked" "$(pct "$(jq -r '.left_lock_percent // 0' <<<"$ls")")"

  local flags; flags=$(jq -r '(.flags // []) | if length == 0 then "none" else join(", ") end' <<<"$d")
  kv "risk flags" "$flags"
  local priv; priv=$(jq -r '(.privileges // []) | if length == 0 then "none" else join(", ") end' <<<"$d")
  kv "privileges" "$priv"
  local alert; alert=$(jq -r '.is_show_alert // false' <<<"$d")
  [ "$alert" = "true" ] && warn "GMGN shows a risk alert on this token"
  echo
}

# ============================================================================
# pool — biggest pool reserves
# ============================================================================
cmd_pool() {
  local token="${1:?token address required}" cid; cid=$(gchain "${2:-56}")
  hdr "BIGGEST POOL" "$token  (chain $cid)"
  local out="$TMP/pool.json"
  if ! gmgn "/v1/token/pool_info?chain=${cid}&address=${token}" "$out"; then
    bad "GMGN request failed"; return 1
  fi
  if ! jq -e '.code == 0' "$out" >/dev/null 2>&1; then
    bad "GMGN error: $(jq -r '.message // .error // "unknown"' "$out" 2>/dev/null)"; return 1
  fi
  local d; d=$(jq -c '.data' "$out")
  kv "pool address"   "$(jq -r '.pool_address // "-"' <<<"$d")"
  kv "quote token"    "$(jq -r '.quote_symbol // "-"' <<<"$d")"
  kv "liquidity USD"  "$(fmt "$(jq -r '.liquidity // 0' <<<"$d")" 0)"
  kv "base reserve"   "$(fmt "$(jq -r '.base_reserve // 0' <<<"$d")" 4)"
  kv "quote reserve"  "$(fmt "$(jq -r '.quote_reserve // 0' <<<"$d")" 4)"
  kv "price USD"      "$(jq -r '.price // "-"' <<<"$d")"
  echo
}

# ============================================================================
# holders — top holders + top traders
# ============================================================================
cmd_holders() {
  local token="${1:?token address required}" cid; cid=$(gchain "${2:-56}")
  hdr "TOP HOLDERS" "$token  (chain $cid)"
  local out="$TMP/holders.json"
  if ! gmgn "/v1/market/token_top_holders?chain=${cid}&address=${token}&limit=15" "$out"; then
    bad "GMGN request failed"; return 1
  fi
  if ! jq -e '.code == 0' "$out" >/dev/null 2>&1; then
    bad "GMGN error: $(jq -r '.message // .error // "unknown"' "$out" 2>/dev/null)"; return 1
  fi
  jq -r '.data.list[:15][] |
    "  #\(.rank // "-")  \(.address[0:10])…\(.address[-4:])  \(.amount | tostring | .[0:18])\n" +
    "       \(.amount_rate // .rate // "-")  \(.is_lp // false | if . then "LP" else "" end) \(.tag // "" | if . == "" then "" else "[" + . + "]" end)"' \
    "$out" 2>/dev/null || warn "no holder data"

  echo
  hdr "TOP TRADERS" "$token  (chain $cid)"
  local out2="$TMP/traders.json"
  if gmgn "/v1/market/token_top_traders?chain=${cid}&address=${token}&limit=10" "$out2" \
     && jq -e '.code == 0' "$out2" >/dev/null 2>&1; then
    jq -r '.data.list[:10][] |
      "  \(.address[0:10])…\(.address[-4:])  buy=$\(.buy_usd // .buy // 0)  sell=$\(.sell_usd // .sell // 0)\n" +
      "       pnl=$\(.profit_usd // .profit // 0)  \(.tag // "")"' \
      "$out2" 2>/dev/null || warn "no trader data"
  else
    warn "trader data unavailable"
  fi
  echo
}

# ============================================================================
# kline — GMGN OHLCV
# ============================================================================
cmd_kline() {
  local token="${1:?token address required}" res="${2:-1h}" cid; cid=$(gchain "${3:-56}")
  local days="${4:-2}"
  hdr "KLINE" "$token  res=$res  chain=$cid  last ${days}d"
  local out="$TMP/k.json"
  local now from
  now=$(( $(date +%s) * 1000 ))
  from=$(( now - days * 86400000 ))
  if ! gmgn "/v1/market/token_kline?chain=${cid}&address=${token}&resolution=${res}&from=${from}&to=${now}" "$out"; then
    bad "GMGN request failed"; return 1
  fi
  if ! jq -e '.code == 0' "$out" >/dev/null 2>&1; then
    bad "GMGN error: $(jq -r '.message // .error // "unknown"' "$out" 2>/dev/null)"; return 1
  fi
  local n; n=$(jq -r '.data.list | length' "$out" 2>/dev/null || echo 0)
  if [ "$n" = "0" ] || [ "$n" = "null" ]; then
    warn "no candles — token may not be trading yet"
  else
    ok "$n candle(s)"
    jq -r '.data.list[] |
      "  \(.time / 1000 | strftime("%m-%d %H:%M"))  O=\(.open)  H=\(.high)  L=\(.low)  C=\(.close)  V=\(.volume)"' \
      "$out" 2>/dev/null | tail -30
  fi
  echo
}

# ============================================================================
# liquidity — DexScreener + GeckoTerminal
# ============================================================================
cmd_liquidity() {
  local token="${1:?token address required}" chain="${2:-56}"
  hdr "LIQUIDITY" "$token"

  local ds="$TMP/ds.json"
  if get "https://api.dexscreener.com/latest/dex/tokens/${token}" "$ds"; then
    local n; n=$(jq -r '.pairs | length' "$ds" 2>/dev/null || echo 0)
    if [ "$n" = "0" ] || [ "$n" = "null" ]; then
      warn "DexScreener: no pairs indexed"
    else
      ok "DexScreener: $n pair(s)"
      jq -r '.pairs[:8][] |
        "  \(.baseToken.symbol)/\(.quoteToken.symbol)  \(.dexId)  \(.chainId)\n" +
        "     price=$\(.priceUsd // "-")  liq=$\(.liquidity.usd // 0 | tostring | .[0:12])  vol24h=$\(.volume.h24 // 0 | tostring | .[0:12])\n" +
        "     chg 1h=\(.priceChange.h1 // "-")%  24h=\(.priceChange.h24 // "-")%  fdv=$\(.fdv // "-")"' \
        "$ds" 2>/dev/null
    fi
  else
    bad "DexScreener request failed"
  fi

  echo
  local gt="$TMP/gt.json"
  local gtnet; case "$chain" in
    56) gtnet="bsc";; 1) gtnet="eth";; 137) gtnet="polygon_pos";;
    8453) gtnet="base";; 42161) gtnet="arbitrum";; 501|sol) gtnet="solana";;
    *) gtnet="bsc";;
  esac
  if get "https://api.geckoterminal.com/api/v2/networks/${gtnet}/tokens/${token}/pools" "$gt"; then
    local gn; gn=$(jq -r '.data | length' "$gt" 2>/dev/null || echo 0)
    if [ "$gn" = "0" ] || [ "$gn" = "null" ]; then
      warn "GeckoTerminal: no pools on $gtnet"
    else
      ok "GeckoTerminal: $gn pool(s) on $gtnet"
      jq -r '.data[:5][] |
        "  \(.attributes.name)\n" +
        "     price=$\(.attributes.base_token_price_usd // "-")  reserve=$\(.attributes.reserve_in_usd // "-")  vol24h=$\(.attributes.volume_usd.h24 // "-")"' \
        "$gt" 2>/dev/null
    fi
  else
    bad "GeckoTerminal request failed"
  fi
  echo
}

# ============================================================================
# quote — ParaSwap + Li.Fi + baw cross-check
# ============================================================================
cmd_quote() {
  local from="${1:?from token required}" to="${2:?to token required}"
  local amt="${3:?amount required}" chain="${4:-$CHAIN_DEFAULT}"

  hdr "SWAP QUOTE" "$from → $to  amount=$amt  chain=$chain"

  local ps_from="$from" ps_to="$to"
  [ "$from" = "BNB" ] || [ "$from" = "native" ] && ps_from="0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
  [ "$to"   = "BNB" ] || [ "$to"   = "native" ] && ps_to="0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

  local dec_from="${DEC_FROM:-18}" dec_to="${DEC_TO:-18}"
  local raw
  raw=$(python3 -c "print(int(float('$amt') * 10**$dec_from))" 2>/dev/null)
  [ -z "$raw" ] && { bad "cannot convert amount '$amt' with $dec_from decimals"; return 1; }

  # ---- ParaSwap ----
  local ps="$TMP/ps.json"
  if get "https://api.paraswap.io/quote" "$ps" \
      -G --data-urlencode "srcToken=$ps_from" \
         --data-urlencode "destToken=$ps_to" \
         --data-urlencode "amount=$raw" \
         --data-urlencode "srcDecimals=$dec_from" \
         --data-urlencode "destDecimals=$dec_to" \
         --data-urlencode "side=SELL" \
         --data-urlencode "network=$chain" \
         --data-urlencode "chainId=$chain"; then
    if jq -e '.delta.destAmount' "$ps" >/dev/null 2>&1; then
      ok "ParaSwap"
      kv "  you receive"  "$(fmt "$(python3 -c "print(float('$(jq -r '.delta.destAmount' "$ps")')/10**$dec_to)" 2>/dev/null)" 6) $to"
      kv "  USD value"    "$(jq -r '.delta.receivedDestUSD // "-"' "$ps")"
      kv "  before fee"   "$(fmt "$(python3 -c "print(float('$(jq -r '.delta.destAmountBeforeFee' "$ps")')/10**$dec_to)" 2>/dev/null)" 6)"
      kv "  gas estimate" "$(jq -r '.gasEstimate // .delta.gasEstimate // "-"' "$ps")"
      kv "  price impact" "$(jq -r '.delta.priceImpact // "-"' "$ps")"
    else
      bad "ParaSwap: $(jq -r '.error // .errorType // "no route"' "$ps" 2>/dev/null | head -c 80)"
    fi
  else
    bad "ParaSwap request failed"
  fi

  echo
  # ---- Li.Fi ----
  local lf="$TMP/lf.json"
  local lf_from="$from" lf_to="$to"
  [ "$from" = "BNB" ] || [ "$from" = "native" ] && lf_from="0x0000000000000000000000000000000000000000"
  [ "$to"   = "BNB" ] || [ "$to"   = "native" ] && lf_to="0x0000000000000000000000000000000000000000"
  if get "https://li.quest/v1/quote" "$lf" \
      -G --data-urlencode "fromChain=$chain" \
         --data-urlencode "toChain=$chain" \
         --data-urlencode "fromToken=$lf_from" \
         --data-urlencode "toToken=$lf_to" \
         --data-urlencode "fromAmount=$raw" \
         --data-urlencode "fromAddress=0xdD1738dD918e224Ea5E4f43237Ba72cB9cC75e3e"; then
    if jq -e '.estimate.toAmount' "$lf" >/dev/null 2>&1; then
      ok "Li.Fi"
      kv "  tool"          "$(jq -r '.tool // "-"' "$lf")"
      kv "  you receive"   "$(fmt "$(python3 -c "print(float('$(jq -r '.estimate.toAmount' "$lf")')/10**$dec_to)" 2>/dev/null)" 6) $to"
      kv "  USD value"     "$(jq -r '.estimate.toAmountUSD // "-"' "$lf")"
      kv "  exec duration" "$(jq -r '.estimate.executionDuration // "-"' "$lf")s"
    else
      bad "Li.Fi: $(jq -r '.message // .error // "no route"' "$lf" 2>/dev/null | head -c 80)"
    fi
  else
    bad "Li.Fi request failed"
  fi

  echo
  # ---- baw cross-check ----
  if command -v baw >/dev/null 2>&1; then
    local bq="$TMP/baw.json"
    if baw market-order quote --json \
         --binanceChainId "$chain" \
         --fromTokenQty "$amt" \
         --fromToken "$from" --toToken "$to" >"$bq" 2>/dev/null && [ -s "$bq" ]; then
      ok "baw (cross-check)"
      jq -r 'to_entries[] | "  \(.key): \(.value)"' "$bq" 2>/dev/null | head -12
    else
      warn "baw quote unavailable (not logged in, or unsupported pair)"
    fi
  fi
  echo
  kv "note" "quotes are indicative — re-quote immediately before execution"
}

# ============================================================================
# scan — info + audit + pool + liquidity + CEX ref
# ============================================================================
cmd_scan() {
  local token="${1:?token address required}" chain="${2:-56}"
  cmd_info      "$token" "$chain"
  cmd_audit     "$token" "$chain"
  cmd_pool      "$token" "$chain"
  cmd_liquidity "$token" "$chain"

  hdr "PRICE REFERENCE" "CEX anchor"
  local sym; sym=$(jq -r '.data.symbol // empty' "$TMP/info.json" 2>/dev/null | tr 'a-z' 'A-Z')
  if [ -n "$sym" ]; then
    local px="$TMP/px.json"
    if get "https://api.binance.com/api/v3/ticker/price?symbol=${sym}USDT" "$px"; then
      kv "$sym/USDT (Binance)" "$(jq -r '.price // "-"' "$px")"
    else
      kv "$sym/USDT (Binance)" "not listed"
    fi
  else
    kv "CEX anchor" "symbol unknown"
  fi
  echo
}

# ============================================================================
# trending — GeckoTerminal
# ============================================================================
cmd_trending() {
  hdr "TRENDING POOLS" "GeckoTerminal, all networks"
  local gt="$TMP/gtp.json"
  if get "https://api.geckoterminal.com/api/v2/networks/trending_pools" "$gt"; then
    jq -r '.data[:15][] |
      "  \(.attributes.name)  [\(.relationships.network.data.id | split("_")[0])]\n" +
      "     price=$\(.attributes.base_token_price_usd)  reserve=$\(.attributes.reserve_in_usd)  vol24h=$\(.attributes.volume_usd.h24)"' \
      "$gt" 2>/dev/null
  else
    bad "GeckoTerminal request failed"
  fi
  echo
}

# ============================================================================
# price / ckline — Binance public API
# ============================================================================
cmd_price() {
  local sym="${1:?symbol required, e.g. BNBUSDT}"
  hdr "PRICE" "$sym"
  local out="$TMP/p.json"
  if get "https://api.binance.com/api/v3/ticker/24hr?symbol=${sym}" "$out"; then
    kv "last"         "$(jq -r '.lastPrice' "$out")"
    kv "24h change"   "$(jq -r '.priceChangePercent' "$out")%"
    kv "24h high/low" "$(jq -r '"\(.highPrice) / \(.lowPrice)"' "$out")"
    kv "24h volume"   "$(jq -r '.volume' "$out")"
    kv "24h quote vol" "$(fmt "$(jq -r '.quoteVolume' "$out")" 0)"
    kv "weighted avg" "$(jq -r '.weightedAvgPrice' "$out")"
  else
    bad "Binance request failed — symbol may not exist"
  fi
  echo
}

cmd_ckline() {
  local sym="${1:?symbol required}" iv="${2:-1h}" lim="${3:-24}"
  hdr "CEX KLINE" "$sym  interval=$iv  limit=$lim"
  local out="$TMP/ck.json"
  if get "https://api.binance.com/api/v3/klines?symbol=${sym}&interval=${iv}&limit=${lim}" "$out"; then
    jq -r '.[] | "  \(.[0] / 1000 | strftime("%Y-%m-%d %H:%M"))  O=\(.[1]) H=\(.[2]) L=\(.[3]) C=\(.[4]) V=\(.[5])"' \
      "$out" 2>/dev/null
  else
    bad "Binance request failed"
  fi
  echo
}

# ============================================================================
# balance / chains — baw passthrough
# ============================================================================
cmd_balance() {
  local chain="${1:-}"
  hdr "WALLET BALANCE" "${chain:-all chains}"
  if ! command -v baw >/dev/null 2>&1; then bad "baw CLI not on PATH"; return 1; fi
  if [ -n "$chain" ]; then
    baw wallet balance --json --binanceChainId "$chain" 2>&1 | jq -C '.' 2>/dev/null || baw wallet balance --binanceChainId "$chain"
  else
    baw wallet balance --json 2>&1 | jq -C '.' 2>/dev/null || baw wallet balance
  fi
  echo
}

cmd_chains() { baw wallet chains 2>&1; }

# ============================================================================
# dispatch
# ============================================================================
case "${1:-help}" in
  audit)     shift; cmd_audit "$@" ;;
  info)      shift; cmd_info "$@" ;;
  pool)      shift; cmd_pool "$@" ;;
  holders)   shift; cmd_holders "$@" ;;
  kline)     shift; cmd_kline "$@" ;;
  liquidity) shift; cmd_liquidity "$@" ;;
  quote)     shift; cmd_quote "$@" ;;
  scan)      shift; cmd_scan "$@" ;;
  trending)  shift; cmd_trending "$@" ;;
  price)     shift; cmd_price "$@" ;;
  ckline)    shift; cmd_ckline "$@" ;;
  balance)   shift; cmd_balance "$@" ;;
  chains)    cmd_chains ;;
  doctor)    cmd_doctor ;;
  help|-h|--help|"") usage ;;
  *) printf '%sUnknown command:%s %s\n\n' "$R" "$N" "$1"; usage; exit 1 ;;
esac
